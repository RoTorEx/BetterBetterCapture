//
//  AssetWriter.swift
//  BetterBetterCapture
//
//  Created by Joshua Sattler on 29.01.26.
//

import AVFoundation
import CoreAudio
import CoreVideo
import Foundation
import OSLog
import ScreenCaptureKit
import VideoToolbox
import os

/// Service responsible for writing captured media to disk using AVAssetWriter
nonisolated final class AssetWriter: CaptureEngineSampleBufferDelegate, @unchecked Sendable {

    // MARK: - Properties

    private var assetWriter: AVAssetWriter?
    private var videoInput: AVAssetWriterInput?
    private var pixelBufferAdaptor: AVAssetWriterInputPixelBufferAdaptor?
    private var audioInput: AVAssetWriterInput?
    private var microphoneInput: AVAssetWriterInput?
    private var recoveryJournal: AudioRecoveryJournal?
    private var recoveryError: Error?
    private var shouldPostProcessAudio = false
    private var activeAudioCodec: AudioCodec = .aac
    private var activeAudioBitrate: AudioBitrate = .standard
    private var activeHasSystemAudio = false
    private var activeHasMicrophone = false
    private var activeMicrophoneMode: MicrophoneProcessingMode = .voice
    private var activeMicrophoneGain: MicrophoneGain = .off
    private var activeSystemGain: AudioGainMode = .off
    private var droppedAudioBufferCount = 0
    private var systemAudioQueue: [CMSampleBuffer] = []
    private var microphoneQueue: [CMSampleBuffer] = []
    private let maximumQueuedAudioBuffers = 192

    private(set) var isWriting = false
    private(set) var outputURL: URL?
    private var finalOutputURL: URL?

    private let logger = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "BetterBetterCapture", category: "AssetWriter")

    // Track if we've received the first sample
    private var didCaptureSamples = false
    private var hasStartedSession = false
    private var sessionStartTime: CMTime = .zero

    /// Last appended video presentation time — used to enforce monotonically
    /// increasing timestamps and protect the writer from timing glitches that
    /// occur when Presenter Overlay composites the camera into the stream.
    private var lastVideoPresentationTime: CMTime = .invalid

    /// The active HDR preset for this recording session, used to select the
    /// correct color properties for the output container and per-frame tagging.
    private var activeHDRPreset: HDRPreset = .sdr

    /// Whether per-frame `CVBufferSetAttachment` color tagging is needed.
    /// True only for ProRes HDR, where `AVVideoColorPropertiesKey` must be omitted.
    private var tagBuffersWithHDRColorimetry = false

    // Lock for thread-safe access to writer state
    private let lock = OSAllocatedUnfairLock()

    private weak var audioLevelMonitor: AudioLevelMonitor?

    init(audioLevelMonitor: AudioLevelMonitor? = nil) {
        self.audioLevelMonitor = audioLevelMonitor
    }

    // MARK: - Setup

    @MainActor private func prepareCapture(url: URL, directory: URL, fileType: AVFileType, settings: SettingsStore) throws -> URL {
        let captureURL = directory.appending(
            path: url.deletingPathExtension().lastPathComponent + "-unprocessed.mov")
        assetWriter = try AVAssetWriter(outputURL: captureURL, fileType: fileType)

        guard let assetWriter else {
            throw AssetWriterError.failedToCreateWriter
        }
        if fileType == .mov || fileType == .mp4 {
            assetWriter.movieFragmentInterval = CMTime(seconds: 2, preferredTimescale: 600)
        }
        recoveryError = nil
        if settings.captureSystemAudio || settings.captureMicrophone {
            recoveryJournal = try AudioRecoveryJournal(directory: directory.appending(
                path: url.deletingPathExtension().lastPathComponent + "-recovery"))
        }

        return captureURL
    }

    /// Prepares the asset writer for recording
    /// - Parameters:
    ///   - url: The output file URL
    ///   - settings: The settings store containing encoding configuration
    ///   - videoSize: The dimensions of the video
    @MainActor func setup(url: URL, settings: SettingsStore, videoSize: CGSize) throws {
        // Ensure output directory exists
        let directory = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Create asset writer. Audio-only recordings use audio-focused file types.
        let fileType: AVFileType
        if settings.captureSystemAudio || settings.captureMicrophone {
            fileType = .mov
        } else if settings.recordAudioOnly {
            fileType = settings.audioCodec == .aac ? .mp4 : .wav
        } else {
            fileType = settings.containerFormat == .mov ? .mov : .mp4
        }
        let captureURL = try prepareCapture(url: url, directory: directory, fileType: fileType, settings: settings)
        guard let assetWriter else { throw AssetWriterError.failedToCreateWriter }

        // Configure video input unless audio-only recording is active
        if !settings.recordAudioOnly {
            let videoSettings = createVideoSettings(from: settings, size: videoSize)
            videoInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
            videoInput?.expectsMediaDataInRealTime = true

            if let videoInput, assetWriter.canAdd(videoInput) {
                assetWriter.add(videoInput)

                // Create pixel buffer adaptor for appending raw pixel buffers from ScreenCaptureKit.
                // Must match the pixel format configured on SCStreamConfiguration in CaptureEngine.
                let pixelFormat: OSType =
                    (settings.captureHDR && settings.videoCodec.supportsHDR)
                    ? settings.videoCodec.hdrPixelFormat
                    : kCVPixelFormatType_32BGRA

                let sourcePixelBufferAttributes: [String: Any] = [
                    kCVPixelBufferPixelFormatTypeKey as String: pixelFormat,
                    kCVPixelBufferWidthKey as String: Int(videoSize.width),
                    kCVPixelBufferHeightKey as String: Int(videoSize.height)
                ]
                pixelBufferAdaptor = AVAssetWriterInputPixelBufferAdaptor(
                    assetWriterInput: videoInput,
                    sourcePixelBufferAttributes: sourcePixelBufferAttributes
                )
            }
        }

        // Configure audio input for system audio
        if settings.captureSystemAudio {
            let audioSettings = createAudioSettings(from: settings)
            audioInput = AVAssetWriterInput(mediaType: .audio, outputSettings: audioSettings)
            audioInput?.expectsMediaDataInRealTime = true

            if let audioInput, assetWriter.canAdd(audioInput) {
                assetWriter.add(audioInput)
            }
        }

        // Configure microphone input as separate track
        if settings.captureMicrophone {
            let micSettings = createAudioSettings(from: settings)
            microphoneInput = AVAssetWriterInput(mediaType: .audio, outputSettings: micSettings)
            microphoneInput?.expectsMediaDataInRealTime = true

            if let microphoneInput, assetWriter.canAdd(microphoneInput) {
                assetWriter.add(microphoneInput)
            }
        }

        activeHDRPreset = settings.hdrPreset
        let isProResHDR = activeHDRPreset != .sdr
            && (settings.videoCodec == .proRes422 || settings.videoCodec == .proRes4444)
        tagBuffersWithHDRColorimetry = isProResHDR

        outputURL = captureURL
        finalOutputURL = url
        didCaptureSamples = false
        hasStartedSession = false
        sessionStartTime = .zero
        lastVideoPresentationTime = .invalid
        frameCount = 0

        shouldPostProcessAudio = settings.captureSystemAudio || settings.captureMicrophone
        activeAudioCodec = settings.audioCodec
        activeAudioBitrate = settings.audioBitrate
        activeHasSystemAudio = settings.captureSystemAudio
        activeHasMicrophone = settings.captureMicrophone
        activeMicrophoneMode = settings.microphoneProcessingMode
        activeMicrophoneGain = settings.microphoneGain
        activeSystemGain = settings.systemAudioGain
        droppedAudioBufferCount = 0
        systemAudioQueue.removeAll(keepingCapacity: true)
        microphoneQueue.removeAll(keepingCapacity: true)

        logger.info(
            """
            AssetWriter configured for output: \(url.lastPathComponent), \
            system gain: \(settings.systemAudioGain.displayName), \
            mic gain: \(settings.microphoneGain.displayName)
            """
        )
    }

    // MARK: - Writing

    /// Starts the writing session
    func startWriting() throws {
        guard let assetWriter, assetWriter.status == .unknown else {
            throw AssetWriterError.writerNotReady
        }

        guard assetWriter.startWriting() else {
            throw AssetWriterError.failedToStartWriting(assetWriter.error)
        }

        isWriting = true
        logger.info("AssetWriter started writing")
    }

    // Track frame counts for debugging
    private var frameCount = 0

    /// Appends a video sample buffer - called synchronously from capture queue
    func appendVideoSample(_ sampleBuffer: CMSampleBuffer) {
        // Check frame status first - only process complete frames
        guard
            let attachmentsArray = CMSampleBufferGetSampleAttachmentsArray(
                sampleBuffer, createIfNecessary: false) as? [[String: Any]],
            let attachments = attachmentsArray.first,
            let statusRawValue = attachments[SCStreamFrameInfo.status.rawValue] as? Int,
            let status = SCFrameStatus(rawValue: statusRawValue)
        else {
            logger.warning("Could not extract frame status from sample buffer")
            return
        }

        guard status == .complete else {
            // Frame is not complete (idle, blank, etc.) - skip silently
            return
        }

        lock.withLockUnchecked {
            guard let assetWriter,
                assetWriter.status == .writing,
                let videoInput,
                videoInput.isReadyForMoreMediaData,
                let adaptor = pixelBufferAdaptor
            else {
                return
            }

            let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)

            // Start session on first sample
            if !hasStartedSession {
                startSessionIfNeeded(assetWriter: assetWriter, sampleBuffer: sampleBuffer)
            } else {
                // Guard against non-monotonic timestamps. Presenter Overlay can
                // cause timing glitches when compositing the camera into the
                // stream; a single bad timestamp permanently fails the writer.
                if lastVideoPresentationTime.isValid
                    && presentationTime <= lastVideoPresentationTime {
                    return
                }
            }

            // Extract pixel buffer from sample buffer
            guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
                logger.warning("No image buffer in complete video frame")
                return
            }

            // Log incoming buffer properties on the first frame to aid HDR debugging.
            if frameCount == 0 {
                logPixelBufferProperties(pixelBuffer)
            }

            // For ProRes HDR, inject BT.2020 / PQ colorimetry directly onto
            // the pixel buffer. AVAssetWriter prohibits AVVideoColorPropertiesKey
            // for the high-bit-depth formats ProRes uses, so we tag each frame
            // to ensure the output file contains correct 'colr' / 'nclx' atoms.
            if tagBuffersWithHDRColorimetry {
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, kCVImageBufferColorPrimaries_ITU_R_2020, .shouldPropagate)
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, kCVImageBufferTransferFunction_SMPTE_ST_2084_PQ, .shouldPropagate)
                CVBufferSetAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, kCVImageBufferYCbCrMatrix_ITU_R_2020, .shouldPropagate)
            }

            // Append using the pixel buffer adaptor
            if adaptor.append(pixelBuffer, withPresentationTime: presentationTime) {
                lastVideoPresentationTime = presentationTime
                frameCount += 1
                if frameCount == 1 {
                    logger.info("First video frame appended successfully")
                }
            } else {
                if let error = assetWriter.error {
                    logger.error(
                        "Failed to append video pixel buffer: \(error.localizedDescription)")
                } else {
                    logger.error("Failed to append video pixel buffer - no error available")
                }
            }
        }
    }

    /// Appends a system audio sample buffer - called synchronously from capture queue
    func appendAudioSample(_ sampleBuffer: CMSampleBuffer) {
        lock.withLockUnchecked {
            guard let assetWriter, assetWriter.status == .writing, let audioInput else {
                return
            }
            let processedBuffer = sampleBuffer
            audioLevelMonitor?.processSystemAudioSample(processedBuffer)
            startSessionIfNeeded(assetWriter: assetWriter, sampleBuffer: processedBuffer)
            journalAudio(processedBuffer, source: "system")
            guard systemAudioQueue.count < maximumQueuedAudioBuffers else {
                droppedAudioBufferCount += 1
                logger.error("System audio FIFO overflow")
                return
            }
            systemAudioQueue.append(processedBuffer)
            droppedAudioBufferCount += Self.drainAudioQueue(&systemAudioQueue, into: audioInput)
        }
    }

    /// Appends a microphone audio sample buffer, applying the configured gain.
    func appendMicrophoneSample(_ sampleBuffer: CMSampleBuffer) {
        lock.withLockUnchecked {
            guard let assetWriter, assetWriter.status == .writing, let microphoneInput else {
                return
            }
            let processedBuffer = sampleBuffer
            audioLevelMonitor?.processMicrophoneSample(processedBuffer)
            startSessionIfNeeded(assetWriter: assetWriter, sampleBuffer: processedBuffer)
            journalAudio(processedBuffer, source: "microphone")
            guard microphoneQueue.count < maximumQueuedAudioBuffers else {
                droppedAudioBufferCount += 1
                logger.error("Microphone FIFO overflow")
                return
            }
            microphoneQueue.append(processedBuffer)
            droppedAudioBufferCount += Self.drainAudioQueue(&microphoneQueue, into: microphoneInput)
        }
    }

    private func journalAudio(_ sample: CMSampleBuffer, source: String) {
        guard recoveryError == nil else { return }
        do {
            try recoveryJournal?.append(sample, source: source, origin: sessionStartTime)
        } catch {
            recoveryError = error
            logger.error("Audio recovery write failed: \(error.localizedDescription)")
        }
    }

    /// Called only after capture has stopped, before another writer is installed.
    func checkpointRecovery() throws {
        try lock.withLockUnchecked { try recoveryJournal?.close() }
    }

    private func startSessionIfNeeded(assetWriter: AVAssetWriter, sampleBuffer: CMSampleBuffer) {
        guard !hasStartedSession else { return }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        assetWriter.startSession(atSourceTime: presentationTime)
        sessionStartTime = presentationTime
        hasStartedSession = true
        didCaptureSamples = true
        logger.info("Session started at time: \(presentationTime.seconds)")
    }

    private static func drainAudioQueue(
        _ queue: inout [CMSampleBuffer], into input: AVAssetWriterInput
    ) -> Int {
        while input.isReadyForMoreMediaData, let sample = queue.first {
            guard input.append(sample) else {
                let dropped = queue.count
                queue.removeAll(keepingCapacity: true)
                return dropped
            }
            queue.removeFirst()
        }
        return 0
    }

    // MARK: - Finalization

    /// Finishes writing and finalizes the output file
    /// - Returns: The output URL and the number of video frames written. A count of zero
    ///            means the file holds audio only, which happens when the capture source
    ///            stopped producing frames while audio kept flowing.
    @concurrent func finishWriting(
        progress: (@Sendable (Double) async -> Void)? = nil
    ) async throws -> (url: URL, videoFrameCount: Int) {
        try checkpointRecovery()
        await flushAudioQueues()
        // First critical section: validate state and mark inputs as finished
        let (writerToFinish, url): (AVAssetWriter, URL)

        do {
            (writerToFinish, url) = try lock.withLockUnchecked {
                guard let assetWriter, isWriting else {
                    throw AssetWriterError.writerNotReady
                }

                guard let url = outputURL else {
                    throw AssetWriterError.noOutputURL
                }

                logger.info(
                    "Finishing writing - status: \(assetWriter.status.rawValue), session started: \(self.hasStartedSession), frames written: \(self.frameCount)"
                )

                // Check if we actually started a session (received at least one frame)
                guard hasStartedSession else {
                    logger.error("No frames were written - session was never started")
                    throw AssetWriterError.noFramesWritten
                }

                // Mark inputs as finished
                videoInput?.markAsFinished()
                audioInput?.markAsFinished()
                microphoneInput?.markAsFinished()

                return (assetWriter, url)
            }
        } catch AssetWriterError.noFramesWritten {
            // Cancel needs to be called outside the lock since it acquires its own lock
            cancel()
            throw AssetWriterError.noFramesWritten
        }

        // Finish writing (outside lock since it's async)
        await writerToFinish.finishWriting()

        let result = try completeWriter(url: url)

        return try await finishProcessing(result: result, progress: progress)
    }

    private func flushAudioQueues() async {
        let deadline = ContinuousClock.now + .seconds(2)
        while ContinuousClock.now < deadline {
            let finished = lock.withLockUnchecked {
                if let audioInput {
                    droppedAudioBufferCount += Self.drainAudioQueue(
                        &systemAudioQueue, into: audioInput)
                }
                if let microphoneInput {
                    droppedAudioBufferCount += Self.drainAudioQueue(
                        &microphoneQueue, into: microphoneInput)
                }
                return systemAudioQueue.isEmpty && microphoneQueue.isEmpty
            }
            if finished { return }
            try? await Task.sleep(for: .milliseconds(2))
        }
        lock.withLockUnchecked {
            droppedAudioBufferCount += systemAudioQueue.count + microphoneQueue.count
            systemAudioQueue.removeAll(keepingCapacity: true)
            microphoneQueue.removeAll(keepingCapacity: true)
        }
    }

    /// Cancels the current writing session
    func cancel() {
        lock.withLockUnchecked {
            let hasCapturedSamples = didCaptureSamples
            // AVAssetWriter.cancelWriting deletes its configured destination.
            // Move an interrupted capture aside before cancelling the writer.
            let preservedURL = preserveCaptureBeforeCancellation()
            assetWriter?.cancelWriting()
            if let preservedURL, let outputURL {
                try? FileManager.default.moveItem(at: preservedURL, to: outputURL)
            }
            isWriting = false
            hasStartedSession = false
            lastVideoPresentationTime = .invalid
            activeHDRPreset = .sdr
            tagBuffersWithHDRColorimetry = false
            frameCount = 0

            // Never delete captured samples on an error or cancellation.
            try? recoveryJournal?.close()
            if let url = outputURL, !hasCapturedSamples {
                try? FileManager.default.removeItem(at: url)
            }

            if !hasCapturedSamples, let journal = recoveryJournal {
                try? FileManager.default.removeItem(at: journal.directory)
            }
            recoveryJournal = nil
            assetWriter = nil
            videoInput = nil
            pixelBufferAdaptor = nil
            audioInput = nil
            microphoneInput = nil
            outputURL = nil
            finalOutputURL = nil
            shouldPostProcessAudio = false
            systemAudioQueue.removeAll(keepingCapacity: true)
            microphoneQueue.removeAll(keepingCapacity: true)

            logger.info("AssetWriter cancelled")
        }
    }

    private func preserveCaptureBeforeCancellation() -> URL? {
        guard didCaptureSamples, let outputURL,
              FileManager.default.fileExists(atPath: outputURL.path) else { return nil }
        let preserved = outputURL.deletingPathExtension()
            .appendingPathExtension(UUID().uuidString + ".mov")
        do {
            try FileManager.default.moveItem(at: outputURL, to: preserved)
            return preserved
        } catch {
            logger.error("Could not preserve interrupted container; audio recovery chunks remain: \(error.localizedDescription)")
            return nil
        }
    }

    // MARK: - Settings Helpers

    @MainActor private func createVideoSettings(from settings: SettingsStore, size: CGSize) -> [String: Any] {
        var videoSettings: [String: Any] = [
            AVVideoWidthKey: Int(size.width),
            AVVideoHeightKey: Int(size.height)
        ]

        let hdrPreset = settings.hdrPreset

        switch settings.videoCodec {
        case .h264:
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.h264

        case .hevc:
            if settings.captureAlphaChannel {
                videoSettings[AVVideoCodecKey] = AVVideoCodecType.hevcWithAlpha
            } else {
                videoSettings[AVVideoCodecKey] = AVVideoCodecType.hevc
            }

        case .proRes422:
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.proRes422

        case .proRes4444:
            videoSettings[AVVideoCodecKey] = AVVideoCodecType.proRes4444
        }

        // Add compression properties for H.264 and HEVC to control bitrate.
        // ProRes codecs use fixed-quality encoding and don't need these.
        if let bpp = settings.videoQuality.bitsPerPixel(for: settings.videoCodec) {
            let frameRate = settings.frameRate.effectiveFrameRate
            let bitrate = Int(size.width * size.height * bpp * frameRate)

            var compressionProperties: [String: Any] = [
                AVVideoAverageBitRateKey: bitrate,
                AVVideoExpectedSourceFrameRateKey: frameRate,
                AVVideoMaxKeyFrameIntervalKey: Int(frameRate * 2)
            ]

            // HEVC HDR: enforce Main 10 profile to prevent 8-bit fallback and
            // enable automatic HDR metadata insertion (HDR10 / Dolby Vision).
            if settings.videoCodec == .hevc && hdrPreset != .sdr {
                compressionProperties[AVVideoProfileLevelKey] =
                    kVTProfileLevel_HEVC_Main10_AutoLevel as String
                compressionProperties[kVTCompressionPropertyKey_HDRMetadataInsertionMode as String] =
                    kVTHDRMetadataInsertionMode_Auto as String
            }

            videoSettings[AVVideoCompressionPropertiesKey] = compressionProperties

            logger.info(
                "Video compression: \(bitrate / 1_000_000) Mbps at \(Int(frameRate)) fps (\(settings.videoQuality.rawValue) quality)"
            )
        }

        // Color space tagging strategy differs by codec:
        //
        // HEVC HDR: Tag via AVVideoColorPropertiesKey with BT.2020 / PQ.
        //   The encoder writes the correct 'colr' atom and VUI parameters.
        //
        // ProRes HDR: Do NOT set AVVideoColorPropertiesKey. AVAssetWriter
        //   prohibits automatic color matching for the high-bit-depth pixel
        //   formats ProRes uses. Instead, BT.2020 / PQ colorimetry is
        //   injected per-frame via CVBufferSetAttachment in appendVideoSample().
        //
        // SDR (all codecs): Tag with Rec. 709 to ensure 'colr' atoms and
        //   VUI parameters are written.
        let isProRes = settings.videoCodec == .proRes422 || settings.videoCodec == .proRes4444

        if isProRes && hdrPreset != .sdr {
            // Color properties are tagged per-frame via CVBufferSetAttachment.
        } else if hdrPreset != .sdr {
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_2020,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_SMPTE_ST_2084_PQ,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_2020
            ]
        } else {
            videoSettings[AVVideoColorPropertiesKey] = [
                AVVideoColorPrimariesKey: AVVideoColorPrimaries_ITU_R_709_2,
                AVVideoTransferFunctionKey: AVVideoTransferFunction_ITU_R_709_2,
                AVVideoYCbCrMatrixKey: AVVideoYCbCrMatrix_ITU_R_709_2
            ]
        }

        return videoSettings
    }

    /// Logs the pixel format, color space, and matrix of an incoming pixel buffer
    /// to help diagnose HDR color mismatches.
    private func logPixelBufferProperties(_ pixelBuffer: CVPixelBuffer) {
        let pixelFormat = CVPixelBufferGetPixelFormatType(pixelBuffer)
        let fourCC = String(format: "%c%c%c%c",
                            (pixelFormat >> 24) & 0xFF,
                            (pixelFormat >> 16) & 0xFF,
                            (pixelFormat >> 8) & 0xFF,
                            pixelFormat & 0xFF)

        let primaries = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferColorPrimariesKey, nil)
            as? String ?? "none"
        let transfer = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferTransferFunctionKey, nil)
            as? String ?? "none"
        let matrix = CVBufferCopyAttachment(pixelBuffer, kCVImageBufferYCbCrMatrixKey, nil)
            as? String ?? "none"

        let colorSpaceName: String
        if let cgColorSpace = CVImageBufferGetColorSpace(pixelBuffer)?.takeUnretainedValue() {
            colorSpaceName = cgColorSpace.name as String? ?? "unnamed"
        } else {
            colorSpaceName = "nil"
        }

        logger.info(
            """
            First frame buffer properties — \
            pixelFormat: \(fourCC) (0x\(String(pixelFormat, radix: 16))), \
            colorPrimaries: \(primaries), \
            transferFunction: \(transfer), \
            yCbCrMatrix: \(matrix), \
            CGColorSpace: \(colorSpaceName)
            """
        )
    }

    @MainActor private func createAudioSettings(from settings: SettingsStore) -> [String: Any] {
        [AVFormatIDKey: kAudioFormatAppleLossless, AVSampleRateKey: 48_000,
         AVNumberOfChannelsKey: 2, AVEncoderBitDepthHintKey: 24]
    }
}

// MARK: - CaptureEngineSampleBufferDelegate

extension AssetWriter {

    private func completeWriter(url: URL) throws -> (url: URL, videoFrameCount: Int) {
        try lock.withLockUnchecked {
            guard let assetWriter else { throw AssetWriterError.writerNotReady }
            if assetWriter.status == .failed {
                let error = assetWriter.error
                logger.error("AssetWriter failed: \(error?.localizedDescription ?? "unknown error")")
                throw AssetWriterError.writingFailed(error)
            }
            isWriting = false
            hasStartedSession = false
            lastVideoPresentationTime = .invalid
            activeHDRPreset = .sdr
            tagBuffersWithHDRColorimetry = false
            logger.info("AssetWriter finished writing \(self.frameCount) frames to: \(url.lastPathComponent)")
            let videoFrameCount = frameCount
            frameCount = 0
            self.assetWriter = nil
            videoInput = nil
            pixelBufferAdaptor = nil
            audioInput = nil
            microphoneInput = nil
            outputURL = nil
            return (url, videoFrameCount)
        }
    }

    @concurrent private func finishProcessing(
        result: (url: URL, videoFrameCount: Int),
        progress: (@Sendable (Double) async -> Void)?
    ) async throws -> (url: URL, videoFrameCount: Int) {
        guard let finalURL = finalOutputURL else { throw AssetWriterError.noOutputURL }
        if let recoveryError { throw recoveryError }
        if droppedAudioBufferCount > 0 {
            throw AssetWriterError.audioBuffersDropped(droppedAudioBufferCount)
        }
        let workingURL = result.url.deletingLastPathComponent().appending(
            path: ".\(UUID().uuidString)-working.\(finalURL.pathExtension)")
        try FileManager.default.copyItem(at: result.url, to: workingURL)
        defer { try? FileManager.default.removeItem(at: workingURL) }
        let audioTracks = try await AVURLAsset(url: result.url).loadTracks(withMediaType: .audio)
        if shouldPostProcessAudio && !audioTracks.isEmpty {
            do {
                let report = try await AudioTrackMixer.mixTracks(
                    in: workingURL,
                    configuration: AudioMixConfiguration(
                        codec: activeAudioCodec, bitrate: activeAudioBitrate,
                        hasSystemAudio: activeHasSystemAudio,
                        hasMicrophone: activeHasMicrophone,
                        microphoneMode: activeMicrophoneMode,
                        microphoneGain: activeMicrophoneGain,
                        systemGain: activeSystemGain),
                    progress: progress)
                logger.info("Audio processed with peak \(report.peakDBFS)dBFS")
                logger.info("AEC ERLE: \(String(describing: report.echoReturnLossEnhancementDB))")
                logger.info("AEC residual echo: \(String(describing: report.residualEchoLikelihood))")
                logger.info("AEC delay: \(String(describing: report.estimatedDelayMS))ms")
            } catch {
                logger.error("Audio processing failed; original capture kept: \(result.url.lastPathComponent)")
                throw error
            }
        }
        shouldPostProcessAudio = false
        // Names are reserved before capture; never overwrite an unrelated output.
        try FileManager.default.moveItem(at: workingURL, to: finalURL)
        let handle = try FileHandle(forWritingTo: finalURL)
        try RecordingFileSync.synchronize(handle)
        try handle.close()
        // Cleanup is best effort and happens only after the destination is durable.
        try? FileManager.default.removeItem(at: result.url)
        if let journal = recoveryJournal {
            try? FileManager.default.removeItem(at: journal.directory)
        }
        recoveryJournal = nil
        finalOutputURL = nil
        return (finalURL, result.videoFrameCount)
    }

    func captureEngine(
        _ engine: CaptureEngine, didOutputVideoSampleBuffer sampleBuffer: CMSampleBuffer
    ) {
        appendVideoSample(sampleBuffer)
    }

    func captureEngine(
        _ engine: CaptureEngine, didOutputAudioSampleBuffer sampleBuffer: CMSampleBuffer
    ) {
        appendAudioSample(sampleBuffer)
    }

    func captureEngine(
        _ engine: CaptureEngine, didOutputMicrophoneSampleBuffer sampleBuffer: CMSampleBuffer
    ) {
        appendMicrophoneSample(sampleBuffer)
    }
}

// MARK: - Errors

nonisolated enum AssetWriterError: LocalizedError {
    case failedToCreateWriter
    case writerNotReady
    case failedToStartWriting(Error?)
    case writingFailed(Error?)
    case noOutputURL
    case noFramesWritten
    case audioBuffersDropped(Int)

    var errorDescription: String? {
        switch self {
        case .failedToCreateWriter:
            return "Failed to create the asset writer."
        case .writerNotReady:
            return "The asset writer is not ready for writing."
        case .failedToStartWriting(let error):
            return "Failed to start writing: \(error?.localizedDescription ?? "Unknown error")"
        case .writingFailed(let error):
            return "Writing failed: \(error?.localizedDescription ?? "Unknown error")"
        case .noOutputURL:
            return "No output URL was configured."
        case .noFramesWritten:
            return "No video frames were captured. Check screen recording permissions."
        case .audioBuffersDropped(let count):
            return "Audio capture could not keep up and dropped \(count) buffers; the partial lossless recording was preserved."
        }
    }
}

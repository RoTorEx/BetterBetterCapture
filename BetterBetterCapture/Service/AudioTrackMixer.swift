import AVFoundation
import Foundation
import WebRTCAudioProcessing

struct AudioProcessingReport: Sendable {
    let echoReturnLossEnhancementDB: Double?
    let residualEchoLikelihood: Double?
    let estimatedDelayMS: Int?
    let peakDBFS: Double
}

struct AudioMixConfiguration: Sendable {
    let codec: AudioCodec
    let bitrate: AudioBitrate
    let hasSystemAudio: Bool
    let hasMicrophone: Bool
    let microphoneMode: MicrophoneProcessingMode
    let microphoneGain: MicrophoneGain
    let systemGain: AudioGainMode
}

/// Converts capture tracks to one final track. Voice mode feeds system audio to
/// WebRTC AEC3 as far-end and processes the microphone in 10 ms frames.
enum AudioTrackMixer {
    private static let sampleRate = 48_000.0
    private static let frameLength = 480

    static func mixTracks(
        in sourceURL: URL,
        configuration: AudioMixConfiguration,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> AudioProcessingReport {
        let asset = AVURLAsset(url: sourceURL)
        let tracks = try await asset.loadTracks(withMediaType: .audio)
        guard !tracks.isEmpty else { throw AudioPostProcessingError.noAudioTracks }

        let readers = try await makeReaders(tracks: tracks, configuration: configuration)
        let duration = try await asset.load(.duration).seconds
        let totalFrames = max(1, Int(ceil(duration * sampleRate)))

        let processedURL = sourceURL.deletingLastPathComponent().appending(
            path: ".\(UUID().uuidString)-processed.\(configuration.codec == .aac ? "m4a" : "wav")")
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: sampleRate,
                                   channels: 2, interleaved: false)!
        var output: AVAudioFile? = try AVAudioFile(forWriting: processedURL,
            settings: outputSettings(codec: configuration.codec, bitrate: configuration.bitrate),
                                     commonFormat: .pcmFormatFloat32, interleaved: false)
        let apm = configuration.microphoneMode == .voice && readers.microphone != nil
            ? bbc_apm_create() : nil
        defer { if let apm { bbc_apm_destroy(apm) } }

        do {
            let peak = try await render(RenderInput(
                totalFrames: totalFrames, readers: readers, configuration: configuration,
                format: format, output: output!, apm: apm), progress: progress)
            output = nil
            try await installProcessedAudio(processedURL, replacingAudioIn: sourceURL,
                hasVideo: !(try await asset.loadTracks(withMediaType: .video)).isEmpty)
            return makeReport(stats: apm.map { bbc_apm_metrics($0) }, peak: peak)
        } catch {
            try? FileManager.default.removeItem(at: processedURL)
            throw error
        }

    }

    private static func makeReport(
        stats: BBCWebRTCAudioMetrics?, peak: Float
    ) -> AudioProcessingReport {
        AudioProcessingReport(
            echoReturnLossEnhancementDB: stats.flatMap {
                $0.echo_return_loss_enhancement_db.isFinite ? $0.echo_return_loss_enhancement_db : nil },
            residualEchoLikelihood: stats.flatMap {
                $0.residual_echo_likelihood.isFinite ? $0.residual_echo_likelihood : nil },
            estimatedDelayMS: stats.flatMap { $0.delay_ms >= 0 ? Int($0.delay_ms) : nil },
            peakDBFS: 20 * log10(max(Double(peak), 0.000_000_1)))
    }

    private static func makeReaders(
        tracks: [AVAssetTrack], configuration: AudioMixConfiguration
    ) async throws -> TrackReaders {
        var index = 0
        let systemTrack = configuration.hasSystemAudio && index < tracks.count ? tracks[index] : nil
        if systemTrack != nil { index += 1 }
        let microphoneTrack = configuration.hasMicrophone && index < tracks.count ? tracks[index] : nil
        var starts: [Double] = []
        for track in [systemTrack, microphoneTrack].compactMap({ $0 }) {
            starts.append(try await track.load(.timeRange).start.seconds)
        }
        let origin = starts.min() ?? 0
        let system = try await makeReader(track: systemTrack, origin: origin)
        let microphone = try await makeReader(track: microphoneTrack, origin: origin)
        return TrackReaders(system: system, microphone: microphone)
    }

    private static func makeReader(track: AVAssetTrack?, origin: Double) async throws -> PCMTrackReader? {
        guard let track else { return nil }
        return try await PCMTrackReader(track: track, origin: origin)
    }

    private static func render(
        _ input: RenderInput, progress: (@Sendable (Double) -> Void)?
    ) async throws -> Float {
        var limiter = StreamingLimiter(ceiling: pow(10, -1.0 / 20.0), releaseSeconds: 0.1)
        var rendered = 0
        var peak: Float = 0
        while rendered < input.totalFrames {
            try Task.checkCancellation()
            let count = min(frameLength, input.totalFrames - rendered)
            var system = try input.readers.system?.read(count: count) ?? .init(repeating: 0, count: count)
            var microphone = try input.readers.microphone?.read(count: count) ?? .init(repeating: 0, count: count)
            try processMicrophone(system: &system, microphone: &microphone,
                                  configuration: input.configuration, apm: input.apm)
            let buffer = try makeMixedBuffer(frame: MixFrame(
                system: system, microphone: microphone, count: count,
                systemScale: input.configuration.hasMicrophone ? 0.7 : 1,
                microphoneScale: input.configuration.hasSystemAudio ? 0.85 : 1),
                                             format: input.format,
                                             limiter: &limiter, peak: &peak)
            try input.output.write(from: buffer)
            rendered += count
            progress?(min(1, Double(rendered) / Double(input.totalFrames)))
        }
        return peak
    }

    private static func processMicrophone(
        system: inout [Float], microphone: inout [Float],
        configuration: AudioMixConfiguration, apm: OpaquePointer?
    ) throws {
        applyFixedGain(configuration.systemGain, to: &system)
        guard configuration.microphoneMode == .voice, let apm else {
            applyFixedGain(configuration.microphoneGain, to: &microphone)
            return
        }
        let count = microphone.count
        if count < frameLength {
            system += .init(repeating: 0, count: frameLength - count)
            microphone += .init(repeating: 0, count: frameLength - count)
        }
        let status = system.withUnsafeBufferPointer { render in
            microphone.withUnsafeMutableBufferPointer { capture in
                bbc_apm_process(apm, render.baseAddress, capture.baseAddress, 0)
            }
        }
        guard status == 0 else { throw AudioPostProcessingError.webRTC(status) }
    }

    private static func makeMixedBuffer(
        frame: MixFrame, format: AVAudioFormat,
        limiter: inout StreamingLimiter, peak: inout Float
    ) throws -> AVAudioPCMBuffer {
        guard let buffer = AVAudioPCMBuffer(
            pcmFormat: format, frameCapacity: AVAudioFrameCount(frame.count)),
              let channels = buffer.floatChannelData else {
            throw AudioPostProcessingError.cannotAllocateBuffer
        }
        buffer.frameLength = AVAudioFrameCount(frame.count)
        for sample in 0..<frame.count {
            let value = limiter.process(
                frame.system[sample] * frame.systemScale
                    + frame.microphone[sample] * frame.microphoneScale)
            channels[0][sample] = value
            channels[1][sample] = value
            peak = max(peak, abs(value))
        }
        return buffer
    }

    private static func applyFixedGain(_ mode: AudioGainMode, to samples: inout [Float]) {
        guard mode != .auto, mode != .off else { return }
        let multiplier = Float(mode.linearGain)
        for index in samples.indices { samples[index] *= multiplier }
    }

    private static func installProcessedAudio(_ audioURL: URL, replacingAudioIn sourceURL: URL,
                                              hasVideo: Bool) async throws {
        if !hasVideo {
            _ = try FileManager.default.replaceItemAt(sourceURL, withItemAt: audioURL)
            return
        }
        let composition = AVMutableComposition()
        let source = AVURLAsset(url: sourceURL)
        let audio = AVURLAsset(url: audioURL)
        for track in try await source.loadTracks(withMediaType: .video) {
            let range = try await track.load(.timeRange)
            guard let destination = composition.addMutableTrack(withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
                throw AudioPostProcessingError.cannotCreateComposition
            }
            try destination.insertTimeRange(range, of: track, at: range.start)
        }
        guard let track = try await audio.loadTracks(withMediaType: .audio).first,
              let destination = composition.addMutableTrack(withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw AudioPostProcessingError.noAudioTracks
        }
        let range = try await track.load(.timeRange)
        try destination.insertTimeRange(range, of: track, at: .zero)
        let finalURL = sourceURL.deletingLastPathComponent().appending(
            path: ".\(UUID().uuidString)-final.\(sourceURL.pathExtension)")
        guard let exporter = AVAssetExportSession(asset: composition,
                                                  presetName: AVAssetExportPresetPassthrough) else {
            throw AudioPostProcessingError.cannotCreateComposition
        }
        let fileType: AVFileType = sourceURL.pathExtension.lowercased() == "mp4" ? .mp4 : .mov
        try await exporter.export(to: finalURL, as: fileType)
        _ = try FileManager.default.replaceItemAt(sourceURL, withItemAt: finalURL)
        try? FileManager.default.removeItem(at: audioURL)
    }

    private static func outputSettings(codec: AudioCodec, bitrate: AudioBitrate) -> [String: Any] {
        if codec == .aac {
            return [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
                    AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: bitrate.rawValue]
        }
        return [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
                AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                AVLinearPCMIsNonInterleaved: false]
    }
}

private struct TrackReaders {
    let system: PCMTrackReader?
    let microphone: PCMTrackReader?
}

private struct RenderInput {
    let totalFrames: Int
    let readers: TrackReaders
    let configuration: AudioMixConfiguration
    let format: AVAudioFormat
    let output: AVAudioFile
    let apm: OpaquePointer?
}

private struct MixFrame {
    let system: [Float]
    let microphone: [Float]
    let count: Int
    let systemScale: Float
    let microphoneScale: Float
}

private final class PCMTrackReader {
    private let reader: AVAssetReader
    private let output: AVAssetReaderTrackOutput
    private var queue: [Float] = []
    private var offset = 0
    private var leadingSilence: Int

    init(track: AVAssetTrack, origin: Double) async throws {
        guard let asset = track.asset else { throw AudioPostProcessingError.cannotReadTrack }
        reader = try AVAssetReader(asset: asset)
        output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48_000,
            AVNumberOfChannelsKey: 1, AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false])
        guard reader.canAdd(output) else { throw AudioPostProcessingError.cannotReadTrack }
        reader.add(output)
        let start = try await track.load(.timeRange).start.seconds
        leadingSilence = max(0, Int(round((start - origin) * 48_000)))
        guard reader.startReading() else { throw reader.error ?? AudioPostProcessingError.cannotReadTrack }
    }

    func read(count: Int) throws -> [Float] {
        var result: [Float] = []
        result.reserveCapacity(count)
        if leadingSilence > 0 {
            let amount = min(leadingSilence, count)
            result += .init(repeating: 0, count: amount)
            leadingSilence -= amount
        }
        while result.count < count {
            if offset < queue.count {
                let amount = min(count - result.count, queue.count - offset)
                result.append(contentsOf: queue[offset..<(offset + amount)])
                offset += amount
                continue
            }
            queue.removeAll(keepingCapacity: true)
            offset = 0
            guard let sample = output.copyNextSampleBuffer() else {
                if reader.status == .failed { throw reader.error ?? AudioPostProcessingError.cannotReadTrack }
                result += .init(repeating: 0, count: count - result.count)
                break
            }
            guard let block = CMSampleBufferGetDataBuffer(sample) else { continue }
            let bytes = CMBlockBufferGetDataLength(block)
            queue = .init(repeating: 0, count: bytes / MemoryLayout<Float>.size)
            let status = queue.withUnsafeMutableBytes {
                CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes,
                                           destination: $0.baseAddress!)
            }
            guard status == noErr else { throw AudioPostProcessingError.cannotReadTrack }
        }
        return result
    }
}

struct StreamingLimiter {
    let ceiling: Float
    private let releaseCoefficient: Float
    private var gain: Float = 1

    init(ceiling: Double, releaseSeconds: Double, sampleRate: Double = 48_000) {
        self.ceiling = Float(ceiling)
        releaseCoefficient = Float(exp(-1 / (releaseSeconds * sampleRate)))
    }

    mutating func process(_ sample: Float) -> Float {
        let desired = abs(sample) > ceiling ? ceiling / abs(sample) : 1
        gain = desired < gain ? desired : 1 - ((1 - gain) * releaseCoefficient)
        return max(-ceiling, min(ceiling, sample * gain))
    }
}

enum AudioPostProcessingError: LocalizedError {
    case noAudioTracks, cannotReadTrack, cannotAllocateBuffer, cannotCreateComposition
    case webRTC(Int32)

    var errorDescription: String? {
        switch self {
        case .noAudioTracks: "The recording contains no audio track."
        case .cannotReadTrack: "An audio track could not be decoded."
        case .cannotAllocateBuffer: "An audio processing buffer could not be allocated."
        case .cannotCreateComposition: "The final media container could not be created."
        case .webRTC(let status): "WebRTC audio processing failed (\(status))."
        }
    }
}

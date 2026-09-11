import AVFoundation
import Foundation
import Testing
import WebRTCAudioProcessing
@testable import BetterBetterCapture

struct AudioProcessingTests {
    @Test func limiterKeepsSamplesBelowMinusOneDBFS() {
        var limiter = StreamingLimiter(ceiling: 0.891_250_9, releaseSeconds: 0.1)
        let output = (0..<2_000).map { _ in limiter.process(1.8) }
        #expect(output.allSatisfy { abs($0) <= 0.891_251 })
    }

    @Test func limiterLeavesQuietSamplesUnchanged() {
        var limiter = StreamingLimiter(ceiling: 0.891_250_9, releaseSeconds: 0.1)
        #expect(limiter.process(0.25) == 0.25)
    }

    @Test func webRTCAttenuatesCorrelatedSpeakerEcho() throws {
        let processor = try #require(bbc_apm_create())
        defer { bbc_apm_destroy(processor) }
        var generator = SeededNoise(seed: 0xBEEF)
        var inputEnergy = 0.0
        var outputEnergy = 0.0
        for frameIndex in 0..<400 {
            let render = (0..<480).map { _ in generator.next() * 0.2 }
            var microphone = render.map { $0 * 0.6 }
            let input = microphone.reduce(0) { $0 + Double($1 * $1) }
            let status = render.withUnsafeBufferPointer { farEnd in
                microphone.withUnsafeMutableBufferPointer { nearEnd in
                    bbc_apm_process(processor, farEnd.baseAddress, nearEnd.baseAddress, 0)
                }
            }
            #expect(status == 0)
            if frameIndex >= 300 {
                inputEnergy += input
                outputEnergy += microphone.reduce(0) { $0 + Double($1 * $1) }
            }
        }
        #expect(outputEnergy < inputEnergy * 0.5)
    }

    @Test func mixerProducesOneEncodedTrackFromLosslessSources() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let systemURL = directory.appending(path: "system.wav")
        let micURL = directory.appending(path: "mic.wav")
        try writeTone(to: systemURL, frequency: 440)
        try writeTone(to: micURL, frequency: 880)

        let sourceURL = directory.appending(path: "source.mov")
        let composition = AVMutableComposition()
        for url in [systemURL, micURL] {
            let asset = AVURLAsset(url: url)
            let track = try #require(await asset.loadTracks(withMediaType: .audio).first)
            let range = try await track.load(.timeRange)
            let destination = try #require(composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid))
            try destination.insertTimeRange(range, of: track, at: .zero)
        }
        let exporter = try #require(AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetPassthrough))
        try await exporter.export(to: sourceURL, as: .mov)

        let recordedProgress = ProgressRecorder()
        _ = try await AudioTrackMixer.mixTracks(
            in: sourceURL,
            configuration: AudioMixConfiguration(
                codec: .aac, bitrate: .standard, hasSystemAudio: true,
                hasMicrophone: true, microphoneMode: .voice,
                microphoneGain: .off, systemGain: .off)
        ) { recordedProgress.append($0) }

        let result = AVURLAsset(url: sourceURL)
        #expect(try await result.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await result.load(.duration).seconds > 0.15)
        let progress = recordedProgress.values
        #expect(progress.last == 1)
        #expect(progress.dropLast().allSatisfy { $0 <= 0.9 })
    }

    @Test func mixerAwaitsFinalProgressDeliveryBeforeReturning() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let sourceURL = directory.appending(path: "source.wav")
        try writeTone(to: sourceURL, frequency: 440)

        let progress = AsyncProgressRecorder()
        _ = try await AudioTrackMixer.mixTracks(
            in: sourceURL,
            configuration: AudioMixConfiguration(
                codec: .pcm, bitrate: .standard, hasSystemAudio: true,
                hasMicrophone: false, microphoneMode: .raw,
                microphoneGain: .off, systemGain: .off)
        ) { value in
            if value == 1 {
                await Task.yield()
                await progress.markFinalDelivered()
            }
        }

        #expect(await progress.finalDelivered)
    }

    @Test func processingProgressIsBoundedForInterviewLengthRecording() {
        var gate = ProcessingProgressGate(minimumStep: 0.01)
        let frameCount = 506_998 // 84:29.98 at one update per 10 ms audio frame
        let values = (1...frameCount).compactMap { frame in
            gate.valueToReport(Double(frame) / Double(frameCount))
        }

        #expect(values.count <= 102)
        #expect(values.last == 1)
        #expect(zip(values, values.dropFirst()).allSatisfy { pair in pair.0 < pair.1 })

        #expect(gate.valueToReport(1) == nil)
        #expect(gate.valueToReport(0.5) == nil)
        #expect(gate.valueToReport(.nan) == nil)
        #expect(gate.valueToReport(.infinity) == nil)
    }

    private func writeTone(to url: URL, frequency: Double) throws {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1)!
        let file = try AVAudioFile(forWriting: url, settings: format.settings)
        let frames: AVAudioFrameCount = 9_600
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        let samples = buffer.floatChannelData![0]
        for index in 0..<Int(frames) {
            samples[index] = Float(sin(2 * .pi * frequency * Double(index) / 48_000) * 0.1)
        }
        try file.write(from: buffer)
    }
}

private final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Double] = []

    var values: [Double] {
        lock.withLock { recordedValues }
    }

    func append(_ value: Double) {
        lock.withLock { recordedValues.append(value) }
    }
}

private actor AsyncProgressRecorder {
    private(set) var finalDelivered = false

    func markFinalDelivered() {
        finalDelivered = true
    }
}

private struct SeededNoise {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Float {
        state = state &* 6_364_136_223_846_793_005 &+ 1
        return Float(Int32(truncatingIfNeeded: state >> 32)) / Float(Int32.max)
    }
}

import AVFoundation
import Foundation
import Testing
@testable import BetterBetterCapture

@MainActor
extension AssetWriterTests {
    @Test func processedVideoKeepsMP4ContainerAndReadableTracks() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = makeStore()
        settings.captureSystemAudio = true
        settings.captureMicrophone = false
        settings.containerFormat = .mp4
        let writer = AssetWriter()
        try writer.setup(url: directory.appending(path: "video.mp4"), settings: settings, videoSize: videoSize)
        try writer.startWriting()
        for index in 0..<5 {
            writer.appendVideoSample(try makeVideoSampleBuffer(at: CMTime(value: Int64(index), timescale: 60)))
            writer.appendAudioSample(try makeSilentAudioSampleBuffer(
                at: CMTime(value: Int64(index * 1024), timescale: 48_000)))
        }
        let result = try await writer.finishWriting()
        let asset = AVURLAsset(url: result.url)
        #expect(try await asset.loadTracks(withMediaType: .video).count == 1)
        #expect(try await asset.loadTracks(withMediaType: .audio).count == 1)
        #expect(try await asset.load(.isPlayable))
        let header = try Data(contentsOf: result.url)
        #expect(String(data: header[4..<8], encoding: .ascii) == "ftyp")
        #expect(String(data: header[8..<12], encoding: .ascii) != "qt  ")
    }

    @Test func openRecoveryFragmentIsReadableBeforeStopAndPreservesBothChannels() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try AudioRecoveryJournal(directory: directory)
        try journal.append(makeNonInterleavedFloatAudioSampleBuffer(leftSample: 0.25, rightSample: 0.5),
                           source: "system", origin: .zero)
        let url = try #require(FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .first { $0.pathExtension == "caf" })
        // No close(), cancel(), finishWriting(), or object destruction before reading.
        let audio = try AVAudioFile(forReading: url)
        let pcm = try #require(AVAudioPCMBuffer(pcmFormat: audio.processingFormat, frameCapacity: 4))
        try audio.read(into: pcm)
        #expect(pcm.frameLength == 4)
        let channels = try #require(pcm.floatChannelData)
        #expect(channels[0][0] == 0.25)
        #expect(channels[1][0] == 0.5)
        try journal.close()
    }

    @Test func interruptedCaptureKeepsPlayableClosedAudioChunks() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = makeStore()
        settings.recordAudioOnly = true
        settings.captureSystemAudio = true
        let url = directory.appending(path: "interrupted.m4a")
        let writer = AssetWriter()
        try writer.setup(url: url, settings: settings, videoSize: videoSize)
        try writer.startWriting()
        for index in 0..<100 {
            writer.appendAudioSample(try makeSilentAudioSampleBuffer(
                at: CMTime(value: CMTimeValue(index * 1024), timescale: 48_000)))
        }
        // Read while the writer is still open: no Stop or finalization has run.
        let recovery = directory.appending(path: "interrupted-recovery")
        let chunks = try FileManager.default.contentsOfDirectory(at: recovery, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "caf" && !$0.lastPathComponent.contains("partial") }
        let chunk = try #require(chunks.first)
        let audio = try AVAudioFile(forReading: chunk)
        #expect(audio.length >= 96_000)
        #expect(audio.fileFormat.channelCount == 2)
        writer.cancel()
        #expect(FileManager.default.fileExists(atPath: chunk.path))
        #expect(FileManager.default.fileExists(atPath: directory.appending(path: "interrupted-unprocessed.mov").path))
    }

    @Test func failedDestinationInstallationPreservesOriginalAndRecovery() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = makeStore()
        settings.recordAudioOnly = true
        settings.captureSystemAudio = true
        let url = directory.appending(path: "failed.m4a")
        let writer = AssetWriter()
        try writer.setup(url: url, settings: settings, videoSize: videoSize)
        try writer.startWriting()
        for index in 0..<10 {
            writer.appendAudioSample(try makeSilentAudioSampleBuffer(
                at: CMTime(value: CMTimeValue(index * 1024), timescale: 48_000)))
        }
        let sentinel = Data("existing user file".utf8)
        try sentinel.write(to: url)
        await #expect(throws: (any Error).self) { try await writer.finishWriting() }
        writer.cancel()
        #expect(try Data(contentsOf: url) == sentinel)
        let original = directory.appending(path: "failed-unprocessed.mov")
        #expect(try await AVURLAsset(url: original).loadTracks(withMediaType: .audio).count == 1)
        let chunks = try FileManager.default.contentsOfDirectory(
            at: directory.appending(path: "failed-recovery"), includingPropertiesForKeys: nil)
        #expect(chunks.contains { $0.pathExtension == "caf" })
    }

    @Test func newWriterCanRecordWhilePreviousWriterIsProcessing() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let settings = makeStore()
        settings.recordAudioOnly = true
        settings.captureSystemAudio = true
        let first = AssetWriter()
        try first.setup(url: directory.appending(path: "first.m4a"), settings: settings, videoSize: videoSize)
        try first.startWriting()
        first.appendAudioSample(try makeSilentAudioSampleBuffer(at: .zero))
        let second = AssetWriter()
        try second.setup(url: directory.appending(path: "second.m4a"), settings: settings, videoSize: videoSize)
        try second.startWriting()
        let firstResult = try await first.finishWriting { _ in
            await MainActor.run {
                if let sample = try? makeSilentAudioSampleBuffer(at: .zero) { second.appendAudioSample(sample) }
            }
        }
        let secondResult = try await second.finishWriting()
        for result in [firstResult, secondResult] {
            #expect(try await AVURLAsset(url: result.url).loadTracks(withMediaType: .audio).count == 1)
        }
        let files = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(files.sorted() == ["first.m4a", "second.m4a"])
    }

}

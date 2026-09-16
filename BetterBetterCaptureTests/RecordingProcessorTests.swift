import Foundation
import Testing
@testable import BetterBetterCapture

@MainActor
struct RecordingProcessorTests {
    @Test func queuedProcessingIsSerialAndDoesNotBlockCaptureControls() async {
        let processor = RecordingProcessor()
        let latch = ProcessingLatch()
        var order: [String] = []
        processor.enqueue(filename: "first") { progress in
            order.append("first started")
            await progress(0.5)
            await latch.wait()
            order.append("first finished")
        }
        processor.enqueue(filename: "second") { progress in
            order.append("second started")
            await progress(1)
        }
        while processor.recordings.first?.progress != 0.5 { await Task.yield() }
        #expect(processor.recordings.count == 2)
        #expect(processor.recordings[1].startedAt == nil)
        #expect(order == ["first started"])
        let viewModel = RecorderViewModel(settings: SettingsStore(defaults: UserDefaults(suiteName: UUID().uuidString)!), recordingProcessor: processor)
        viewModel.settings.recordAudioOnly = true
        viewModel.settings.captureSystemAudio = true
        #expect(viewModel.canStartRecording)
        await latch.release()
        while !processor.recordings.isEmpty { await Task.yield() }
        #expect(order == ["first started", "first finished", "second started"])
    }

    @Test func elapsedTimeContinuesAcrossMinuteBoundary() {
        let start = Date(timeIntervalSince1970: 0)
        let recording = ProcessingRecording(id: UUID(), filename: "test", stoppedAt: start, startedAt: start)
        #expect(recording.elapsed(at: start.addingTimeInterval(65)) == "0:01:05")
    }
}

private actor ProcessingLatch {
    private var continuation: CheckedContinuation<Void, Never>?
    private var released = false

    func wait() async {
        guard !released else { return }
        await withCheckedContinuation { continuation = $0 }
    }
    func release() {
        released = true
        continuation?.resume()
        continuation = nil
    }
}

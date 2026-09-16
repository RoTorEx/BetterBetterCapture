import Foundation

/// One processing worker avoids competing encoders while capture remains available.
@MainActor
@Observable
final class RecordingProcessor {
    private(set) var recordings: [ProcessingRecording] = []
    private var pending: [Work] = []
    private var worker: Task<Void, Never>?

    private struct Work {
        let id: UUID
        let run: (@Sendable @escaping (Double) async -> Void) async -> Void
    }

    func enqueue(filename: String,
                 run: @escaping (@Sendable @escaping (Double) async -> Void) async -> Void) {
        let id = UUID()
        recordings.append(ProcessingRecording(id: id, filename: filename, stoppedAt: Date()))
        pending.append(Work(id: id, run: run))
        guard worker == nil else { return }
        worker = Task { await drain() }
    }

    private func drain() async {
        while !pending.isEmpty {
            let work = pending.removeFirst()
            if let index = recordings.firstIndex(where: { $0.id == work.id }) {
                recordings[index].startedAt = Date()
            }
            await work.run { [weak self] value in
                await self?.update(value, id: work.id)
            }
            recordings.removeAll { $0.id == work.id }
        }
        worker = nil
    }

    private func update(_ value: Double, id: UUID) {
        guard value.isFinite, let index = recordings.firstIndex(where: { $0.id == id }) else { return }
        recordings[index].progress = min(1, max(recordings[index].progress, value))
    }
}

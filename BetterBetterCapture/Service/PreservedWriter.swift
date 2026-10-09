import AVFoundation

/// A single owner keeps a writer alive while it finalizes an interrupted original.
/// No capture thread uses this writer after cancellation has handed it off.
nonisolated final class PreservedWriter: @unchecked Sendable {
    private let writer: AVAssetWriter

    init(_ writer: AVAssetWriter) { self.writer = writer }

    func finish() {
        writer.finishWriting { _ = self }
    }
}

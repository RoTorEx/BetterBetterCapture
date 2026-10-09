import Foundation

/// Timeout, interruption and reply race; only the first completion resumes.
nonisolated final class BridgeReply: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<String, Error>?
    var connection: NSXPCConnection?

    init(continuation: CheckedContinuation<String, Error>) { self.continuation = continuation }
    func finish(_ result: Result<String, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()
        guard let continuation else { return }
        continuation.resume(with: result)
        connection?.invalidate()
    }
}

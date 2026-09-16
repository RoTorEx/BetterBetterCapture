import Darwin
import Foundation
import OSLog

nonisolated enum RecordingFileSync {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BetterBetterCapture",
                                       category: "RecordingFileSync")

    /// Request hardware-cache flushing as well as the ordinary filesystem flush.
    /// Unsupported volumes retain fsync's weaker guarantee; real I/O errors fail.
    static func synchronize(_ file: FileHandle) throws {
        try file.synchronize()
        while fcntl(file.fileDescriptor, F_FULLFSYNC) == -1 {
            let failure = errno
            if failure == EINTR { continue }
            if failure == ENOTSUP || failure == EINVAL || failure == ENOSYS {
                logger.warning("Output volume does not support full hardware synchronization; using filesystem synchronization")
                return
            }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure))
        }
    }
}

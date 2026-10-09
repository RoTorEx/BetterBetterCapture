import Darwin
import Foundation
import OSLog

nonisolated enum RecordingFileSync {
    private static let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "BetterBetterCapture",
                                       category: "RecordingFileSync")

    static func synchronizeDirectory(_ directory: URL) throws {
        let descriptor = open(directory.path, O_RDONLY)
        guard descriptor >= 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno)) }
    }

    static func write(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent().appending(path: "." + UUID().uuidString + ".tmp")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try data.write(to: temporary)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try synchronize(handle)
        guard rename(temporary.path, destination.path) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        try synchronizeDirectory(destination.deletingLastPathComponent())
    }

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

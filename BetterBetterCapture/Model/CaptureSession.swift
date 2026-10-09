import Foundation

nonisolated struct CaptureSession: Codable, Identifiable, Sendable {
    var id: UUID
    var startedAt: Date
    var directory: URL
    var bookmark: Data?
    var name: String
    var profile: String
    var state: String
    var savedFile: URL?
    var transcript: URL?
    var error: String?
}

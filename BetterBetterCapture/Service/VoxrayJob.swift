import Foundation

nonisolated struct VoxrayJob: Decodable, Sendable {
    let id: String
    let stage: String
    let recording: String
    let transcript: String
    let error: String?
}

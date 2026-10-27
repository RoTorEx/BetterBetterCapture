import Foundation

nonisolated struct VoxrayJob: Decodable, Sendable {
    let id: String
    let stage: String
    let recording: String
    let transcript: String
    let error: String?
    var mediaRemoved: Bool?

    enum CodingKeys: String, CodingKey {
        case id, stage, recording, transcript, error
        case mediaRemoved = "media_removed"
    }
}

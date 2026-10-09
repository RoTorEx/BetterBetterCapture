import Foundation

nonisolated struct VoxrayRequest: Encodable {
    let recordingId: String
    let recording: String
    let recordedAt: String
    let profile: String
    let name: String

    enum CodingKeys: String, CodingKey {
        case recordingId = "recording_id"
        case recording
        case recordedAt = "recorded_at"
        case profile, name
    }
}

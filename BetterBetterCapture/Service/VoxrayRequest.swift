import Foundation

nonisolated struct VoxrayRequest: Encodable {
    let recordingId: String
    let recording: String
    let recordedAt: String
    let profile: String
    let name: String
    let transcribe: Bool
    let keepVideo: Bool
    var googleDrive: Bool?
    var transcriptOnly: Bool?

    enum CodingKeys: String, CodingKey {
        case recordingId = "recording_id"
        case recording
        case recordedAt = "recorded_at"
        case profile, name, transcribe
        case keepVideo = "keep_video"
        case googleDrive = "google_drive"
        case transcriptOnly = "transcript_only"
    }
}

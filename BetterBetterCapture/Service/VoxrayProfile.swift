import Foundation

nonisolated struct VoxrayProfile: Decodable, Identifiable, Sendable {
    let id: String
    let callsDir: String
    var keepVideo: Bool?
    var googleDrive: Bool?
    var driveFolder: String?
    var driveSupported: Bool?

    enum CodingKeys: String, CodingKey {
        case id
        case callsDir = "calls_dir"
        case keepVideo = "keep_video"
        case googleDrive = "google_drive"
        case driveFolder = "drive_folder"
        case driveSupported = "drive_supported"
    }
}

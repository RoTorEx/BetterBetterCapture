import Foundation

nonisolated struct VoxrayProfile: Decodable, Identifiable, Sendable {
    let id: String
    let callsDir: String

    enum CodingKeys: String, CodingKey { case id; case callsDir = "calls_dir" }
}

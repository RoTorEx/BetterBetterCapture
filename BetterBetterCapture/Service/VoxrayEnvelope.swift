import Foundation

nonisolated struct VoxrayEnvelope<T: Decodable>: Decodable {
    let status: String
    let contractVersion: Int?
    let data: T?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case status, data, message
        case contractVersion = "contract_version"
    }
}

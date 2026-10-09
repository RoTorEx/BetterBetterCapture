import Foundation

@objc nonisolated protocol VoxrayBridgeProtocol {
    func perform(_ operation: String, payload: String, reply: @escaping (String) -> Void)
}

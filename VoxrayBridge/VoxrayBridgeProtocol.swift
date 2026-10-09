import Foundation

@objc protocol VoxrayBridgeProtocol {
    func perform(_ operation: String, payload: String, reply: @escaping (String) -> Void)
}

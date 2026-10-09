import Foundation

final class BridgeDelegate: NSObject, NSXPCListenerDelegate {
    private let bridge = VoxrayBridge()

    func listener(_ listener: NSXPCListener, shouldAcceptNewConnection connection: NSXPCConnection) -> Bool {
        connection.exportedInterface = NSXPCInterface(with: VoxrayBridgeProtocol.self)
        connection.exportedObject = bridge
        connection.resume()
        return true
    }
}

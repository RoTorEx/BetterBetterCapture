import Foundation
import Darwin

let delegate = BridgeDelegate()
let listener = NSXPCListener.service()

listener.delegate = delegate
listener.resume()

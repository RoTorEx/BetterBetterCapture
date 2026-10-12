import Foundation
import Darwin

final class VoxrayBridge: NSObject, VoxrayBridgeProtocol {
    func perform(_ operation: String, payload: String, reply: @escaping (String) -> Void) {
        // A short fixed contract, never a shell or arbitrary command execution API.
        DispatchQueue.global(qos: .utility).async {
            do {
                reply(try self.execute(operation, payload: payload))
            } catch {
                let response = ["status": "error", "message": error.localizedDescription]
                let data = try? JSONSerialization.data(withJSONObject: response)
                reply(data.flatMap { String(data: $0, encoding: .utf8) } ?? "{}")
            }
        }
    }

    private func execute(_ operation: String, payload: String) throws -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let executable = home.appending(path: ".x-cli-voxray/bin/voxray")
        var (arguments, requestFile) = try prepare(operation, payload: payload)
        defer { if let requestFile { try? FileManager.default.removeItem(at: requestFile) } }
        arguments += ["--json", "--non-interactive"]
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin"
        process.environment = environment
        let output = Pipe()
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = operation == "run" ? 7_220.0 : 30.0
        let watchdog = DispatchWorkItem {
            if process.isRunning { process.terminate() }
            DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
            }
        }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
        let data = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        watchdog.cancel()
        guard data.count <= 1_048_576,
              let response = String(data: data, encoding: .utf8),
              (try? JSONSerialization.jsonObject(with: data)) != nil else {
            throw NSError(domain: "VoxrayBridge", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "Voxray returned no valid response. Recording is saved."])
        }
        if operation == "version" {
            guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["status"] as? String == "ok", object["command"] as? String == "version",
                  let version = object["result"] as? String, !version.isEmpty else {
                throw NSError(domain: "VoxrayBridge", code: 3,
                              userInfo: [NSLocalizedDescriptionKey: "Voxray version is unavailable."])
            }
            let envelope: [String: Any] = ["status": "ok", "contract_version": 1, "data": version]
            return String(data: try JSONSerialization.data(withJSONObject: envelope), encoding: .utf8) ?? "{}"
        }
        return response
    }
    private func prepare(_ operation: String, payload: String) throws -> ([String], URL?) {
        var arguments: [String]
        var requestFile: URL?
        switch operation {
        case "profiles", "version":
            arguments = [operation]
        case "submit":
            let file = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".json")
            requestFile = file
            try Data(payload.utf8).write(to: file, options: .withoutOverwriting)
            do {
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
            } catch {
                try? FileManager.default.removeItem(at: file)
                throw error
            }
            arguments = ["jobs", "submit", "--request", file.path]
        case "status", "run":
            guard UUID(uuidString: payload) != nil else {
                throw NSError(domain: "VoxrayBridge", code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Invalid recording identity"])
            }
            arguments = ["jobs", operation, "--id", payload]
        default:
            throw NSError(domain: "VoxrayBridge", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: "Unsupported operation"])
        }
        return (arguments, requestFile)
    }

}

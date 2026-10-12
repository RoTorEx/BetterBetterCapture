import Foundation

/// An integration failure returns to the UI; it cannot control the capture writer.

@MainActor final class VoxrayClient: VoxrayServing {
    func profiles() async throws -> [VoxrayProfile] {
        try await request("profiles", payload: "")
    }

    func submit(_ session: CaptureSession) async throws -> VoxrayJob {
        guard let recording = session.savedFile else { throw AssetWriterError.noOutputURL }
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "Europe/Warsaw")
        let input = VoxrayRequest(
            recordingId: session.id.uuidString, recording: recording.path,
            recordedAt: formatter.string(from: session.startedAt), profile: session.profile,
            name: session.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Call" : session.name,
            transcribe: session.transcribe ?? true)
        let payload = String(data: try JSONEncoder().encode(input), encoding: .utf8) ?? ""
        return try await request("submit", payload: payload)
    }

    func run(_ id: UUID) async throws -> VoxrayJob {
        try await request("run", payload: id.uuidString)
    }

    func status(_ id: UUID) async throws -> VoxrayJob {
        try await request("status", payload: id.uuidString)
    }

    private func request<T: Decodable>(_ operation: String, payload: String) async throws -> T {
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let pending = BridgeReply(continuation: continuation)
            let connection = NSXPCConnection(serviceName: "com.betterbettercapture.app.voxraybridge")
            pending.connection = connection
            connection.remoteObjectInterface = NSXPCInterface(with: VoxrayBridgeProtocol.self)
            connection.interruptionHandler = { pending.finish(.failure(Self.unavailable())) }
            connection.invalidationHandler = { pending.finish(.failure(Self.unavailable())) }
            connection.resume()
            guard let proxy = connection.remoteObjectProxyWithErrorHandler({ pending.finish(.failure($0)) })
                as? VoxrayBridgeProtocol else { pending.finish(.failure(Self.unavailable())); return }
            proxy.perform(operation, payload: payload) { pending.finish(.success($0)) }
            DispatchQueue.global().asyncAfter(deadline: .now() + (operation == "run" ? 7_240 : 35)) {
                pending.finish(.failure(Self.unavailable()))
            }
        }
        return try Self.decode(response)
    }

    nonisolated static func decode<T: Decodable>(_ response: String) throws -> T {
        let envelope = try JSONDecoder().decode(VoxrayEnvelope<T>.self, from: Data(response.utf8))
        guard envelope.status == "ok", envelope.contractVersion == 1, let value = envelope.data else {
            throw NSError(domain: "Voxray", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: envelope.message ?? "Unsupported Voxray contract. Recording is saved."])
        }
        return value
    }

    nonisolated private static func unavailable() -> NSError {
        NSError(domain: "Voxray", code: 2,
                userInfo: [NSLocalizedDescriptionKey: "Voxray is unavailable. Recording is saved; retry later."])
    }
}

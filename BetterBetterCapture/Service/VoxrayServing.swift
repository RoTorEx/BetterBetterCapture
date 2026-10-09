import Foundation

@MainActor protocol VoxrayServing {
    func profiles() async throws -> [VoxrayProfile]
    func submit(_ session: CaptureSession) async throws -> VoxrayJob
    func run(_ id: UUID) async throws -> VoxrayJob
    func status(_ id: UUID) async throws -> VoxrayJob
}

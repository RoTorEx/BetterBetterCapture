import Foundation
import Testing
@testable import BetterBetterCapture

@MainActor struct CallWorkflowTests {
    @Test(arguments: ["m4a", "mov"]) func profileAtStopSurvivesNextCapture(mediaExtension: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureSessionStore(registry: directory.appending(path: "registry"))
        let client = FailingVoxray()
        client.fail = false
        let workflow = CallWorkflow(store: store, client: client)
        for initial in ["", "aveni"] {
            let captured = try store.begin(directory: directory, name: "Daily", profile: initial)
            workflow.profile = "thira"
            var stopped = workflow.finishCapture(captured)
            workflow.profile = "aveni" // Another capture starts while this one finalizes.
            stopped.savedFile = stopped.directory.appending(path: "record." + mediaExtension)
            stopped.state = "saved"
            await workflow.process(stopped, assignCurrentProfile: false)
            #expect(client.submitted.last?.profile == "thira")
            #expect(client.submitted.last?.id == captured.id)
            #expect(client.submitted.last?.name == "Daily")
            let deselected = try store.begin(directory: directory, name: "Local", profile: "thira")
            workflow.profile = "" // Removing assignment also takes effect at Stop.
            var unassigned = workflow.finishCapture(deselected)
            unassigned.savedFile = deselected.directory.appending(path: "record." + mediaExtension)
            workflow.profile = "aveni"
            let count = client.submitted.count
            await workflow.process(unassigned, assignCurrentProfile: false)
            #expect(client.submitted.count == count)
            #expect(unassigned.profile.isEmpty)
            await workflow.process(unassigned) // Explicit later processing may assign the current profile.
            #expect(client.submitted.last?.profile == "aveni")
            #expect(client.submitted.last?.id == deselected.id)
        }
    }

    @Test func integrationFailureKeepsSavedRecordingAndCanRetryAfterRestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = directory.appending(path: "registry")
        let store = CaptureSessionStore(registry: registry)
        var session = try store.begin(directory: directory, name: "Daily", profile: "av eni")
        let original = session.directory.appending(path: "record.wav")
        let samples = Data("captured audio remains independent".utf8)
        try samples.write(to: original)
        session.savedFile = original
        session.state = "saved"
        try store.save(session)
        let client = FailingVoxray()
        let workflow = CallWorkflow(store: store, client: client)
        await workflow.process(session)
        #expect(try Data(contentsOf: original) == samples)
        #expect(store.sessions[0].state == "saved")
        #expect(store.sessions[0].error != nil)
        let restarted = CaptureSessionStore(registry: registry)
        client.fail = false
        await CallWorkflow(store: restarted, client: client).process(restarted.sessions[0])
        #expect(restarted.sessions[0].state == "ready")
        #expect(try Data(contentsOf: original) == samples)
    }

    @Test func interruptedSessionIsDiscoveredWithoutVoxray() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let registry = directory.appending(path: "registry")
        let store = CaptureSessionStore(registry: registry)
        var session = try store.begin(directory: directory, name: "", profile: "")
        session.state = "recording"
        try store.save(session)
        let restarted = CaptureSessionStore(registry: registry)
        #expect(restarted.sessions.first?.id == session.id)
        #expect(restarted.sessions.first?.state == "interrupted")
        #expect(FileManager.default.fileExists(atPath: session.directory.path))
    }

    @Test func metadataFailureDoesNotPreventCreatingCaptureFolder() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let invalidRegistry = directory.appending(path: "file")
        try Data("sentinel".utf8).write(to: invalidRegistry)
        let store = CaptureSessionStore(registry: invalidRegistry)
        let session = try store.begin(directory: directory, name: "bad / name", profile: "missing")
        #expect(FileManager.default.fileExists(atPath: session.directory.path))
        #expect(session.error != nil)
        #expect(try Data(contentsOf: invalidRegistry) == Data("sentinel".utf8))
    }
    @Test func malformedOrIncompatibleResponsesFailWithoutArtifacts() {
        for response in ["broken", "{}", "{\"status\":\"ok\",\"contract_version\":2,\"data\":[]}",
                         "{\"status\":\"error\",\"message\":\"Missing profile\"}"] {
            #expect(throws: (any Error).self) {
                let _: [VoxrayProfile] = try VoxrayClient.decode(response)
            }
        }
    }

    @Test func replyTimeoutAndLateResponseResumeExactlyOnce() async throws {
        let result = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let reply = BridgeReply(continuation: continuation)
            reply.finish(.success("first"))
            reply.finish(.failure(NSError(domain: "late timeout", code: 1)))
            reply.finish(.success("late response"))
        }
        #expect(result == "first")
    }

}

@MainActor private final class FailingVoxray: VoxrayServing {
    var fail = true
    var submitted: [CaptureSession] = []

    func profiles() async throws -> [VoxrayProfile] { [] }
    func submit(_ session: CaptureSession) async throws -> VoxrayJob {
        if fail { throw NSError(domain: "integration", code: 1) }
        submitted.append(session)
        return VoxrayJob(id: session.id.uuidString, stage: "ready", recording: "record.wav",
                         transcript: "transcript.txt", error: nil)
    }
    func run(_ id: UUID) async throws -> VoxrayJob { throw NSError(domain: "unused", code: 1) }
    func status(_ id: UUID) async throws -> VoxrayJob { throw NSError(domain: "unused", code: 1) }
}

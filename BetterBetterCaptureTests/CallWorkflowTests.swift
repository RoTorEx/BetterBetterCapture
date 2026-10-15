import Foundation
import Testing
@testable import BetterBetterCapture

@MainActor struct CallWorkflowTests {
    @Test(arguments: ["mov", "m4a"]) func editedNameAndVideoChoiceFreezeAtStop(mediaExtension: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureSessionStore(registry: directory.appending(path: "registry"))
        let client = FailingVoxray()
        client.fail = false
        let workflow = CallWorkflow(store: store, client: client)
        let capture = try store.begin(directory: directory, name: "", profile: "aveni")
        workflow.name = "Engineering Daily"
        workflow.profile = "aveni"
        workflow.keepVideo = true
        var stopped = workflow.finishCapture(capture)
        workflow.name = "Next recording"
        workflow.keepVideo = false
        stopped.savedFile = stopped.directory.appending(path: "record." + mediaExtension)
        await workflow.process(stopped, assignCurrentProfile: false)
        #expect(client.submitted.last?.name == "Engineering Daily")
        #expect(client.submitted.last?.keepVideo == true)
    }

    @Test func stopResetsIntegrationChoicesForNextRecording() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureSessionStore(registry: directory.appending(path: "registry"))
        let workflow = CallWorkflow(store: store, client: FailingVoxray())
        let capture = try store.begin(directory: directory, name: "", profile: "")
        workflow.name = "Engineering Daily"
        workflow.profile = "aveni"
        workflow.transcribe = false
        workflow.keepVideo = true

        let stopped = workflow.finishCapture(capture)

        #expect(stopped.name == "Engineering Daily")
        #expect(stopped.profile == "aveni")
        #expect(stopped.transcribe == false)
        #expect(stopped.keepVideo == true)
        #expect(workflow.name.isEmpty)
        #expect(workflow.profile.isEmpty)
        #expect(workflow.transcribe)
        #expect(!workflow.keepVideo)
        #expect(store.sessions.first?.profile == "aveni")
    }

    @Test func refreshReconcilesCompletedSavedJobWithoutSubmittingAgain() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureSessionStore(registry: directory.appending(path: "registry"))
        var session = try store.begin(directory: directory, name: "Daily", profile: "aveni")
        session.state = "saved"
        session.savedFile = session.directory.appending(path: "record.mov")
        try store.save(session)
        let client = FailingVoxray()
        client.completed = true
        await CallWorkflow(store: store, client: client).refresh()
        #expect(store.sessions.first?.state == "ready")
        #expect(store.sessions.first?.transcript?.lastPathComponent == "transcript.txt")
        #expect(client.submitted.isEmpty)
    }
    @Test(arguments: [false, true]) func versionDiscoveryDoesNotBlockProfiles(unavailable: Bool) async {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let client = FailingVoxray()
        client.versionUnavailable = unavailable
        let workflow = CallWorkflow(store: CaptureSessionStore(registry: directory), client: client)
        await workflow.refresh()
        #expect(workflow.version == (unavailable ? nil : "0.5.1"))
        #expect(workflow.profiles.map(\.id) == ["aveni"])
        #expect(workflow.integrationError == nil)
    }

    @Test(arguments: [false, true]) func transcriptionChoiceIsFrozenAtStop(enabled: Bool) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureSessionStore(registry: directory.appending(path: "registry"))
        let client = FailingVoxray()
        client.fail = false
        let workflow = CallWorkflow(store: store, client: client)
        workflow.profile = "aveni"
        workflow.transcribe = enabled
        let capture = try store.begin(directory: directory, name: "Daily", profile: "aveni")
        var stopped = workflow.finishCapture(capture)
        workflow.transcribe = !enabled
        stopped.savedFile = stopped.directory.appending(path: "record.m4a")
        await workflow.process(stopped, assignCurrentProfile: false)
        #expect(client.submitted.last?.transcribe == enabled)
        #expect(store.sessions.first?.state == (enabled ? "ready" : "filed"))
        #expect((store.sessions.first?.transcript != nil) == enabled)
    }

    @Test func oldSessionStillDecodesWithDefaultTranscription() throws {
        let capture = CaptureSession(id: UUID(), startedAt: Date(), directory: URL(filePath: "/tmp"),
                                     name: "Legacy", profile: "aveni", state: "saved")
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(capture)) as? [String: Any])
        object.removeValue(forKey: "transcribe")
        let decoded = try JSONDecoder().decode(CaptureSession.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded.transcribe == nil)
    }

    @Test(arguments: ["m4a", "mov"]) func profileAtStopSurvivesNextCapture(mediaExtension: String) async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CaptureSessionStore(registry: directory.appending(path: "registry"))
        let client = FailingVoxray()
        client.fail = false
        let workflow = CallWorkflow(store: store, client: client)
        for initial in ["", "aveni"] {
            let captured = try store.begin(directory: directory, name: "Daily", profile: initial)
            workflow.name = "Daily"
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
    var versionUnavailable = false
    var completed = false
    var submitted: [CaptureSession] = []

    func profiles() async throws -> [VoxrayProfile] { [VoxrayProfile(id: "aveni", callsDir: "/tmp/aveni")] }
    func version() async throws -> String {
        if versionUnavailable { throw NSError(domain: "version", code: 1) }
        return "0.5.1"
    }
    func submit(_ session: CaptureSession) async throws -> VoxrayJob {
        if fail { throw NSError(domain: "integration", code: 1) }
        submitted.append(session)
        return VoxrayJob(id: session.id.uuidString, stage: session.transcribe == false ? "stored" : "ready", recording: "record.wav",
                         transcript: "transcript.txt", error: nil)
    }
    func run(_ id: UUID) async throws -> VoxrayJob { throw NSError(domain: "unused", code: 1) }
    func status(_ id: UUID) async throws -> VoxrayJob {
        guard completed else { throw NSError(domain: "unused", code: 1) }
        return VoxrayJob(id: id.uuidString, stage: "ready", recording: "/tmp/record.m4a",
                         transcript: "/tmp/transcript.txt", error: nil)
    }
}

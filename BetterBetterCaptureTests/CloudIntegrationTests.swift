import Foundation
import Testing
@testable import BetterBetterCapture

@MainActor struct CloudIntegrationTests {
    @Test func defaultsAndManualOverridesFreezeAtStop() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureSessionStore(registry: root.appending(path: "registry"))
        let client = CloudVoxray()
        let workflow = CallWorkflow(store: store, client: client)
        await workflow.refresh()
        workflow.profile = "project"
        #expect(workflow.googleDrive)
        #expect(workflow.driveFolder == "defaultFolder")
        workflow.driveFolder = "overrideFolder"
        workflow.transcriptOnly = true
        #expect(workflow.transcribe)
        #expect(!workflow.keepVideo)
        let capture = try store.begin(directory: root, name: "", profile: "")
        let stopped = workflow.finishCapture(capture)
        #expect(stopped.googleDrive == true)
        #expect(stopped.driveFolder == "overrideFolder")
        #expect(stopped.transcriptOnly == true)
        #expect(workflow.profile.isEmpty)
        #expect(!workflow.transcriptOnly)
        workflow.profile = "project"
        #expect(workflow.driveFolder == "defaultFolder")
        workflow.googleDrive = false
        let next = workflow.finishCapture(capture)
        #expect(next.googleDrive == false)
        #expect(next.transcriptOnly == false)
    }

    @Test func profileDefaultsAndMediaOnlyArchiveFreezeIndependently() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureSessionStore(registry: root.appending(path: "registry"))
        let workflow = CallWorkflow(store: store, client: CloudVoxray())
        await workflow.refresh()
        workflow.profile = "project"
        #expect(workflow.keepVideo)
        #expect(workflow.googleDrive)
        #expect(!workflow.transcriptOnly)
        workflow.transcribe = false
        workflow.keepVideo = false
        let capture = try store.begin(directory: root, name: "Archive", profile: "")
        let stopped = workflow.finishCapture(capture)
        #expect(stopped.transcribe == false)
        #expect(stopped.googleDrive == true)
        #expect(stopped.transcriptOnly == false)
        #expect(stopped.keepVideo == false)
        workflow.profile = "project"
        #expect(workflow.keepVideo)
        #expect(workflow.transcribe)
        #expect(!workflow.transcriptOnly)
    }

    @Test func retentionControlsKeepConsistentChoices() {
        let workflow = CallWorkflow(client: CloudVoxray())
        workflow.transcriptOnly = true
        workflow.transcribe = false
        #expect(!workflow.transcriptOnly)
        workflow.transcriptOnly = true
        workflow.keepVideo = true
        #expect(!workflow.transcriptOnly)
    }

    @Test func legacyRequestsOmitUnsupportedChoices() throws {
        let request = VoxrayRequest(recordingId: UUID().uuidString, recording: "/record.wav",
                                    recordedAt: "2026-10-27T12:00:00+01:00", profile: "default", name: "Daily",
                                    transcribe: true, keepVideo: false)
        let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(request)) as? [String: Any]
        #expect(object?["google_drive"] == nil)
        #expect(object?["drive_folder"] == nil)
        #expect(object?["transcript_only"] == nil)
    }

    @Test(arguments: [false, true]) func cleanupRequiresCompletedVerifiedJob(verified: Bool) async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureSessionStore(registry: root.appending(path: "registry"))
        var session = try store.begin(directory: root, name: "Daily", profile: "project")
        session.state = "saved"
        session.transcriptOnly = true
        let media = root.appending(path: "Daily.m4a")
        let raw = session.directory.appending(path: "original.mov")
        let recovery = session.directory.appending(path: "microphone-0.partial.caf")
        let unrelated = root.appending(path: "Other.m4a")
        let transcript = root.appending(path: "transcript.txt")
        for file in [media, raw, recovery, unrelated] { try Data("samples".utf8).write(to: file) }
        try Data("Speaker 1: hello".utf8).write(to: transcript)
        session.savedFile = media
        try store.save(session)
        let client = CloudVoxray()
        client.result = VoxrayJob(id: session.id.uuidString, stage: verified ? "ready" : "failed",
                                  recording: "/call/record.m4a", transcript: transcript.path,
                                  error: verified ? nil : "Upload failed; media preserved", mediaRemoved: verified)
        let workflow = CallWorkflow(store: store, client: client)
        await workflow.refresh()
        for file in [media, raw, recovery] {
            #expect(FileManager.default.fileExists(atPath: file.path) == !verified)
        }
        #expect(FileManager.default.fileExists(atPath: unrelated.path))
        #expect(FileManager.default.fileExists(atPath: session.directory.appending(path: "session.json").path))
        #expect(store.sessions.first?.state == (verified ? "ready" : "saved"))
        #expect((store.sessions.first?.savedFile == nil) == verified)
        #expect((workflow.integrationError == nil) == verified)
    }

    @Test func unverifiedJobAndForeignSavedPathPreserveMedia() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = CaptureSessionStore(registry: root.appending(path: "registry"))
        var session = try store.begin(directory: root, name: "Daily", profile: "project")
        session.transcriptOnly = true
        let raw = session.directory.appending(path: "original.mov")
        var job = VoxrayJob(id: session.id.uuidString, stage: "ready", recording: "/record.wav",
                            transcript: "/not-readable/transcript.txt", error: nil, mediaRemoved: false)
        try Data("samples".utf8).write(to: raw)
        #expect(throws: (any Error).self) { try store.removeMediaAfterTranscript(session, job: job) }
        #expect(FileManager.default.fileExists(atPath: raw.path))
        job.mediaRemoved = true
        let foreign = root.appending(path: "foreign")
        try FileManager.default.createDirectory(at: foreign, withIntermediateDirectories: true)
        session.savedFile = foreign.appending(path: "record.m4a")
        try Data("foreign samples".utf8).write(to: #require(session.savedFile))
        #expect(throws: (any Error).self) { try store.removeMediaAfterTranscript(session, job: job) }
        #expect(FileManager.default.fileExists(atPath: raw.path))
    }
}

@MainActor private final class CloudVoxray: VoxrayServing {
    var result: VoxrayJob?

    func profiles() async throws -> [VoxrayProfile] {
        [VoxrayProfile(id: "project", callsDir: "/calls", keepVideo: true, googleDrive: true,
                       driveFolder: "defaultFolder", driveSupported: true)]
    }
    func version() async throws -> String { "0.6.0" }
    func status(_ id: UUID) async throws -> VoxrayJob {
        guard let result else { throw CocoaError(.fileNoSuchFile) }
        return result
    }
    func run(_ id: UUID) async throws -> VoxrayJob { try await status(id) }
    func submit(_ session: CaptureSession) async throws -> VoxrayJob { try await status(session.id) }
}

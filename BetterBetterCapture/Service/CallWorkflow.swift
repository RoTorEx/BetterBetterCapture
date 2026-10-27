import Foundation
import Observation

@Observable @MainActor final class CallWorkflow {
    let store: CaptureSessionStore
    var name = ""
    var profile = "" {
        didSet {
            guard oldValue != profile else { return }
            applyDriveDefaults()
        }
    }
    var transcribe = true {
        didSet { if !transcribe { transcriptOnly = false } }
    }
    var keepVideo = false {
        didSet { if keepVideo { transcriptOnly = false } }
    }
    var googleDrive = false
    var driveFolder = ""
    var transcriptOnly = false {
        didSet {
            if transcriptOnly { transcribe = true; keepVideo = false }
        }
    }
    var driveSupported: Bool { profiles.first { $0.id == profile }?.driveSupported == true }

    private func applyDriveDefaults() {
        let selected = profiles.first { $0.id == profile }
        googleDrive = selected?.googleDrive ?? false
        driveFolder = selected?.driveFolder ?? ""
    }

    private(set) var profiles: [VoxrayProfile] = []
    private(set) var version: String?
    private(set) var integrationError: String?
    private(set) var activeJobs: Set<UUID> = []
    private let client: any VoxrayServing

    init(store: CaptureSessionStore? = nil, client: (any VoxrayServing)? = nil) {
        self.store = store ?? CaptureSessionStore()
        self.client = client ?? VoxrayClient()
    }

    func refresh() async {
        version = try? await client.version()
        do {
            let firstDiscovery = profiles.isEmpty
            profiles = try await client.profiles()
            if firstDiscovery { applyDriveDefaults() }
            integrationError = nil
        } catch { integrationError = error.localizedDescription }
        // A helper or app restart does not lose accepted jobs. The OS lock prevents duplicates.
        for session in store.sessions where session.state == "transcribing" ||
            (session.state == "saved" && !session.profile.isEmpty) {
            guard !activeJobs.contains(session.id) else { continue }
            await process(session)
        }
    }

    /// Freeze routing when Stop is accepted, before capture shutdown or queued processing.
    func finishCapture(_ original: CaptureSession) -> CaptureSession {
        var session = original
        session.name = name
        session.profile = profile
        session.transcribe = transcribe
        session.keepVideo = keepVideo
        session.googleDrive = driveSupported ? googleDrive : nil
        session.driveFolder = driveSupported && !driveFolder.isEmpty ? driveFolder : nil
        session.transcriptOnly = driveSupported ? transcriptOnly : nil
        session.state = "processing"
        try? store.save(session)
        name = ""
        profile = ""
        transcribe = true
        keepVideo = false
        transcriptOnly = false
        googleDrive = false
        driveFolder = ""
        return session
    }

    func process(_ original: CaptureSession, assignCurrentProfile: Bool = true) async {
        guard original.savedFile != nil, !activeJobs.contains(original.id) else { return }
        var session = original
        if session.profile.isEmpty {
            guard assignCurrentProfile, !profile.isEmpty else { return }
            session.profile = profile
            session.name = name
            session.transcribe = transcribe
            session.keepVideo = keepVideo
            session.googleDrive = driveSupported ? googleDrive : nil
            session.driveFolder = driveSupported && !driveFolder.isEmpty ? driveFolder : nil
            session.transcriptOnly = driveSupported ? transcriptOnly : nil
        }
        activeJobs.insert(session.id)
        defer { activeJobs.remove(session.id) }
        do {
            session.state = "transcribing"
            session.error = nil
            try store.save(session)
            let submitted: VoxrayJob
            if let existing = try? await client.status(session.id) {
                submitted = existing
            } else {
                submitted = try await client.submit(session)
            }
            let complete = ["ready", "stored"].contains(submitted.stage)
            let result = complete ? submitted : try await client.run(session.id)
            switch result.stage {
            case "ready": session.state = "ready"
            case "stored": session.state = "filed"
            default: session.state = "saved"
            }
            session.error = result.error
            integrationError = result.error
            if session.transcriptOnly == true, result.stage == "ready", result.mediaRemoved == true {
                try store.removeMediaAfterTranscript(session, job: result)
                session.savedFile = nil
            }
            if result.stage == "ready" { session.transcript = URL(fileURLWithPath: result.transcript) }
            try store.save(session)
        } catch {
            session.state = "saved"
            session.error = error.localizedDescription
            try? store.save(session)
            integrationError = error.localizedDescription
        }
    }

    func recover(_ original: CaptureSession) async {
        var session = original
        do {
            session.savedFile = try await store.recover(session)
            session.state = "saved"
            session.error = nil
            try store.save(session)
        } catch {
            session.error = error.localizedDescription
            try? store.save(session)
        }
    }
}

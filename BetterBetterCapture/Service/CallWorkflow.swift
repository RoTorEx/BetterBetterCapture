import Foundation
import Observation

@Observable @MainActor final class CallWorkflow {
    let store: CaptureSessionStore
    var name = ""
    var profile = ""
    var transcribe = true
    private(set) var profiles: [VoxrayProfile] = []
    private(set) var integrationError: String?
    private(set) var activeJobs: Set<UUID> = []
    private let client: any VoxrayServing

    init(store: CaptureSessionStore? = nil, client: (any VoxrayServing)? = nil) {
        self.store = store ?? CaptureSessionStore()
        self.client = client ?? VoxrayClient()
    }

    func refresh() async {
        do {
            profiles = try await client.profiles()
            integrationError = nil
        } catch { integrationError = error.localizedDescription }
        // A helper or app restart does not lose accepted jobs. The OS lock prevents duplicates.
        for session in store.sessions where session.state == "transcribing" {
            await process(session)
        }
    }

    /// Freeze routing when Stop is accepted, before capture shutdown or queued processing.
    func finishCapture(_ original: CaptureSession) -> CaptureSession {
        var session = original
        session.profile = profile
        session.transcribe = transcribe
        session.state = "processing"
        try? store.save(session)
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

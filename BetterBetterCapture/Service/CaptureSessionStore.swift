import AVFoundation
import Foundation
import Observation

/// Capture history belongs to the recorder, independently of Voxray availability.
@Observable @MainActor final class CaptureSessionStore {
    private(set) var sessions: [CaptureSession] = []
    private let registry: URL

    init(registry: URL? = nil) {
        self.registry = registry ?? FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "CaptureSessions")
        do {
            try FileManager.default.createDirectory(at: self.registry, withIntermediateDirectories: true)
            let files = try FileManager.default.contentsOfDirectory(at: self.registry, includingPropertiesForKeys: nil)
            sessions = files.filter { $0.pathExtension == "json" }.compactMap {
                try? JSONDecoder().decode(CaptureSession.self, from: Data(contentsOf: $0))
            }.sorted { $0.startedAt > $1.startedAt }
            // Capture is in-process: sessions left in these states were interrupted.
            for var session in sessions where ["starting", "recording", "processing"].contains(session.state) {
                session.state = "interrupted"
                session.error = "Capture was interrupted. Originals and audio fragments are available."
                try save(session)
            }
        } catch {
            // Expose failures in the caller when starting; never discard existing files.
        }
        discover(in: self.registry.deletingLastPathComponent().appending(path: "Recordings"))
    }

    func begin(directory: URL, name: String, profile: String) throws -> CaptureSession {
        let id = UUID()
        let folder = directory.appending(path: "_CaptureData").appending(path: id.uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try RecordingFileSync.synchronizeDirectory(folder.deletingLastPathComponent())
        try RecordingFileSync.synchronizeDirectory(directory)
        var session = CaptureSession(
            id: id, startedAt: Date(), directory: folder, name: name,
            profile: profile, state: "starting")
        session.bookmark = try? folder.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        session.outputBookmark = try? directory.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        do { try save(session) } catch {
            session.error = "Recording metadata could not be saved: " + error.localizedDescription
            if let index = sessions.firstIndex(where: { $0.id == session.id }) {
                sessions[index] = session
            } else { sessions.insert(session, at: 0) }
        }
        return session
    }

    func save(_ session: CaptureSession) throws {
        if let index = sessions.firstIndex(where: { $0.id == session.id }) {
            sessions[index] = session
        } else {
            sessions.insert(session, at: 0)
        }
        let data = try JSONEncoder().encode(session)
        try? RecordingFileSync.write(data, to: session.directory.appending(path: "session.json"))
        try RecordingFileSync.write(data, to: registry.appending(path: session.id.uuidString + ".json"))
    }

    func discover(in directory: URL) {
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        let locations = [directory, directory.appending(path: "_CaptureData")]
        for location in locations {
            guard let folders = try? FileManager.default.contentsOfDirectory(
                at: location, includingPropertiesForKeys: nil) else { continue }
            for folder in folders where UUID(uuidString: folder.lastPathComponent) != nil {
                guard var session = try? JSONDecoder().decode(
                    CaptureSession.self, from: Data(contentsOf: folder.appending(path: "session.json"))),
                      !sessions.contains(where: { $0.id == session.id }) else { continue }
                if ["starting", "recording", "processing"].contains(session.state) {
                    session.state = "interrupted"
                }
                try? save(session)
            }
        }
    }

    func access(_ session: CaptureSession) -> URL {
        if let bookmark = session.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                  relativeTo: nil, bookmarkDataIsStale: &stale) { return url }
        }
        return session.directory
    }

    /// Reassemble a new audio copy, leaving all chunks and the raw container intact.
    func recover(_ session: CaptureSession) async throws -> URL {
        let directory = access(session)
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        guard let enumerator = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: nil) else { throw AssetWriterError.noOutputURL }
        let fragments = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "caf" }
        let composition = AVMutableComposition()
        var inserted = false
        for source in ["system", "microphone"] {
            guard let track = composition.addMutableTrack(
                withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else { continue }
            let ordered = fragments.filter { $0.lastPathComponent.hasPrefix(source + "-") }.sorted {
                Self.offset($0) < Self.offset($1)
            }
            for fragment in ordered {
                let asset = AVURLAsset(url: fragment)
                guard let audio = try? await asset.loadTracks(withMediaType: .audio).first,
                      let duration = try? await asset.load(.duration), duration.seconds > 0 else { continue }
                try track.insertTimeRange(CMTimeRange(start: .zero, duration: duration), of: audio,
                                          at: CMTime(seconds: Self.offset(fragment), preferredTimescale: 48_000))
                inserted = true
            }
        }
        guard inserted, let exporter = AVAssetExportSession(
            asset: composition, presetName: AVAssetExportPresetAppleM4A) else {
            throw AssetWriterError.noOutputURL
        }
        let parent = directory.deletingLastPathComponent()
        let outputDirectory = parent.lastPathComponent == "_CaptureData"
            ? parent.deletingLastPathComponent() : directory
        let recovered = outputDirectory.appending(path: "Recovered-" + UUID().uuidString + ".m4a")
        try await exporter.export(to: recovered, as: .m4a)
        let file = try FileHandle(forWritingTo: recovered)
        defer { try? file.close() }
        try RecordingFileSync.synchronize(file)
        try RecordingFileSync.synchronizeDirectory(outputDirectory)
        return recovered
    }

    /// The per-capture opt-in is honored only after Voxray verifies its transcript and upload.
    func removeMediaAfterTranscript(_ session: CaptureSession, job: VoxrayJob) throws {
        guard session.transcriptOnly == true, job.stage == "ready", job.mediaRemoved == true,
              UUID(uuidString: job.id) == session.id else { throw CocoaError(.fileWriteNoPermission) }
        // Voxray revalidates its saved transcript proof before every bridge response.
        // The sandboxed recorder must not read arbitrary Voxray library paths.
        let directory = access(session)
        let scoped = directory.startAccessingSecurityScopedResource()
        defer { if scoped { directory.stopAccessingSecurityScopedResource() } }
        guard directory.lastPathComponent == session.id.uuidString,
              directory.deletingLastPathComponent().lastPathComponent == "_CaptureData",
              directory.standardizedFileURL == directory.resolvingSymlinksInPath().standardizedFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
        let output = directory.deletingLastPathComponent().deletingLastPathComponent()
        let access = try outputAccess(session, expected: output)
        let outputScoped = access.startAccessingSecurityScopedResource()
        defer { if outputScoped { access.stopAccessingSecurityScopedResource() } }
        try validateSavedMedia(session.savedFile, output: output, directory: directory)
        let extensions: Set<String> = ["mov", "mp4", "m4a", "wav", "caf", "aiff", "flac"]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else {
            throw CocoaError(.fileReadUnknown)
        }
        var files: [URL] = []
        for case let file as URL in enumerator where extensions.contains(file.pathExtension.lowercased()) {
            let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true,
                  file.standardizedFileURL == file.resolvingSymlinksInPath().standardizedFileURL else {
                throw CocoaError(.fileWriteNoPermission)
            }
            files.append(file)
        }
        if let saved = session.savedFile, !files.contains(saved), FileManager.default.fileExists(atPath: saved.path) {
            files.append(saved)
        }
        for file in files { try FileManager.default.removeItem(at: file) }
        try RecordingFileSync.synchronizeDirectory(directory)
        try RecordingFileSync.synchronizeDirectory(output)
    }

    private func outputAccess(_ session: CaptureSession, expected: URL) throws -> URL {
        guard let bookmark = session.outputBookmark else { return expected }
        var stale = false
        let directory = try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                                relativeTo: nil, bookmarkDataIsStale: &stale)
        guard directory.standardizedFileURL == expected.standardizedFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
        return directory
    }

    private func validateSavedMedia(_ saved: URL?, output: URL, directory: URL) throws {
        guard let saved, FileManager.default.fileExists(atPath: saved.path) else { return }
        let parent = saved.deletingLastPathComponent().standardizedFileURL
        guard parent == output.standardizedFileURL || parent == directory.standardizedFileURL,
              saved.standardizedFileURL == saved.resolvingSymlinksInPath().standardizedFileURL else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }

    private static func offset(_ url: URL) -> Double {
        Double(url.lastPathComponent.split(separator: "-").dropFirst().first ?? "0") ?? 0
    }
}

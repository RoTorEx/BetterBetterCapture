import Foundation

extension SettingsStore {
    // MARK: - Helper Methods

    /// Generates a filename based on the current timestamp.
    /// Audio-only recordings use audio file extensions (.m4a for AAC, .wav for PCM)
    /// so they are easier to identify and open in audio players.
    func generateFilename() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd-HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        let ext = recordAudioOnly ? audioOnlyFileExtension : containerFormat.fileExtension
        return "BetterBetterCapture_\(timestamp).\(ext)"
    }

    private var audioOnlyFileExtension: String {
        switch audioCodec {
        case .aac:
            return "m4a"
        case .pcm:
            return "wav"
        }
    }

    /// Returns the full output URL for a new recording
    func generateOutputURL() -> URL {
        let preferred = outputDirectory.appending(path: generateFilename())
        let stem = preferred.deletingPathExtension().lastPathComponent
        let capture = outputDirectory.appending(path: stem + "-unprocessed.mov")
        let recovery = outputDirectory.appending(path: stem + "-recovery")
        guard FileManager.default.fileExists(atPath: preferred.path)
                || FileManager.default.fileExists(atPath: capture.path)
                || FileManager.default.fileExists(atPath: recovery.path) else { return preferred }
        return outputDirectory.appending(path: stem + "-" + UUID().uuidString)
            .appendingPathExtension(preferred.pathExtension)
    }
}

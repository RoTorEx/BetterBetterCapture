import Foundation

extension SettingsStore {
    /// Capture must expose a broken selected bookmark instead of silently changing destinations.
    func captureOutputDirectory() throws -> URL {
        guard let bookmark = customOutputDirectoryBookmark else { return defaultOutputDirectory }
        var stale = false
        return try URL(resolvingBookmarkData: bookmark, options: .withSecurityScope,
                       relativeTo: nil, bookmarkDataIsStale: &stale)
    }
}

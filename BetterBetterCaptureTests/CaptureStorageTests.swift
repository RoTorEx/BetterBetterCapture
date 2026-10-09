import Foundation
import Testing
@testable import BetterBetterCapture

@MainActor struct CaptureStorageTests {
    @Test func brokenSelectedBookmarkFailsExplicitlyForCapture() throws {
        let suite = UUID().uuidString
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Data("broken bookmark".utf8), forKey: "customOutputDirectoryBookmark")
        let settings = SettingsStore(defaults: defaults)
        #expect(settings.hasCustomOutputDirectory)
        #expect(throws: (any Error).self) { try settings.captureOutputDirectory() }
    }
}

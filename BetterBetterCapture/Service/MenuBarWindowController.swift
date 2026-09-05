import AppKit

/// Opens or closes the existing SwiftUI menu-bar panel through its status button.
@MainActor
enum MenuBarWindowController {
    static func toggle() {
        // MenuBarExtra has no presentation binding. Use the app's status button
        // so SwiftUI retains ownership of panel positioning and dismissal.
        for window in NSApp.windows {
            if let contentView = window.contentView,
               let button = statusButton(in: contentView) {
                button.performClick(nil)
                return
            }
        }
    }

    private static func statusButton(in view: NSView) -> NSStatusBarButton? {
        if let button = view as? NSStatusBarButton {
            return button
        }

        for subview in view.subviews {
            if let button = statusButton(in: subview) {
                return button
            }
        }
        return nil
    }
}

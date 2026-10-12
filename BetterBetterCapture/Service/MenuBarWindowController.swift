import AppKit

/// Opens or closes the existing SwiftUI menu-bar panel through its status button.
@MainActor
enum MenuBarWindowController {
    private static weak var panel: NSWindow?

    static func attach(_ window: NSWindow) {
        panel = window
        (window as? NSPanel)?.becomesKeyOnlyIfNeeded = false
        DispatchQueue.main.async { focus() }
    }

    static func focus() {
        guard let panel, panel.isVisible else { return }
        panel.makeKey()
        panel.makeFirstResponder(panel.contentView)
    }

    static func dismiss() {
        guard panel?.isVisible == true else { return }
        toggle()
    }

    static func toggle() {
        // MenuBarExtra has no presentation binding. Use the app's status button
        // so SwiftUI retains ownership of panel positioning and dismissal.
        for window in NSApp.windows {
            if let contentView = window.contentView,
               let button = statusButton(in: contentView) {
                button.performClick(nil)
                DispatchQueue.main.async { focus() }
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

import AppKit
import SwiftUI

/// Capture the actual menu-bar panel without introducing another window or scene.
struct MenuBarPanelReader: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { PanelView() }
    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class PanelView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window { MenuBarWindowController.attach(window) }
        }
    }
}

import AppKit
import SwiftUI

/// Capture the actual menu-bar panel without introducing another window or scene.
struct MenuBarPanelReader: NSViewRepresentable {
    let onEscape: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PanelView()
        view.onEscape = onEscape
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        (nsView as? PanelView)?.onEscape = onEscape
    }

    private final class PanelView: NSView {
        var onEscape: () -> Void = {}
        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
            guard let window else { return }
            MenuBarWindowController.attach(window)
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self, event.window === self.window, self.window?.isVisible == true,
                      event.keyCode == 53, event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else {
                    return event
                }
                self.onEscape()
                return nil
            }
        }

        isolated deinit {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }
    }
}

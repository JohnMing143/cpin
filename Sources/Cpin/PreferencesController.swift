import AppKit
import SwiftUI

@MainActor
final class PreferencesController {
    private let model: AppModel
    private var window: NSWindow?

    init(model: AppModel) { self.model = model }

    func show() {
        model.refreshStorageUsage()
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 500, height: 700),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "Cpin 偏好设置"
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            window.contentView = NSHostingView(rootView: PreferencesView(model: model))
            window.center()
            self.window = window
        }
        if let screen = window?.screen ?? NSScreen.main {
            let height = min(700, screen.visibleFrame.height - 60)
            window?.setContentSize(NSSize(width: min(500, screen.visibleFrame.width - 40), height: height))
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

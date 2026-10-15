#if STANDALONE_CHECKS
import AppKit
import QuartzCore
import CpinCore

private struct PanelCheckFailure: Error, CustomStringConvertible {
    let description: String
}

@main
struct PanelControllerChecks {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        app.finishLaunching()
        Task { @MainActor in
            do {
                try await runChecks()
                print("All native panel checks passed.")
                exit(0)
            } catch {
                fputs("FAIL: \(error)\n", stderr)
                exit(1)
            }
        }
        app.run()
    }

    @MainActor private static func require(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw PanelCheckFailure(description: message) }
    }

    private static func pause(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    // Find the animated native layer by its public CAAnimation data, rather than
    // depending on the controller's private view classes or animation key names.
    @MainActor private static func motionLayer(in view: NSView) -> CALayer? {
        if let layer = view.layer, let keys = layer.animationKeys(), keys.contains(where: { key in
            guard let group = layer.animation(forKey: key) as? CAAnimationGroup else { return false }
            return group.animations?.contains { ($0 as? CAPropertyAnimation)?.keyPath == "transform" } == true
        }) { return layer }
        for child in view.subviews { if let layer = motionLayer(in: child) { return layer } }
        return nil
    }

    @MainActor private static func checkMotion(_ panel: NSPanel, position: PanelPosition, reduceMotion: Bool) throws {
        guard let content = panel.contentView, let layer = motionLayer(in: content),
              let presentation = layer.presentation() else {
            throw PanelCheckFailure(description: "No live presentation layer during \(position.rawValue) transition")
        }
        let t = presentation.transform
        if reduceMotion {
            try require(abs(t.m41) < 0.5 && abs(t.m42) < 0.5, "Reduce Motion must avoid translation")
            return
        }
        switch position {
        case .bottom: try require(t.m42 < -0.5 && abs(t.m41) < 0.5, "Bottom must animate from below")
        case .top: try require(t.m42 > 0.5 && abs(t.m41) < 0.5, "Top must animate from above")
        case .left: try require(t.m41 < -0.5 && abs(t.m42) < 0.5, "Left must animate from the left")
        case .right: try require(t.m41 > 0.5 && abs(t.m42) < 0.5, "Right must animate from the right")
        }
    }

    @MainActor private static func runChecks() async throws {
        try require(!NSScreen.screens.isEmpty, "A logged-in macOS GUI session is required")
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cpin-PanelChecks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let history = try ClipboardHistory(directory: directory)
        try history.addText("Panel check fixture", sourceName: "Test")
        let model = AppModel(history: history, isDemo: true)
        let controller = PanelController(model: model, writeItem: { _ in
            throw PanelCheckFailure(description: "The panel check must not write any pasteboard")
        })
        model.onLayoutChange = { [weak controller] in controller?.updateLayout() }
        defer { controller.hide(restoreFocus: false) }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        print("Native panel checks; Reduce Motion = \(reduceMotion). Keep this test app active for approximately 8 seconds.")
        var testPanel: NSPanel?
        for mode in PanelMode.allCases {
            for position in PanelPosition.allCases {
                model.panelMode = mode
                model.panelPosition = position
                controller.show()
                try await pause(0.035)
                guard let panel = NSApp.windows.compactMap({ $0 as? NSPanel }).first(where: \.isVisible) else {
                    throw PanelCheckFailure(description: "No visible native panel after show")
                }
                testPanel = panel
                try checkMotion(panel, position: position, reduceMotion: reduceMotion)
                try await pause(0.32)
                try require(controller.isVisible && panel.isVisible, "\(mode.rawValue)/\(position.rawValue) failed to finish showing")
                try require(panel.isKeyWindow, "Shown panel must be key for search and keyboard navigation")
                let frame = panel.frame
                controller.hide(restoreFocus: false)
                try await pause(0.035)
                try checkMotion(panel, position: position, reduceMotion: reduceMotion)
                try require(panel.frame == frame, "Animation must not move the native window onto adjacent screens")
                try await pause(0.25)
                try require(!controller.isVisible && !panel.isVisible, "\(mode.rawValue)/\(position.rawValue) failed to finish hiding")
                print("PASS: \(mode.rawValue)/\(position.rawValue) presentation direction, focus and final visibility")
            }
        }
        guard let panel = testPanel else { throw PanelCheckFailure(description: "Missing test panel") }
        model.panelPosition = .bottom
        controller.show()
        try await pause(0.32)
        model.query = "preserve this query"
        for _ in 0..<4 {
            controller.hide(restoreFocus: false)
            try await pause(0.025)
            controller.show()
            try await pause(0.025)
        }
        try await pause(0.35)
        try require(controller.isVisible && panel.isVisible, "A stale dismissal completion hid the reopened panel")
        try require(model.query == "preserve this query", "Reversing dismissal reset the search query")
        print("PASS: rapid reversal preserves query and final visible state")
        controller.hide(restoreFocus: false)
        try await pause(0.25)
        controller.show()
        try await pause(0.035)
        model.panelPosition = .right
        controller.updateLayout()
        try await pause(0.35)
        try require(controller.isVisible && panel.isVisible, "Mid-animation layout change did not settle visible")
        try require(panel.frame.height > panel.frame.width, "Changing bottom to right did not produce vertical geometry")
        try require(NSScreen.screens.contains { $0.frame.intersects(panel.frame) }, "Panel settled outside every available screen")
        controller.hide(restoreFocus: false)
        try await pause(0.035)
        model.panelPosition = .top
        controller.updateLayout()
        try await pause(0.3)
        try require(!controller.isVisible && !panel.isVisible, "Mid-dismissal direction change failed to hide")
        print("PASS: layout changes during show and hide converge")
    }
}
#endif

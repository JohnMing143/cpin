import CpinCore

import AppKit
import SwiftUI
import ApplicationServices
import QuartzCore

private final class ShelfPanel: NSPanel {
    var suppressContentClicks = false
    override func sendEvent(_ event: NSEvent) {
        if suppressContentClicks && [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp].contains(event.type) { return }
        super.sendEvent(event)
    }
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PanelController: NSObject, NSWindowDelegate {
    private let model: AppModel
    private let writeItem: (ClipItem) throws -> Void
    private let beforeShow: () -> Void
    private var panel: ShelfPanel?
    private var previousApplication: NSRunningApplication?
    private var keyMonitor: Any?
    private var clickMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var appObserver: NSObjectProtocol?
    private var displayedScreenID: NSNumber?
    private var animatedContent: NSView?
    private var wantsVisible = false
    private var animationGeneration = 0
    private var animationCompletion: DispatchWorkItem?
    var isVisible: Bool { wantsVisible && panel?.isVisible == true }

    init(model: AppModel, writeItem: @escaping (ClipItem) throws -> Void, beforeShow: @escaping () -> Void = {}) {
        self.model = model
        self.writeItem = writeItem
        self.beforeShow = beforeShow
        super.init()
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.updateLayout() }
        }
        appObserver = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshPastePermission() }
        }
    }

    deinit {
        animationCompletion?.cancel()
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let appObserver { NotificationCenter.default.removeObserver(appObserver) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        for monitor in [keyMonitor, clickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
    }

    func toggle() { isVisible ? hide() : show() }

    func focusCards() { panel?.makeFirstResponder(nil) }

    private func focusSearchField(in view: NSView) -> Bool {
        if let field = view as? NSTextField, field.isEditable {
            field.selectText(nil)
            return true
        }
        return view.subviews.contains { focusSearchField(in: $0) }
    }

    func show() {
        refreshPastePermission()
        if isVisible {
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
            return
        }
        // Reverse an in-flight dismissal without resetting search, selection or screen.
        if panel?.isVisible == true {
            beforeShow()
            let front = NSWorkspace.shared.frontmostApplication
            if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = front }
            wantsVisible = true
            panel?.ignoresMouseEvents = false
            NSApp.activate(ignoringOtherApps: true)
            panel?.makeKeyAndOrderFront(nil)
            installMonitors()
            animateVisibility(true)
            return
        }
        // Capture a just-copied item before activating Cpin, preserving its source.
        beforeShow()
        let front = NSWorkspace.shared.frontmostApplication
        if front?.processIdentifier != ProcessInfo.processInfo.processIdentifier { previousApplication = front }
        model.query = ""
        model.selectedID = model.visibleItems.first?.id
        model.feedback = nil
        if panel == nil {
            let window = ShelfPanel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: false)
            window.isFloatingPanel = true
            window.animationBehavior = .none
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: .aqua)
            let clip = NSView(frame: .zero)
            clip.wantsLayer = true
            clip.layer?.masksToBounds = true
            // Animate an AppKit-owned, non-flipped wrapper, leaving SwiftUI's
            // hosting layer untouched. Its parent uses bottom-left coordinates.
            let motion = NSView(frame: .zero)
            motion.wantsLayer = true
            motion.autoresizingMask = [.width, .height]
            let content = NSHostingView(rootView: ShelfView(model: model))
            content.autoresizingMask = [.width, .height]
            motion.addSubview(content)
            clip.addSubview(motion)
            animatedContent = motion
            window.contentView = clip
            window.delegate = self
            panel = window
        }
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        displayedScreenID = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        updateLayout()
        wantsVisible = true
        panel?.ignoresMouseEvents = false
        prepareHiddenContent()
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeKeyAndOrderFront(nil)
        panel?.makeFirstResponder(nil)
        installMonitors()
        animateVisibility(true)
    }

    func updateLayout() {
        guard let panel else { return }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber) == displayedScreenID
        } ?? panel.screen ?? NSScreen.main
        guard let screen else { return }
        displayedScreenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
        var safeVisible = screen.visibleFrame
        let safeTop = screen.frame.maxY - screen.safeAreaInsets.top
        if safeVisible.maxY > safeTop { safeVisible.size.height = max(0, safeTop - safeVisible.minY) }
        panel.level = model.panelMode == .docked ? .statusBar : .floating
        panel.hasShadow = model.panelMode == .floating
        panel.setFrame(PanelGeometry.frame(screenFrame: screen.frame, visibleFrame: safeVisible,
                                          mode: model.panelMode, position: model.panelPosition), display: true)
        if let bounds = panel.contentView?.bounds { animatedContent?.frame = bounds }
        // Finish layout changes in the new direction without leaving stale animation geometry.
        if animationCompletion != nil { animateVisibility(wantsVisible) }
    }

    func refreshPastePermission() {
        model.canAutoPaste = !model.isDemo && AXIsProcessTrusted()
    }

    func requestInitialPastePermissionIfNeeded() {
        guard !model.isDemo else { return }
        refreshPastePermission()
        let key = "didRequestInitialPastePermission"
        guard !UserDefaults.standard.bool(forKey: key) else { return }
        UserDefaults.standard.set(true, forKey: key)
        guard !model.canAutoPaste else { return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        model.canAutoPaste = AXIsProcessTrustedWithOptions(options)
    }

    func hide(restoreFocus: Bool = true) {
        guard wantsVisible else { return }
        wantsVisible = false
        removeMonitors()
        panel?.ignoresMouseEvents = true
        animateVisibility(false)
        if restoreFocus { restorePreviousApplication() }
    }

    private func hiddenTransform() -> CATransform3D {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let size = panel?.contentView?.bounds.size else { return CATransform3DIdentity }
        switch model.panelPosition {
        case .bottom: return CATransform3DMakeTranslation(0, -size.height, 0)
        case .top: return CATransform3DMakeTranslation(0, size.height, 0)
        case .left: return CATransform3DMakeTranslation(-size.width, 0, 0)
        case .right: return CATransform3DMakeTranslation(size.width, 0, 0)
        }
    }

    private func prepareHiddenContent() {
        guard let layer = animatedContent?.layer else { return }
        layer.removeAllAnimations()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = hiddenTransform()
        layer.opacity = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.72
        CATransaction.commit()
    }

    private func animateVisibility(_ visible: Bool) {
        animationGeneration += 1
        let generation = animationGeneration
        animationCompletion?.cancel()
        animationCompletion = nil
        guard let layer = animatedContent?.layer else {
            if !visible { panel?.orderOut(nil) }
            return
        }
        // Sample the presentation layer before cancellation: rapid toggles reverse from
        // the currently displayed pixels, never from the previous model-layer endpoint.
        // A hidden window can retain a stale presentation tree from the previous
        // edge. Only an active visibility animation is eligible for reversal.
        let presentation = layer.animation(forKey: "shelfVisibility") == nil ? nil : layer.presentation()
        let currentTransform = presentation?.transform ?? layer.transform
        let currentOpacity = presentation?.opacity ?? layer.opacity
        layer.removeAnimation(forKey: "shelfVisibility")
        panel?.suppressContentClicks = true
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let targetTransform = visible ? CATransform3DIdentity : hiddenTransform()
        let targetOpacity: Float = visible ? 1 : (reduceMotion ? 0 : 0.72)
        let duration = reduceMotion ? 0.10 : (visible ? 0.26 : 0.20)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = targetTransform
        layer.opacity = targetOpacity
        CATransaction.commit()
        let movement = CABasicAnimation(keyPath: "transform")
        movement.fromValue = NSValue(caTransform3D: currentTransform)
        movement.toValue = NSValue(caTransform3D: targetTransform)
        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = currentOpacity
        fade.toValue = targetOpacity
        let group = CAAnimationGroup()
        group.animations = [movement, fade]
        group.duration = duration
        group.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 0.75, 0.25, 1)
        layer.add(group, forKey: "shelfVisibility")
        let completion = DispatchWorkItem { [weak self] in
            guard let self, self.animationGeneration == generation else { return }
            self.animationCompletion = nil
            self.panel?.suppressContentClicks = false
            if !self.wantsVisible { self.panel?.orderOut(nil) }
        }
        animationCompletion = completion
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: completion)
    }

    private func restorePreviousApplication() {
        if let app = previousApplication, !app.isTerminated { app.activate(options: [.activateIgnoringOtherApps]) }
    }

    func copy(_ item: ClipItem) {
        guard !model.isDemo else { model.feedback = "演示模式不会修改剪切板"; return }
        do { try writeItem(item); model.feedback = "已复制" }
        catch { model.feedback = "复制失败：\(error.localizedDescription)" }
    }

    func activate(_ item: ClipItem) {
        guard !model.isDemo else { model.feedback = "演示模式不会修改剪切板"; return }
        do { try writeItem(item) }
        catch { model.feedback = "复制失败：\(error.localizedDescription)"; return }
        refreshPastePermission()
        guard model.canAutoPaste else {
            model.feedback = "已复制，返回目标应用按⌘V粘贴"
            return
        }
        guard let target = previousApplication, !target.isTerminated else {
            model.feedback = "已复制；请切换到目标应用粘贴"
            return
        }
        hide()
        let pasteGeneration = animationGeneration
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) { [weak self] in
            guard let self, !self.wantsVisible, self.animationGeneration == pasteGeneration,
                  NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier,
                  let source = CGEventSource(stateID: .combinedSessionState),
                  let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
                  let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else { return }
            down.flags = .maskCommand
            up.flags = .maskCommand
            down.post(tap: .cghidEventTap)
            up.post(tap: .cghidEventTap)
        }
    }

    func requestPastePermission() {
        guard !model.isDemo else { model.feedback = "演示模式不会请求系统权限"; return }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        model.canAutoPaste = AXIsProcessTrustedWithOptions(options)
        if model.canAutoPaste { model.feedback = "已开启直接粘贴" }
        else {
            model.feedback = "请在系统设置中允许 Cpin 使用辅助功能"
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        }
    }

    private func installMonitors() {
        removeMonitors()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.isVisible, event.window === self.panel,
                  NSApp.modalWindow == nil, self.panel?.attachedSheet == nil else { return event }
            return self.handleKey(event) ? nil : event
        }
        clickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self, !self.mouseIsInsideApplicationWindow() else { return }
            self.hide(restoreFocus: false)
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return }
            Task { @MainActor [weak self] in
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == app.processIdentifier else { return }
                self?.hide(restoreFocus: false)
            }
        }
    }

    private func mouseIsInsideApplicationWindow() -> Bool {
        let location = NSEvent.mouseLocation
        return NSApp.windows.contains { $0.isVisible && NSMouseInRect(location, $0.frame, false) }
    }

    private func removeMonitors() {
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
        for monitor in [keyMonitor, clickMonitor].compactMap({ $0 }) { NSEvent.removeMonitor(monitor) }
        keyMonitor = nil; clickMonitor = nil
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let command = event.modifierFlags.contains(.command)
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if command, character == "f" {
            model.focusSearchToken += 1
            if let content = panel?.contentView { _ = focusSearchField(in: content) }
            return true
        }
        if command, let number = Int(character), (1...9).contains(number) {
            if model.visibleItems.indices.contains(number - 1) { activate(model.visibleItems[number - 1]) }
            return true
        }
        switch event.keyCode {
        case 53:
            if !model.query.isEmpty {
                model.query = ""
                model.selectedID = model.visibleItems.first?.id
                focusCards()
            }
            else { hide() }
            return true
        case 36, 76:
            if let item = model.selectedItem { activate(item) }
            return true
        case 123, 124, 125, 126:
            if panel?.firstResponder is NSTextView { return false }
            let vertical = model.panelPosition.isVertical
            guard vertical ? [125, 126].contains(event.keyCode) : [123, 124].contains(event.keyCode) else { return false }
            model.moveSelection([123, 126].contains(event.keyCode) ? -1 : 1)
            return true
        default: return false
        }
    }
}

import AppKit
import CpinCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let isDemo: Bool
    private var temporaryDirectory: URL?
    private var model: AppModel?
    private var monitor: ClipboardMonitor?
    private var panelController: PanelController?
    private var preferencesController: PreferencesController?
    private var hotKey: GlobalHotKey?
    private var statusItem: NSStatusItem?

    init(isDemo: Bool) { self.isDemo = isDemo }

    func applicationDidFinishLaunching(_ notification: Notification) {
        do {
            let directory: URL
            if isDemo {
                directory = FileManager.default.temporaryDirectory.appendingPathComponent("Cpin-Demo-\(UUID().uuidString)", isDirectory: true)
                temporaryDirectory = directory
            } else {
                directory = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                    .appendingPathComponent("Cpin", isDirectory: true)
            }
            let history = try ClipboardHistory(directory: directory, limit: isDemo ? 100 : AppModel.savedHistoryLimit())
            if isDemo { try DemoContent.populate(history) }
            let model = AppModel(history: history, isDemo: isDemo)
            let monitor = isDemo ? nil : ClipboardMonitor(history: history) { [weak model] message in model?.feedback = message }
            let panel = PanelController(
                model: model,
                writeItem: { [weak monitor] item in try monitor?.write(item) },
                beforeShow: { [weak monitor] in monitor?.captureChanges() }
            )
            self.model = model
            self.monitor = monitor
            self.panelController = panel
            let preferences = PreferencesController(model: model)
            self.preferencesController = preferences
            model.onActivate = { [weak panel] in panel?.activate($0) }
            model.onSelect = { [weak panel] in panel?.focusCards() }
            model.onCopy = { [weak panel] in panel?.copy($0) }
            model.onHide = { [weak panel] in panel?.hide() }
            model.onRequestPastePermission = { [weak panel] in panel?.requestPastePermission() }
            model.onPauseChange = { [weak monitor] in monitor?.isPaused = $0 }
            model.onLayoutChange = { [weak panel] in panel?.updateLayout() }
            model.onOpenPreferences = { [weak panel, weak preferences] in
                panel?.hide(restoreFocus: false)
                preferences?.show()
            }
            monitor?.isPaused = model.isPaused

            installEditMenu()
            installStatusItem()
            if !isDemo {
                monitor?.start()
                let hotKey = GlobalHotKey { [weak panel] in panel?.toggle() }
                model.shortcutAvailable = hotKey.register()
                self.hotKey = hotKey
            }
            panel.show()
            if !model.shortcutAvailable {
                model.feedback = "⇧⌘V 已被占用，可点击菜单栏图标打开"
            }
            if !isDemo {
                DispatchQueue.main.async { [weak panel] in panel?.requestInitialPastePermissionIfNeeded() }
            }
        } catch {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Cpin 无法打开本地历史"
            alert.informativeText = "已有数据已保留。\n\(error.localizedDescription)"
            alert.addButton(withTitle: "退出")
            alert.runModal()
            NSApp.terminate(nil)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        panelController?.show()
        return true
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        panelController?.refreshPastePermission()
    }

    func applicationWillTerminate(_ notification: Notification) {
        monitor?.stop()
        hotKey?.unregister()
        if let temporaryDirectory { try? FileManager.default.removeItem(at: temporaryDirectory) }
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            let image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Cpin 剪切板")
            image?.isTemplate = true
            button.image = image
            button.toolTip = isDemo ? "Cpin · 演示模式" : "Cpin · ⇧⌘V"
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
    }

    @objc private func statusClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(menuItem("打开剪切板", action: #selector(showPanel)))
            if model?.shortcutAvailable == false {
                let unavailable = NSMenuItem(title: "⇧⌘V 已被其他应用占用", action: nil, keyEquivalent: "")
                unavailable.isEnabled = false
                menu.addItem(unavailable)
            }
            menu.addItem(.separator())
            menu.addItem(menuItem("偏好设置…", action: #selector(showPreferences)))
            menu.addItem(menuItem(model?.isPaused == true ? "继续记录" : "暂停记录", action: #selector(togglePause)))
            menu.addItem(menuItem("启用直接粘贴…", action: #selector(enablePaste)))
            menu.addItem(.separator())
            menu.addItem(menuItem("退出 Cpin", action: #selector(quit)))
            statusItem?.menu = menu
            statusItem?.button?.performClick(nil)
            statusItem?.menu = nil
        } else {
            panelController?.toggle()
        }
    }

    private func menuItem(_ title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }

    private func installEditMenu() {
        let main = NSMenu()
        let app = NSMenuItem()
        let appMenu = NSMenu()
        let settings = menuItem("偏好设置…", action: #selector(showPreferences))
        settings.keyEquivalent = ","
        appMenu.addItem(settings)
        appMenu.addItem(.separator())
        let quit = menuItem("退出 Cpin", action: #selector(quit))
        quit.keyEquivalent = "q"
        appMenu.addItem(quit)
        app.submenu = appMenu
        main.addItem(app)
        let edit = NSMenuItem(title: "编辑", action: nil, keyEquivalent: "")
        let editMenu = NSMenu(title: "编辑")
        editMenu.addItem(withTitle: "撤销", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "复制", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        edit.submenu = editMenu
        main.addItem(edit)
        NSApp.mainMenu = main
    }

    @objc private func showPanel() { panelController?.show() }
    @objc private func showPreferences() { model?.openPreferences() }
    @objc private func togglePause() {
        if let model { model.setPaused(!model.isPaused) }
    }
    @objc private func enablePaste() { panelController?.requestPastePermission() }
    @objc private func quit() { NSApp.terminate(nil) }
}

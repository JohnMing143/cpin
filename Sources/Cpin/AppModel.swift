import AppKit
import Combine
import CpinCore
import ImageIO

@MainActor
final class AppModel: ObservableObject {
    @Published var query = "" {
        didSet { normalizeSelection() }
    }
    @Published var pinnedOnly = false {
        didSet { normalizeSelection() }
    }
    @Published var selectedID: UUID?
    @Published var isPaused: Bool {
        didSet {
            guard oldValue != isPaused else { return }
            if !isDemo { preferences.set(isPaused, forKey: "capturePaused") }
            onPauseChange?(isPaused)
        }
    }
    @Published private(set) var historyLimit: Int
    @Published var panelMode: PanelMode {
        didSet {
            guard oldValue != panelMode else { return }
            if !isDemo { preferences.set(panelMode.rawValue, forKey: "panelMode") }
            onLayoutChange?()
        }
    }
    @Published var panelPosition: PanelPosition {
        didSet {
            guard oldValue != panelPosition else { return }
            if !isDemo { preferences.set(panelPosition.rawValue, forKey: "panelPosition") }
            onLayoutChange?()
        }
    }
    @Published var canAutoPaste = false
    @Published private(set) var storageBytes: Int64
    @Published var feedback: String?
    @Published var focusSearchToken = 0
    @Published var shortcutAvailable = true
    @Published private(set) var items: [ClipItem]

    let isDemo: Bool
    let history: ClipboardHistory

    var onActivate: ((ClipItem) -> Void)?
    var onSelect: (() -> Void)?
    var onCopy: ((ClipItem) -> Void)?
    var onHide: (() -> Void)?
    var onPauseChange: ((Bool) -> Void)?
    var onRequestPastePermission: (() -> Void)?
    var onOpenPreferences: (() -> Void)?
    var onLayoutChange: (() -> Void)?

    private let preferences: UserDefaults
    private var historySubscriptions = Set<AnyCancellable>()
    private let images = NSCache<NSString, NSImage>()
    private let icons = NSCache<NSString, NSImage>()

    init(history: ClipboardHistory, isDemo: Bool, preferences: UserDefaults = .standard) {
        self.history = history
        self.isDemo = isDemo
        self.preferences = preferences
        self.items = history.items
        self.historyLimit = history.limit
        self.storageBytes = history.storageBytes
        self.isPaused = isDemo ? false : preferences.bool(forKey: "capturePaused")
        self.panelMode = isDemo ? .floating : PanelMode(rawValue: preferences.string(forKey: "panelMode") ?? "") ?? .floating
        self.panelPosition = isDemo ? .bottom : PanelPosition(rawValue: preferences.string(forKey: "panelPosition") ?? "") ?? .bottom
        images.countLimit = 24
        images.totalCostLimit = 32 * 1_024 * 1_024
        icons.countLimit = 32
        history.$items.dropFirst().sink { [weak self] items in
            guard let self else { return }
            self.items = items
            self.normalizeSelection()
        }.store(in: &historySubscriptions)
        history.$storageBytes.dropFirst().sink { [weak self] bytes in
            self?.storageBytes = bytes
        }.store(in: &historySubscriptions)
        normalizeSelection()
    }

    static func savedHistoryLimit(in preferences: UserDefaults = .standard) -> Int {
        guard let number = preferences.object(forKey: "historyLimit") as? NSNumber else { return 100 }
        let value = number.intValue
        return value >= 0 ? value : 100
    }

    var visibleItems: [ClipItem] {
        let search = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return items.filter { item in
            (!pinnedOnly || item.isPinned) && (
                search.isEmpty ||
                (item.text?.localizedStandardContains(search) ?? false) ||
                item.sourceName.localizedStandardContains(search) ||
                (item.kind == .image && "图片 image".localizedStandardContains(search))
            )
        }.sorted { lhs, rhs in
            if lhs.isPinned != rhs.isPinned { return lhs.isPinned }
            if lhs.lastCopiedAt != rhs.lastCopiedAt { return lhs.lastCopiedAt > rhs.lastCopiedAt }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }

    var selectedItem: ClipItem? { visibleItems.first { $0.id == selectedID } }
    var totalCount: Int { items.count }
    var pinnedCount: Int { items.filter(\.isPinned).count }

    func select(_ item: ClipItem) {
        selectedID = item.id
        onSelect?()
    }

    func moveSelection(_ offset: Int) {
        let visible = visibleItems
        guard !visible.isEmpty else { return }
        let current = visible.firstIndex { $0.id == selectedID } ?? 0
        let next = max(0, min(visible.count - 1, current + offset))
        selectedID = visible[next].id
    }

    func activate(_ item: ClipItem) { onActivate?(item) }
    func handleCardClick(_ item: ClipItem) {
        select(item)
        activate(item)
    }
    func copy(_ item: ClipItem) { onCopy?(item) }
    func hidePanel() { onHide?() }
    func requestPastePermission() { onRequestPastePermission?() }
    func openPreferences() { onOpenPreferences?() }
    func quit() { NSApplication.shared.terminate(nil) }
    func setPaused(_ value: Bool) { isPaused = value }

    func togglePin(_ item: ClipItem) {
        perform { try history.togglePin(item.id) }
    }

    func delete(_ item: ClipItem) {
        perform { try history.remove(item.id) }
        images.removeObject(forKey: item.id.uuidString as NSString)
    }

    func clearHistory() {
        images.removeAllObjects()
        perform {
            try history.clearUnpinned()
            feedback = "历史已清空，置顶内容已保留"
        }
    }

    func clearAllHistory() {
        images.removeAllObjects()
        perform {
            try history.clearAll()
            feedback = "全部记录和图片已清理"
        }
    }

    func refreshStorageUsage() {
        perform { try history.refreshStorageUsage() }
    }

    @discardableResult
    func setHistoryLimit(_ value: Int) -> Bool {
        guard value >= 0 else {
            feedback = "请输入正整数，或选择不限制条数"
            return false
        }
        return perform {
            try history.setLimit(value)
            historyLimit = history.limit
            if !isDemo { preferences.set(value, forKey: "historyLimit") }
            feedback = value == 0 ? "已设置为不限制条数" : "记录上限已设为 \(value) 条"
        }
    }

    func openDataFolder() {
        NSWorkspace.shared.open(history.directory)
    }

    func image(for item: ClipItem) -> NSImage? {
        let key = item.id.uuidString as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let url = history.imageURL(for: item),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let thumbnail = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 640,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: true
              ] as CFDictionary) else { return nil }
        let image = NSImage(cgImage: thumbnail, size: .zero)
        images.setObject(image, forKey: key, cost: thumbnail.width * thumbnail.height * 4)
        return image
    }

    func sourceIcon(for item: ClipItem) -> NSImage? {
        guard let identifier = item.sourceBundleIdentifier else { return nil }
        let key = identifier as NSString
        if let cached = icons.object(forKey: key) { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: identifier) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        icon.size = NSSize(width: 16, height: 16)
        icons.setObject(icon, forKey: key)
        return icon
    }

    private func normalizeSelection() {
        let visible = visibleItems
        if !visible.contains(where: { $0.id == selectedID }) {
            selectedID = visible.first?.id
        }
    }

    @discardableResult
    private func perform(_ action: () throws -> Void) -> Bool {
        do {
            try action()
            return true
        } catch {
            feedback = "操作未完成：\(error.localizedDescription)"
            return false
        }
    }
}

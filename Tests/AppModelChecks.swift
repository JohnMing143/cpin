#if STANDALONE_CHECKS
import Foundation
import CpinCore

@main
struct AppModelChecks {
    @MainActor
    static func main() throws {
        let suite = "Cpin-Preferences-Checks-\(UUID().uuidString)"
        let preferences = UserDefaults(suiteName: suite)!
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(suite)
        defer {
            preferences.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: directory)
        }
        precondition(AppModel.savedHistoryLimit(in: preferences) == 100)
        let history = try ClipboardHistory(directory: directory)
        let model = AppModel(history: history, isDemo: false, preferences: preferences)
        precondition(model.panelMode == .floating && model.panelPosition == .bottom)
        var changes = 0
        model.onLayoutChange = { changes += 1 }
        model.panelMode = .docked
        model.panelPosition = .right
        model.panelPosition = .right
        precondition(changes == 2)
        precondition(model.setHistoryLimit(137))
        precondition(AppModel.savedHistoryLimit(in: preferences) == 137 && history.limit == 137)
        let reloaded = AppModel(history: history, isDemo: false, preferences: preferences)
        precondition(reloaded.panelMode == .docked && reloaded.panelPosition == .right)
        precondition(model.setHistoryLimit(0))
        precondition(AppModel.savedHistoryLimit(in: preferences) == 0 && history.limit == 0)
        precondition(!model.setHistoryLimit(-1))
        precondition(model.historyLimit == 0 && AppModel.savedHistoryLimit(in: preferences) == 0)

        let item = try history.addText("single-click fixture", sourceName: "Tests")!
        var actions: [String] = []
        model.onSelect = { actions.append("select") }
        model.onActivate = { activated in
            precondition(activated.id == item.id)
            actions.append("activate")
        }
        model.handleCardClick(item)
        precondition(actions == ["select", "activate"] && model.selectedID == item.id)
        precondition(model.totalCount == 1 && model.storageBytes == history.storageBytes)
        model.togglePin(item)
        precondition(model.pinnedCount == 1)
        model.clearAllHistory()
        precondition(model.totalCount == 0 && model.pinnedCount == 0)
        precondition(model.storageBytes == history.storageBytes)

        let demo = AppModel(history: history, isDemo: true, preferences: preferences)
        precondition(demo.panelMode == .floating && demo.panelPosition == .bottom)
        demo.panelMode = .floating
        demo.panelPosition = .left
        precondition(demo.setHistoryLimit(42))
        demo.setPaused(true)
        precondition(preferences.string(forKey: "panelPosition") == "right")
        precondition(AppModel.savedHistoryLimit(in: preferences) == 0)
        precondition(!preferences.bool(forKey: "capturePaused"))
        print("App model checks passed: single-click activation, preferences persistence, custom limits, storage updates and demo isolation.")
    }
}
#endif

import SwiftUI
import CpinCore

struct PreferencesView: View {
    @ObservedObject var model: AppModel
    @State private var limitDraft = "100"
    @State private var unlimited = false
    @State private var limitError: String?
    @State private var confirmingAll = false
    @State private var confirmingUnpinned = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                section("面板外观", icon: "rectangle.bottomthird.inset.filled") {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("显示模式").font(.system(size: 12, weight: .medium))
                        Picker("显示模式", selection: $model.panelMode) {
                            ForEach(PanelMode.allCases, id: \.self) { mode in Text(mode.title).tag(mode) }
                        }.pickerStyle(.segmented).labelsHidden()
                        Text("出现位置").font(.system(size: 12, weight: .medium))
                        Picker("出现位置", selection: $model.panelPosition) {
                            ForEach(PanelPosition.allCases, id: \.self) { position in Text(position.title).tag(position) }
                        }.pickerStyle(.segmented).labelsHidden()
                    }
                }
                section("单击卡片", icon: "cursorarrow.click") {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(model.canAutoPaste ? "直接粘贴到当前应用" : "复制内容，再按 ⌘V 手动粘贴", systemImage: model.canAutoPaste ? "checkmark.circle.fill" : "doc.on.doc")
                            .font(.system(size: 13, weight: .medium))
                        Text("直接粘贴需要辅助功能权限。图钉按钮仅用于置顶。")
                            .font(.system(size: 11)).foregroundStyle(ShelfTheme.secondaryInk)
                        Button(model.canAutoPaste ? "重新检查授权" : "授权直接粘贴…") { model.requestPastePermission() }
                    }
                }
                section("剪切板历史", icon: "clock.arrow.circlepath") {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle("暂停记录", isOn: Binding(get: { model.isPaused }, set: { model.setPaused($0) }))
                            .toggleStyle(.switch).controlSize(.small)
                        Divider()
                        Toggle("不限制记录条数", isOn: $unlimited).toggleStyle(.checkbox)
                        HStack(spacing: 10) {
                            Text("记录上限")
                            TextField("输入条数", text: $limitDraft).textFieldStyle(.roundedBorder)
                                .frame(width: 100).disabled(unlimited)
                                .onSubmit { applyLimit() }
                            Text("条").foregroundStyle(ShelfTheme.secondaryInk)
                            Spacer()
                            Button("应用") { applyLimit() }
                        }
                        if let limitError { Text(limitError).font(.system(size: 11)).foregroundStyle(.red) }
                        Text("输入任意正整数，点击应用后生效。置顶内容长期保留，不计入上限。降低上限会移除较早的未置顶记录。")
                            .font(.system(size: 11)).foregroundStyle(ShelfTheme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    }
                }
                section("本地存储", icon: "internaldrive") {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(ByteCountFormatter.string(fromByteCount: model.storageBytes, countStyle: .file))
                                .font(.system(size: 24, weight: .semibold, design: .rounded))
                            Spacer()
                            Text("\(model.totalCount) 条记录").foregroundStyle(ShelfTheme.secondaryInk)
                        }
                        Text("内容仅保存在这台 Mac。一键清理会删除全部历史、置顶内容及保存的图片。")
                            .font(.system(size: 11)).foregroundStyle(ShelfTheme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 10) {
                            Button("一键清理…", role: .destructive) { confirmingAll = true }
                            Button("清空未置顶…") { confirmingUnpinned = true }
                            Spacer()
                        }
                        Button { model.openDataFolder() } label: { Label("打开本地数据目录", systemImage: "folder") }
                    }
                }
                if let feedback = model.feedback {
                    Text(feedback).font(.system(size: 12, weight: .medium))
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                        .background(ShelfTheme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 9))
                        .accessibilityLabel("状态：\(feedback)")
                }
                HStack {
                    Text(model.isDemo ? "演示模式 · 不修改真实历史" : "Cpin · 轻量、本地、随手可用")
                        .font(.system(size: 10)).foregroundStyle(ShelfTheme.secondaryInk)
                    Spacer()
                    Button("退出 Cpin") { model.quit() }.controlSize(.small)
                }
            }.padding(24)
        }
        .font(.system(size: 12)).foregroundStyle(ShelfTheme.ink)
        .frame(minWidth: 460, idealWidth: 500, maxWidth: .infinity, minHeight: 560, idealHeight: 730, maxHeight: .infinity)
        .background(Color(red: 0.98, green: 0.97, blue: 0.95))
        .tint(ShelfTheme.accent).preferredColorScheme(.light)
        .onAppear { syncLimit(); model.refreshStorageUsage() }
        .onChange(of: model.historyLimit) { _ in syncLimit() }
        .alert("删除全部剪切板历史？", isPresented: $confirmingAll) {
            Button("取消", role: .cancel) { }
            Button("删除全部", role: .destructive) { model.clearAllHistory() }
        } message: { Text("包括所有置顶内容及保存的图片。此操作无法撤销。") }
        .alert("清空未置顶的记录？", isPresented: $confirmingUnpinned) {
            Button("取消", role: .cancel) { }
            Button("清空记录", role: .destructive) { model.clearHistory() }
        } message: { Text("已置顶的内容会保留，清空后无法恢复。") }
    }

    private func section<Content: View>(_ title: String, icon: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon).font(.system(size: 13, weight: .semibold))
            content().padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.black.opacity(0.06)))
        }
    }

    private func syncLimit() {
        unlimited = model.historyLimit == 0
        limitDraft = model.historyLimit > 0 ? String(model.historyLimit) : "100"
        limitError = nil
    }

    private func applyLimit() {
        let value: Int
        if unlimited {
            value = 0
        } else {
            guard let parsed = Int(limitDraft.trimmingCharacters(in: .whitespacesAndNewlines)), parsed >= 1 else {
                limitError = "请输入有效的正整数，或选择不限制条数。"
                return
            }
            value = parsed
        }
        if model.setHistoryLimit(value) { limitError = nil }
        else { limitError = "未能保存记录上限，请查看下方状态提示。" }
    }
}

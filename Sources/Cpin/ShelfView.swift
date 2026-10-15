import SwiftUI
import CpinCore

struct ShelfView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var vertical: Bool { model.panelPosition.isVertical }
    private var outline: ShelfOutline { ShelfOutline(mode: model.panelMode, position: model.panelPosition) }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 24).padding(.top, 18).padding(.bottom, 16)
            if model.visibleItems.isEmpty {
                emptyState.frame(maxWidth: .infinity, maxHeight: vertical ? .infinity : nil)
                    .frame(height: vertical ? nil : 250)
            } else {
                cards
            }
            footer.padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 17)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(red: 0.97, green: 0.98, blue: 0.99).opacity(0.48))
        .background(.ultraThinMaterial)
        .clipShape(outline)
        .overlay(outline.stroke(.white.opacity(0.65), lineWidth: 1).clipShape(outline))
        .tint(ShelfTheme.accent).preferredColorScheme(.light)
        .onChange(of: model.focusSearchToken) { _ in searchFocused = true }
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(vertical ? .vertical : .horizontal, showsIndicators: false) {
                if vertical {
                    LazyVStack(spacing: 12) { cardItems }.padding(.horizontal, 24).padding(.vertical, 7)
                } else {
                    LazyHStack(spacing: 12) { cardItems }.padding(.horizontal, 24).padding(.vertical, 7)
                }
            }.frame(height: vertical ? nil : 250)
                .onChange(of: model.selectedID) { id in
                    if let id {
                        if reduceMotion { proxy.scrollTo(id) }
                        else { withAnimation(.easeOut(duration: 0.18)) { proxy.scrollTo(id) } }
                    }
                }
        }
    }

    private var cardItems: some View {
        ForEach(Array(model.visibleItems.enumerated()), id: \.element.id) { index, item in
            ClipCardView(model: model, item: item, index: index).id(item.id)
        }
    }

    @ViewBuilder private var header: some View {
        if vertical {
            VStack(spacing: 14) {
                HStack { brand; Spacer(); controls }
                HStack { tabs; Spacer(minLength: 0) }
                search
            }
        } else {
            HStack(spacing: 18) {
                brand
                tabs
                Spacer(minLength: 12)
                search.frame(width: 242)
                controls
            }
        }
    }

    private var brand: some View {
        HStack(spacing: 9) {
            Image(systemName: "square.on.square.fill")
                .font(.system(size: 16, weight: .bold)).foregroundStyle(.white)
                .frame(width: 31, height: 31)
                .background(ShelfTheme.accent.gradient, in: RoundedRectangle(cornerRadius: 9))
            Text("Cpin").font(.system(size: 20, weight: .bold, design: .rounded)).foregroundStyle(ShelfTheme.ink)
        }
    }

    private var tabs: some View {
        HStack(spacing: 3) {
            tab("全部", count: model.totalCount, pinned: false)
            tab("已置顶", count: model.pinnedCount, pinned: true)
        }.padding(3).background(.black.opacity(0.05), in: Capsule())
    }

    private var search: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(.system(size: 12))
            TextField("搜索剪切板", text: $model.query).textFieldStyle(.plain)
                .font(.system(size: 12)).focused($searchFocused)
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).accessibilityLabel("清除搜索")
            } else {
                Text("⌘ F").font(.system(size: 10))
            }
        }.foregroundStyle(ShelfTheme.secondaryInk).padding(.horizontal, 11).frame(height: 32)
            .background(.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(.black.opacity(0.12)))
    }

    private var controls: some View {
        HStack(spacing: 7) {
            Button { model.openPreferences() } label: {
                Image(systemName: "slider.horizontal.3").frame(width: 30, height: 30)
            }.help("偏好设置").accessibilityLabel("偏好设置")
            Button { model.hidePanel() } label: {
                Image(systemName: dismissSymbol).frame(width: 30, height: 30)
            }.help("收起 · Esc").accessibilityLabel("收起剪切板")
        }.buttonStyle(.plain).font(.system(size: 13, weight: .medium)).foregroundStyle(ShelfTheme.ink)
    }

    private var dismissSymbol: String {
        switch model.panelPosition {
        case .bottom: return "chevron.down"
        case .top: return "chevron.up"
        case .left: return "chevron.left"
        case .right: return "chevron.right"
        }
    }

    private func tab(_ title: String, count: Int, pinned: Bool) -> some View {
        Button { model.pinnedOnly = pinned } label: {
            HStack(spacing: 5) {
                Text(title)
                Text("\(count)").font(.system(size: 10, weight: .medium))
            }.font(.system(size: 12, weight: .medium)).padding(.horizontal, 12).padding(.vertical, 7)
                .foregroundStyle(model.pinnedOnly == pinned ? ShelfTheme.ink : ShelfTheme.secondaryInk)
                .background(model.pinnedOnly == pinned ? .white : .clear, in: Capsule())
        }.buttonStyle(.plain)
    }

    private var emptyState: some View {
        VStack(spacing: 11) {
            Image(systemName: !model.query.isEmpty ? "magnifyingglass" : model.pinnedOnly ? "pin" : "doc.on.clipboard")
                .font(.system(size: 30, weight: .light)).foregroundStyle(ShelfTheme.accent)
            Text(!model.query.isEmpty ? "没有找到匹配内容" : model.pinnedOnly ? "把常用内容留在这里" : "复制的内容，会在这里相遇")
                .font(.system(size: 15, weight: .medium)).foregroundStyle(ShelfTheme.ink)
            Text(!model.query.isEmpty ? "试试其他关键词" : model.pinnedOnly ? "点击卡片上的图钉，即可置顶保存" : "复制文字、链接或图片开始")
                .font(.system(size: 12)).foregroundStyle(ShelfTheme.secondaryInk)
            if !model.query.isEmpty {
                Button("清除搜索") { model.query = "" }.buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium)).foregroundStyle(ShelfTheme.accent).padding(.top, 3)
            }
        }.multilineTextAlignment(.center).padding(.horizontal, 20)
    }

    @ViewBuilder private var footer: some View {
        if vertical {
            VStack(alignment: .leading, spacing: 9) {
                privacy
                Text(model.canAutoPaste ? "点击粘贴 · ↑ ↓ 选择 · esc 收起" : "点击复制 · ↑ ↓ 选择 · esc 收起")
                if model.shortcutAvailable && !model.isDemo { Text("⇧⌘V 呼出") }
            }.font(.system(size: 10)).foregroundStyle(ShelfTheme.secondaryInk).frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(spacing: 6) {
                privacy
                Spacer()
                if model.shortcutAvailable && !model.isDemo { Text("⇧⌘V 呼出").padding(.trailing, 12) }
                Text(model.canAutoPaste ? "点击粘贴" : "点击复制").padding(.trailing, 12)
                Text("← → 选择").padding(.trailing, 12)
                Text("esc 收起")
            }.font(.system(size: 10)).foregroundStyle(ShelfTheme.secondaryInk)
        }
    }

    private var privacy: some View {
        HStack(spacing: 6) {
            Image(systemName: model.isPaused ? "pause.circle" : "lock.shield")
            Text(model.feedback ?? (model.isPaused ? "已暂停记录" : (model.isDemo ? "演示模式 · 不记录剪切板" : "仅保存在这台 Mac")))
                .lineLimit(2)
        }
    }
}

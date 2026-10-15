import SwiftUI
import AppKit
import CpinCore

struct ClipCardView: View {
    @ObservedObject var model: AppModel
    let item: ClipItem
    let index: Int
    @State private var hovered = false
    private var tint: Color { ShelfTheme.color(item.kind) }
    private var selected: Bool { model.selectedID == item.id }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 7) {
                Image(systemName: ShelfTheme.symbol(item.kind)).font(.system(size: 12, weight: .semibold))
                Text(ShelfTheme.label(item.kind)).font(.system(size: 11, weight: .semibold))
                Spacer()
                Button { model.togglePin(item) } label: {
                    Image(systemName: item.isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 12, weight: .medium)).frame(width: 28, height: 28)
                }.buttonStyle(.plain).help(item.isPinned ? "取消置顶" : "置顶")
                    .accessibilityLabel(item.isPinned ? "取消置顶" : "置顶")
            }.foregroundStyle(tint).padding(.horizontal, 15).padding(.vertical, 7)
                .background(tint.opacity(hovered ? 0.20 : 0.14))
            Button { model.handleCardClick(item) } label: {
                VStack(alignment: .leading, spacing: 0) {
                    content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .padding(.horizontal, 15).padding(.top, 10).padding(.bottom, 12).clipped()
                    HStack(spacing: 6) {
                        if let icon = model.sourceIcon(for: item) {
                            Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                        } else {
                            Image(systemName: "app.dashed").font(.system(size: 12))
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.sourceName).font(.system(size: 10, weight: .medium)).lineLimit(1)
                            Text(relativeTime).font(.system(size: 10)).foregroundStyle(ShelfTheme.secondaryInk).lineLimit(1)
                        }
                        Spacer(minLength: 3)
                        if index < 9 {
                            Text("⌘\(index + 1)").font(.system(size: 10, weight: .medium, design: .monospaced))
                                .padding(.horizontal, 5).padding(.vertical, 3)
                                .background(.black.opacity(0.035), in: RoundedRectangle(cornerRadius: 4))
                        }
                        Image(systemName: "arrow.up.right").font(.system(size: 10, weight: .semibold))
                    }.foregroundStyle(ShelfTheme.ink)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(Color(red: 0.98, green: 0.985, blue: 0.99))
                        .overlay(alignment: .top) { Rectangle().fill(.black.opacity(0.045)).frame(height: 0.5) }
                }.contentShape(Rectangle())
            }.buttonStyle(.plain)
                .help(model.canAutoPaste ? "点击粘贴" : "点击复制，然后手动粘贴")
                .accessibilityLabel("\(model.canAutoPaste ? "粘贴" : "复制")\(ShelfTheme.label(item.kind))，\(item.sourceName)")
        }
        .frame(width: model.panelPosition.isVertical ? 264 : 216, height: 236)
        .background(.white, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(selected ? ShelfTheme.accent.opacity(0.85) : hovered ? tint.opacity(0.65) : .black.opacity(0.065), lineWidth: selected || hovered ? 1.5 : 0.75))
        .shadow(color: .black.opacity(hovered ? 0.11 : 0.055), radius: hovered ? 7 : 5, y: 3)
        .onHover { hovered = $0 }
        .animation(.easeOut(duration: 0.12), value: hovered)
        .contextMenu {
            Button { model.activate(item) } label: { Label("粘贴", systemImage: "doc.on.clipboard") }
            Button { model.copy(item) } label: { Label("复制", systemImage: "doc.on.doc") }
            Divider()
            Button { model.togglePin(item) } label: { Label(item.isPinned ? "取消置顶" : "置顶", systemImage: "pin") }
            Button(role: .destructive) { model.delete(item) } label: { Label("删除", systemImage: "trash") }
        }
    }

    private var relativeTime: String {
        guard Date().timeIntervalSince(item.lastCopiedAt) >= 60 else { return "刚刚" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .full
        return formatter.localizedString(for: item.lastCopiedAt, relativeTo: Date())
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            if let image = model.image(for: item) {
                GeometryReader { proxy in
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "photo").font(.system(size: 30, weight: .light))
                    Text("图片不可用").font(.system(size: 11))
                }.foregroundStyle(tint).frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        case .link:
            VStack(alignment: .leading, spacing: 12) {
                Image(systemName: "arrow.up.right").font(.system(size: 24, weight: .light)).foregroundStyle(tint)
                Text(URL(string: (item.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))?.host ?? "链接")
                    .font(.system(size: 20, weight: .semibold, design: .rounded)).lineLimit(2)
                Text(item.text ?? "").font(.system(size: 11)).foregroundStyle(ShelfTheme.secondaryInk).lineLimit(3)
            }.foregroundStyle(ShelfTheme.ink)
        case .code:
            Text(item.text ?? "").font(.system(size: 11, design: .monospaced))
                .foregroundStyle(ShelfTheme.ink).lineSpacing(4).lineLimit(8)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        case .text:
            Text(item.text ?? "").font(.system(size: 13)).lineSpacing(5).lineLimit(7)
                .foregroundStyle(ShelfTheme.ink).frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

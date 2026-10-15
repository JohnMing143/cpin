import SwiftUI
import CpinCore

enum ShelfTheme {
    static let accent = Color(red: 0.91, green: 0.39, blue: 0.20)
    static let secondaryInk = Color(red: 0.36, green: 0.38, blue: 0.41)
    static let ink = Color(red: 0.15, green: 0.17, blue: 0.20)
    static func color(_ kind: ClipKind) -> Color {
        switch kind {
        case .text: return Color(red: 0.75, green: 0.40, blue: 0.21)
        case .link: return Color(red: 0.27, green: 0.49, blue: 0.70)
        case .code: return Color(red: 0.52, green: 0.40, blue: 0.69)
        case .image: return Color(red: 0.32, green: 0.56, blue: 0.43)
        }
    }
    static func symbol(_ kind: ClipKind) -> String {
        switch kind { case .text: return "text.alignleft"; case .link: return "link"; case .code: return "chevron.left.forwardslash.chevron.right"; case .image: return "photo" }
    }
    static func label(_ kind: ClipKind) -> String {
        switch kind { case .text: return "文本"; case .link: return "链接"; case .code: return "代码"; case .image: return "图片" }
    }
}

/// The edge touching the display remains flush; the two inward corners soften the shelf.
struct ShelfOutline: Shape {
    var mode: PanelMode
    var position: PanelPosition

    func path(in rect: CGRect) -> Path {
        let radius = min(24, min(rect.width, rect.height) / 2)
        let floating = mode == .floating
        let topLeft: CGFloat = floating || position == .bottom || position == .right ? radius : 0
        let topRight: CGFloat = floating || position == .bottom || position == .left ? radius : 0
        let bottomRight: CGFloat = floating || position == .top || position == .left ? radius : 0
        let bottomLeft: CGFloat = floating || position == .top || position == .right ? radius : 0
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + topLeft, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - topRight, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + topRight), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottomRight))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - bottomRight, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + bottomLeft, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - bottomLeft), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + topLeft))
        path.addQuadCurve(to: CGPoint(x: rect.minX + topLeft, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

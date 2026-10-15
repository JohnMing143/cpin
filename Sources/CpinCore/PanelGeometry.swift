import Foundation
import CoreGraphics

public enum PanelMode: String, CaseIterable, Sendable {
    case floating, docked
    public var title: String { self == .floating ? "悬浮" : "贴边" }
}

public enum PanelPosition: String, CaseIterable, Sendable {
    case bottom, top, left, right
    public var title: String {
        switch self {
        case .bottom: return "底部"
        case .top: return "顶部"
        case .left: return "左侧"
        case .right: return "右侧"
        }
    }
    public var isVertical: Bool { self == .left || self == .right }
}

public enum PanelGeometry {
    public static func frame(screenFrame: CGRect, visibleFrame: CGRect, mode: PanelMode, position: PanelPosition) -> CGRect {
        if mode == .floating {
            // Clamp margins on unusually small displays to keep all dimensions positive.
            let marginX = min(16, max(0, visibleFrame.width / 4))
            let marginY = min(12, max(0, visibleFrame.height / 4))
            let available = visibleFrame.insetBy(dx: marginX, dy: marginY)
            let width = min(position.isVertical ? 312 : 1320, max(0, available.width))
            let height = min(position.isVertical ? 840 : 374, max(0, available.height))
            var origin = CGPoint(x: available.midX - width / 2, y: available.midY - height / 2)
            switch position {
            case .bottom: origin.y = available.minY
            case .top: origin.y = available.maxY - height
            case .left: origin.x = available.minX
            case .right: origin.x = available.maxX - width
            }
            return CGRect(origin: origin, size: CGSize(width: width, height: height))
        }
        let top = min(screenFrame.maxY, visibleFrame.maxY)
        let availableHeight = max(0, top - screenFrame.minY)
        let width = position.isVertical ? min(312, max(0, screenFrame.width)) : max(0, screenFrame.width)
        let height = position.isVertical ? availableHeight : min(374, availableHeight)
        let x = position == .right ? screenFrame.maxX - width : screenFrame.minX
        let y = position == .top ? top - height : screenFrame.minY
        return CGRect(x: x, y: y, width: width, height: height)
    }
}

#if STANDALONE_CHECKS
import Foundation
import CoreGraphics
import CpinCore

@main
struct PanelGeometryChecks {
    static func main() {
        let screens = [
            (CGRect(x: 0, y: 0, width: 1512, height: 982), CGRect(x: 0, y: 70, width: 1512, height: 874)),
            (CGRect(x: -1920, y: -200, width: 1920, height: 1080), CGRect(x: -1920, y: -130, width: 1920, height: 972)),
            (CGRect(x: 1512, y: 100, width: 280, height: 300), CGRect(x: 1512, y: 140, width: 280, height: 236)),
            (CGRect(x: -20, y: -20, width: 20, height: 20), CGRect(x: -20, y: -20, width: 20, height: 16))
        ]
        var checks = 0
        for (screen, visible) in screens {
            for mode in PanelMode.allCases {
                for position in PanelPosition.allCases {
                    let result = PanelGeometry.frame(screenFrame: screen, visibleFrame: visible, mode: mode, position: position)
                    precondition(result.width > 0 && result.height > 0)
                    precondition(result.minX >= screen.minX && result.maxX <= screen.maxX)
                    precondition(result.minY >= screen.minY && result.maxY <= visible.maxY)
                    if mode == .floating {
                        precondition(visible.contains(result))
                        precondition(result.width <= (position.isVertical ? 312 : 1320))
                        precondition(result.height <= (position.isVertical ? 840 : 374))
                        switch position {
                        case .bottom: precondition(result.minY == visible.minY + min(12, visible.height / 4))
                        case .top: precondition(result.maxY == visible.maxY - min(12, visible.height / 4))
                        case .left: precondition(result.minX == visible.minX + min(16, visible.width / 4))
                        case .right: precondition(result.maxX == visible.maxX - min(16, visible.width / 4))
                        }
                    } else {
                        if position.isVertical {
                            precondition(result.height == visible.maxY - screen.minY)
                            precondition(result.width == min(312, screen.width))
                            precondition(result.minY == screen.minY)
                        } else {
                            precondition(result.width == screen.width)
                            precondition(result.height == min(374, visible.maxY - screen.minY))
                        }
                        switch position {
                        case .bottom: precondition(result.minY == screen.minY)
                        case .top: precondition(result.maxY == visible.maxY)
                        case .left: precondition(result.minX == screen.minX)
                        case .right: precondition(result.maxX == screen.maxX)
                        }
                    }
                    checks += 1
                }
            }
        }
        precondition(PanelPosition.left.isVertical && PanelPosition.right.isVertical)
        precondition(!PanelPosition.top.isVertical && !PanelPosition.bottom.isVertical)
        print("Panel geometry checks passed: \(checks) layouts across normal, negative-coordinate, narrow and tiny screens.")
    }
}
#endif

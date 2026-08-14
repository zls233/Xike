import CoreGraphics
import Foundation

enum BreakOverlayPosition: String, Codable, CaseIterable, Identifiable, Sendable {
    case center
    case topLeading
    case topTrailing
    case bottomLeading
    case bottomTrailing

    var id: String { rawValue }

    var title: String {
        return switch self {
        case .center: "屏幕中央".xikeLocalized
        case .topLeading: "左上角".xikeLocalized
        case .topTrailing: "右上角".xikeLocalized
        case .bottomLeading: "左下角".xikeLocalized
        case .bottomTrailing: "右下角".xikeLocalized
        }
    }

    var systemImage: String {
        switch self {
        case .center: "rectangle.center.inset.filled"
        case .topLeading: "rectangle.inset.topleft.filled"
        case .topTrailing: "rectangle.inset.topright.filled"
        case .bottomLeading: "rectangle.inset.bottomleft.filled"
        case .bottomTrailing: "rectangle.inset.bottomright.filled"
        }
    }

    func origin(panelSize: CGSize, in visibleFrame: CGRect, margin: CGFloat = 28) -> CGPoint {
        let leading = visibleFrame.minX + margin
        let trailing = visibleFrame.maxX - panelSize.width - margin
        let bottom = visibleFrame.minY + margin
        let top = visibleFrame.maxY - panelSize.height - margin

        return switch self {
        case .center:
            CGPoint(
                x: visibleFrame.midX - panelSize.width / 2,
                y: visibleFrame.midY - panelSize.height / 2
            )
        case .topLeading:
            CGPoint(x: leading, y: top)
        case .topTrailing:
            CGPoint(x: trailing, y: top)
        case .bottomLeading:
            CGPoint(x: leading, y: bottom)
        case .bottomTrailing:
            CGPoint(x: trailing, y: bottom)
        }
    }
}

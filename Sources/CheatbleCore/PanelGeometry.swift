import Foundation
import CoreGraphics

public enum PanelGeometry {
    public static func frame(in visibleFrame: CGRect, requestedSize: CGSize, origin: CGPoint? = nil, margin: CGFloat = 16) -> CGRect {
        let marginX = min(margin, max(0, visibleFrame.width / 4))
        let marginY = min(margin, max(0, visibleFrame.height / 4))
        let width = min(max(240, requestedSize.width), max(1, visibleFrame.width - marginX * 2))
        let height = min(max(320, requestedSize.height), max(1, visibleFrame.height - marginY * 2))
        if let origin {
            return CGRect(x: min(max(origin.x, visibleFrame.minX), visibleFrame.maxX - width),
                          y: min(max(origin.y, visibleFrame.minY), visibleFrame.maxY - height), width: width, height: height)
        }
        return CGRect(x: visibleFrame.maxX - marginX - width,
                      y: visibleFrame.maxY - marginY - height, width: width, height: height)
    }
    public static func columnCount(for width: CGFloat) -> Int {
        guard width.isFinite else { return 1 }
        return max(1, min(3, Int((max(0, width - 24) + 12) / 292)))
    }

    public static func screenIndex(for window: CGRect?, screens: [CGRect], fallback: Int = 0) -> Int? {
        guard !screens.isEmpty else { return nil }
        let fallbackIndex = screens.indices.contains(fallback) ? fallback : 0
        guard let window, !window.isEmpty else { return fallbackIndex }
        let areas = screens.map { screen -> CGFloat in
            let intersection = screen.intersection(window)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        guard let maximum = areas.max(), maximum > 0 else { return fallbackIndex }
        // Preserve the current monitor on exact ties.
        if areas[fallbackIndex] == maximum { return fallbackIndex }
        return areas.firstIndex(of: maximum)
    }

    /// Accessibility coordinates are top-left based on the primary display.
    public static func fromAccessibility(_ frame: CGRect, primaryScreenTop: CGFloat) -> CGRect {
        CGRect(x: frame.minX, y: primaryScreenTop - frame.maxY, width: frame.width, height: frame.height)
    }
}

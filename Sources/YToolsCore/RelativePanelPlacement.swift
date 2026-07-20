/// A screen-independent top-left position measured within a display's usable area.
public struct RelativePanelPlacement: Equatable, Sendable {
    public let horizontalFraction: Double
    public let topFraction: Double
    public let sourceVisibleWidth: Double
    public let sourceVisibleHeight: Double

    public init?(
        horizontalFraction: Double,
        topFraction: Double,
        sourceVisibleWidth: Double,
        sourceVisibleHeight: Double
    ) {
        guard horizontalFraction.isFinite,
              topFraction.isFinite,
              (0...1).contains(horizontalFraction),
              (0...1).contains(topFraction),
              sourceVisibleWidth.isFinite,
              sourceVisibleHeight.isFinite,
              sourceVisibleWidth > 0,
              sourceVisibleHeight > 0 else { return nil }
        self.horizontalFraction = horizontalFraction
        self.topFraction = topFraction
        self.sourceVisibleWidth = sourceVisibleWidth
        self.sourceVisibleHeight = sourceVisibleHeight
    }

    public init?(
        left: Double,
        top: Double,
        visibleOriginX: Double,
        visibleOriginY: Double,
        visibleWidth: Double,
        visibleHeight: Double
    ) {
        guard left.isFinite,
              top.isFinite,
              visibleOriginX.isFinite,
              visibleOriginY.isFinite,
              visibleWidth.isFinite,
              visibleHeight.isFinite,
              visibleWidth > 0,
              visibleHeight > 0 else { return nil }
        let maximumY = visibleOriginY + visibleHeight
        horizontalFraction = min(
            max((left - visibleOriginX) / visibleWidth, 0),
            1
        )
        topFraction = min(max((maximumY - top) / visibleHeight, 0), 1)
        sourceVisibleWidth = visibleWidth
        sourceVisibleHeight = visibleHeight
    }

    public func resolvedLeft(visibleOriginX: Double, visibleWidth: Double) -> Double {
        visibleOriginX + visibleWidth * horizontalFraction
    }

    public func resolvedTop(visibleOriginY: Double, visibleHeight: Double) -> Double {
        visibleOriginY + visibleHeight * (1 - topFraction)
    }
}

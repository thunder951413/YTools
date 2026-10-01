namespace YTools.Core;

/// <summary>
/// A screen-independent top-left position measured within a display's usable
/// area. Fractions use a top-down axis to mirror the macOS port.
/// </summary>
public readonly record struct RelativePanelPlacement(
    double HorizontalFraction,
    double TopFraction,
    double SourceVisibleWidth,
    double SourceVisibleHeight)
{
    public static RelativePanelPlacement? Create(
        double horizontalFraction,
        double topFraction,
        double sourceVisibleWidth,
        double sourceVisibleHeight)
    {
        if (!double.IsFinite(horizontalFraction)
            || !double.IsFinite(topFraction)
            || horizontalFraction is < 0 or > 1
            || topFraction is < 0 or > 1
            || !double.IsFinite(sourceVisibleWidth)
            || !double.IsFinite(sourceVisibleHeight)
            || sourceVisibleWidth <= 0
            || sourceVisibleHeight <= 0)
        {
            return null;
        }

        return new RelativePanelPlacement(
            horizontalFraction,
            topFraction,
            sourceVisibleWidth,
            sourceVisibleHeight);
    }

    public static RelativePanelPlacement? Create(
        double left,
        double top,
        double visibleOriginX,
        double visibleOriginY,
        double visibleWidth,
        double visibleHeight)
    {
        if (!double.IsFinite(left)
            || !double.IsFinite(top)
            || !double.IsFinite(visibleOriginX)
            || !double.IsFinite(visibleOriginY)
            || !double.IsFinite(visibleWidth)
            || !double.IsFinite(visibleHeight)
            || visibleWidth <= 0
            || visibleHeight <= 0)
        {
            return null;
        }

        var maximumY = visibleOriginY + visibleHeight;
        var horizontalFraction = Math.Clamp((left - visibleOriginX) / visibleWidth, 0, 1);
        var topFraction = Math.Clamp((maximumY - top) / visibleHeight, 0, 1);
        return new RelativePanelPlacement(
            horizontalFraction,
            topFraction,
            visibleWidth,
            visibleHeight);
    }

    public double ResolvedLeft(double visibleOriginX, double visibleWidth)
    {
        return visibleOriginX + visibleWidth * HorizontalFraction;
    }

    public double ResolvedTop(double visibleOriginY, double visibleHeight)
    {
        return visibleOriginY + visibleHeight * (1 - TopFraction);
    }
}

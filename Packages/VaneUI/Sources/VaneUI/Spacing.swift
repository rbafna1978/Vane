import CoreGraphics

/// The spacing scale.
///
/// Everything vertical in the app lands on one of these. It exists because the first build of
/// the main screen used 10, 14, 16, 18, 22, 26, 48 and 214 point gaps chosen one at a time,
/// which is what "arbitrary" looks like from ten feet away even when each number seemed fine
/// while it was being typed.
///
/// Four tiers, not eight: hairline separation, related items, a group, a section. A scale with a
/// step for every occasion is the same as no scale.
public nonisolated enum Space {
    /// Between a label and the thing it labels.
    public static let tight: CGFloat = 4
    /// Between related lines in the same block.
    public static let close: CGFloat = 8
    /// Between blocks inside one group.
    public static let block: CGFloat = 16
    /// Between groups.
    public static let group: CGFloat = 24
    /// Between sections of the surface.
    public static let section: CGFloat = 40

    /// The horizontal text margin. The chart's plot area starts here too — a chart inset to a
    /// different margin than the text above it is the cheapest way to make a layout look
    /// assembled rather than designed.
    public static let margin: CGFloat = 24
}

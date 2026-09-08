import SwiftUI

/// A figure that rolls when it changes rather than teleporting.
///
/// Gate (find-animation-opportunities): purpose is *preventing a jarring change* — a refreshed
/// temperature swapping instantly reads as a glitch rather than as new information. Frequency
/// is occasional (a data refresh, not a tap), so it is eligible. 280ms, inside the 300ms UI
/// budget.
///
/// `.contentTransition(.numericText(value:))` is the native mechanism: it interpolates digit
/// glyphs inside the text renderer, so it is one draw call rather than a stack of overlapping
/// views, and it respects the font's own metrics.
public struct RollingNumber: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @Environment(\.dynamicTypeSize) private var typeSize

    private let value: Double
    private let format: FloatingPointFormatStyle<Double>
    private let unit: String?

    public init(
        _ value: Double,
        format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0)),
        unit: String? = nil
    ) {
        self.value = value
        self.format = format
        self.unit = unit
    }

    /// The figure and its unit, as one text run.
    ///
    /// The degree ring was an adjacent `Text` in an `HStack` for two attempts and detached both
    /// times: `.top` aligns to the *ascender*, which on a 148pt condensed face sits far above
    /// the cap line, and `baselineOffset` inside a stack moves the run's own baseline so the
    /// stack re-aligns around it. Concatenating the runs makes it one layout, where the
    /// baseline is shared by construction and the offset means what it says.
    ///
    /// Both numbers are fractions of the reading size rather than constants, so the ring holds
    /// its position as the clamped Dynamic Type curve grows the figure. 0.58 puts the ring's
    /// top on the numeral's cap line for a face of this cap height; 0.19 is the ring size that
    /// reads as a unit rather than as a footnote marker.
    private var composed: Text {
        let size = VaneType.reading(for: typeSize)
        var text = Text(value, format: format).monospacedDigit()
        if let unit {
            text = text + Text(unit)
                .font(.custom(VaneFont.display, fixedSize: size * 0.19))
                .baselineOffset(size * 0.58)
        }
        return text
    }

    public var body: some View {
        composed
            .vaneReadingType()
            // Tabular figures are applied to the numeric run above, not here, so the unit is
            // not forced onto a digit-width advance.
            .contentTransition(reduceMotion ? .opacity : .numericText(value: value))
            // The reduced path is designed, not disabled. `.opacity` crossfades the digits;
            // `.identity` would hard-swap them, which is *less* motion than asked for and reads
            // as a glitch — reduced motion means gentler, never absent.
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : VaneMotion.figure, value: value)
    }
}

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

    private let value: Double
    private let format: FloatingPointFormatStyle<Double>
    private let font: Font

    public init(
        _ value: Double,
        format: FloatingPointFormatStyle<Double> = .number.precision(.fractionLength(0)),
        font: Font = .vaneReading
    ) {
        self.value = value
        self.format = format
        self.font = font
    }

    public var body: some View {
        Text(value, format: format)
            .font(font)
            // Tabular figures: without them the glyph widths change as digits change and the
            // whole line shifts sideways while it rolls.
            .monospacedDigit()
            .contentTransition(reduceMotion ? .opacity : .numericText(value: value))
            // The reduced path is designed, not disabled. `.opacity` crossfades the digits;
            // `.identity` would hard-swap them, which is *less* motion than asked for and reads
            // as a glitch — reduced motion means gentler, never absent.
            .animation(reduceMotion ? .easeInOut(duration: 0.2) : VaneMotion.figure, value: value)
    }
}

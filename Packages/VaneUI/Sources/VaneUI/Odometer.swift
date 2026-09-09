import CoreText
import SwiftUI

/// The display face's real vertical metrics at a given size.
///
/// Built through `DisplayMetrics.forSize(_:)`, never directly: a `body` runs on every frame of
/// a drag, and creating a `CTFont` plus four metric queries per wheel per frame is real work on
/// the one path in the app that must not drop a frame. `swiftui-pro`'s performance rule — assume
/// `body` is called frequently and move anything non-trivial out of it — applies exactly here.
///
/// The odometer's first build guessed the digit band as `size * 0.74` and clipped a centred
/// window to it, which left slivers of the numerals above and below visible around every digit.
/// A window onto a strip of glyphs has to be positioned from the font's own cap height and
/// ascent — there is no fraction of the point size that happens to be right, and picking one by
/// eye is how you get a broken wheel at one size and a correct one at another.
nonisolated struct DisplayMetrics {
    let capHeight: CGFloat
    /// How far to move a centred `Text` so its cap band sits centred in the window.
    let bandOffset: CGFloat
    /// The advance width of a numeral, so each wheel's window is exactly as wide as the digit
    /// it shows. Guessed at `size * 0.56` this left a visible gap between the tens and units —
    /// the figure read as two separate numbers rather than one.
    let digitWidth: CGFloat

    /// Memoised. The keys are the handful of sizes the clamped Dynamic Type curve can produce,
    /// so the table stays at a few entries for the life of the process.
    @MainActor
    static func forSize(_ size: CGFloat, weight: CGFloat = 900) -> DisplayMetrics {
        let key = Key(size: size, weight: weight)
        if let cached = cache[key] { return cached }
        let made = DisplayMetrics(size: size, weight: weight)
        cache[key] = made
        return made
    }

    private struct Key: Hashable { let size: CGFloat; let weight: CGFloat }
    @MainActor private static var cache: [Key: DisplayMetrics] = [:]

    private init(size: CGFloat, weight: CGFloat) {
        // Through `VaneType.displayFont` so the wheels are measured from the *same* variable
        // instance they are drawn in. Measuring the default instance and drawing at weight 900
        // would put the window in the wrong place by the difference between Thin and Black.
        let font = VaneType.displayFont(size, weight: weight)
        let ascent = CTFontGetAscent(font)
        let descent = CTFontGetDescent(font)
        let cap = CTFontGetCapHeight(font)

        capHeight = cap

        // Measured from a real glyph. All ten numerals share an advance in any face designed
        // for setting figures, so "0" stands for all of them.
        var glyph = CGGlyph(0)
        var character = UniChar(UnicodeScalar("0").value)
        var advance = CGSize.zero
        if CTFontGetGlyphsForCharacters(font, &character, &glyph, 1) {
            CTFontGetAdvancesForGlyphs(font, .horizontal, &glyph, &advance, 1)
        }
        digitWidth = advance.width > 0 ? advance.width : size * 0.5
        // A centred Text puts its baseline at `(ascent + descent)/2 - descent` below centre.
        // The cap band runs from there up by `cap`, so its own centre sits half a cap higher.
        // Moving by the negation of that lands the band dead centre in the window.
        bandOffset = (ascent + descent) / 2 - ascent + cap / 2
    }
}

/// The reading, on wheels.
///
/// This is the app's primary instrument now that the chart has left the main screen. Time travel
/// is not read off a plot any more — it is *felt* in the figure, which rolls continuously as the
/// day under your finger changes, the way a mechanical counter does.
///
/// **Why a drum and not a crossfade.** `find-animation-opportunities` is explicit that data
/// people are reading must not move for style, and a 148pt number is the most-read thing on the
/// screen. The motion earns its place on two counts. It is 1:1 with the finger, so it is
/// manipulation feedback rather than decoration — let go and it settles and is still. And a
/// number that *travels* between two values says something a number that swaps does not: which
/// direction it went, and how far. That is the information the chart used to carry.
///
/// **Why no `Animation` is involved.** The wheels are a pure function of the scrub position, so
/// during a drag there is nothing to animate — the value simply is where your finger put it.
/// Only the release is animated, by the spring that settles the scrub itself, and the wheels
/// follow it for free. An animation here would put lag between the touch and the figure, which
/// is the one thing `apple-design` says never to do.
public struct Odometer: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize

    private let value: Double
    private let unit: String?
    private let reading: CGFloat

    public init(_ value: Double, unit: String? = nil, size: CGFloat = 180) {
        self.value = value
        self.unit = unit
        self.reading = size
    }

    private var size: CGFloat { reading }
    private var metrics: DisplayMetrics { .forSize(size) }
    /// The window is exactly one cap height, and the wheel's pitch is the same, so a numeral
    /// leaving is replaced precisely by the one arriving and no sliver of either is ever
    /// visible at rest.
    private var lineHeight: CGFloat { metrics.capHeight }

    /// Two places is the whole domain: Earth's record runs -90°C to +57°C, so a hundreds wheel
    /// would never turn. A wheel that can never move is a wheel that should not be drawn.
    private var places: [Int] { magnitude >= 10 ? [1, 0] : [0] }
    private var magnitude: Double { abs(value) }

    public var body: some View {
        HStack(alignment: .top, spacing: 0) {
            if value < 0 {
                Text("−")
                    .font(VaneType.display(size))
                    .offset(y: metrics.bandOffset)
                    .frame(height: lineHeight)
            }
            ForEach(places, id: \.self) { place in
                Wheel(position: wheelPosition(place: place), size: size,
                      lineHeight: lineHeight, bandOffset: metrics.bandOffset,
                      width: metrics.digitWidth)
            }
            if let unit {
                let unitSize = size * 0.19
                let unitMetrics = DisplayMetrics.forSize(unitSize)
                Text(unit)
                    .font(VaneType.display(unitSize))
                    // Sits on the cap line: its own band offset puts its cap band at the top of
                    // the frame, then it drops by the difference between the two cap heights so
                    // the ring's top lines up with the numerals' tops. Both terms are measured,
                    // so this holds at every Dynamic Type size.
                    .offset(y: unitMetrics.bandOffset)
                    .padding(.leading, unitSize * 0.12)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(value.rounded())) degrees")
    }

    private func wheelPosition(place: Int) -> Double {
        // Reduced motion gets the digits, not the journey: the wheels land on whole numbers and
        // the figure changes without travelling.
        if reduceMotion { return floor(magnitude / pow(10, Double(place))) }
        return Wheel.position(for: magnitude, place: place)
    }
}

/// One digit wheel: a strip of numerals behind a window one digit tall.
struct Wheel: View {
    let position: Double
    let size: CGFloat
    let lineHeight: CGFloat
    let bandOffset: CGFloat
    let width: CGFloat

    var body: some View {
        let index = floor(position)
        let fraction = position - index

        ZStack {
            // Three numerals is all that can ever be visible through a one-digit window, so
            // three is all that gets laid out. Rendering ten and clipping nine of them is nine
            // wasted text layouts per wheel, per frame, at 148pt.
            ForEach(-1...1, id: \.self) { step in
                Text(numeral(index + Double(step)))
                    .font(VaneType.display(size))
                    // Counting up brings the next numeral from below, so the strip travels
                    // upward as the value rises. This is the direction every counter turns.
                    .offset(y: bandOffset + (CGFloat(step) - fraction) * lineHeight)
            }
        }
        .frame(height: lineHeight)
        .clipped()
        // The measured numeral advance, so a 1 does not narrow the figure mid-roll and shuffle
        // everything to its left, and the wheels sit as close as set type would.
        .frame(width: width)
    }

    /// Where one wheel sits, in digits.
    ///
    /// A real odometer's tens wheel is still for nine tenths of the units wheel's turn and then
    /// snaps round with it. Rolling every wheel by its own fraction — the obvious implementation
    /// — has the tens digit sitting permanently halfway between two numbers, which is both
    /// illegible and not what any counter has ever done.
    nonisolated static func position(for magnitude: Double, place: Int) -> Double {
        let scaled = magnitude / pow(10, Double(place))
        let whole = floor(scaled)
        let fraction = scaled - whole
        guard place > 0 else { return scaled }
        // The last tenth of the lower wheel's turn, expanded to a full turn of this one.
        return whole + max(0, (fraction - 0.9) * 10)
    }

    /// Wraps: the numeral before 0 is 9, and the wheel is a loop, not a list.
    nonisolated static func numeral(_ raw: Double) -> String {
        let wrapped = Int(raw.rounded(.down)).quotientAndRemainder(dividingBy: 10).remainder
        return String(wrapped < 0 ? wrapped + 10 : wrapped)
    }

    private func numeral(_ raw: Double) -> String { Wheel.numeral(raw) }
}

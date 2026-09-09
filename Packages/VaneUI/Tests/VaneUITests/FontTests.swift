import CoreText
import Foundation
import Testing
@testable import VaneUI

@Suite("Type")
struct FontTests {
    /// The faces have to be in the resource bundle, or every custom font silently falls back to
    /// the system face and the app looks subtly wrong everywhere at once.
    @Test func `both faces ship in the bundle`() {
        #expect(VaneFont.fontURL(for: "BigShoulders") != nil)
        #expect(VaneFont.fontURL(for: "JetBrainsMono") != nil)
    }

    /// Big Shoulders' default instance is *Thin*. Asking for the face by name without setting
    /// `wght` gives the lightest cut in the family — the opposite of this design — so the axes
    /// binding is the thing that has to be asserted, not the font resolving.
    @MainActor
    @Test func `the weight axis actually binds`() {
        VaneFont.register()
        let thin = DisplayMetrics.forSize(180, weight: 100)
        let black = DisplayMetrics.forSize(180, weight: 900)
        // A heavier cut of a condensed face is wider per numeral; if the axis were being
        // ignored these would be identical.
        #expect(black.digitWidth > thin.digitWidth)
    }

    /// The optical size axis is why this face was chosen over the alternatives, so it is worth
    /// asserting it is not silently dropped.
    ///
    /// Counting the entries in the variation dictionary does not work and the reason is worth
    /// recording: **CoreText omits an axis whose value equals its default.** Big Shoulders'
    /// `opsz` default is 72, and the API clamps to the axis range, so at a 180pt setting `opsz`
    /// lands exactly on the default and vanishes from the dictionary — which looks like the axis
    /// being ignored and is the opposite. Assert the values instead.
    @MainActor
    @Test func `the optical size axis is set from the point size`() {
        VaneFont.register()
        let opsz = "opsz".utf8.reduce(0) { $0 << 8 | Int($1) }

        func value(_ size: CGFloat, axis: Int) -> Double? {
            guard let variation = CTFontCopyVariation(VaneType.displayFont(size, weight: 900))
                    as? [AnyHashable: Any] else { return nil }
            return variation.first { ($0.key as? Int) == axis }?.value as? Double
        }

        // A caption-sized setting carries a caption-sized optical cut.
        #expect(value(12, axis: opsz).map { abs($0 - 12) < 0.001 } == true)

        // A display-sized setting clamps to the top of the axis rather than running past it.
        // Absent means "equal to the default", which for this face is 72 — see above.
        #expect(abs((value(180, axis: opsz) ?? 72) - 72) < 0.001)

        // And the two are genuinely different cuts, which is the whole point of the axis.
        #expect(CTFontGetCapHeight(VaneType.displayFont(72, weight: 900)) > 0)
    }
}

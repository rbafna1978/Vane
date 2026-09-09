import CoreText
import Foundation
import SwiftUI

/// The type system.
///
/// Big Shoulders carries the identity, SF Pro Text carries running text, JetBrains Mono carries
/// data. SF for body is deliberate rather than lazy: Dynamic Type and VoiceOver come free with
/// it, and no licensed face gives those.
///
/// `nonisolated`: these are constants, CoreText registration is thread-safe, and the widget
/// extension has to register the same faces without touching the main actor.
public nonisolated enum VaneFont {
    /// The variable font's default instance name. Big Shoulders ships as a single file carrying
    /// `wght` 100-900 and `opsz` 10-72, and its default instance happens to be Thin — so asking
    /// for this name *without* setting the axes gives you the lightest cut in the family, which
    /// is the opposite of what this design wants. Always go through `VaneType.display(_:_:)`.
    public static let display = "BigShoulders-Thin"
    public static let mono = "JetBrainsMono-Regular"

    /// SPM resource bundles are not scanned for fonts the way an app's Info.plist is, so the
    /// faces have to be registered by hand before first use. Idempotent — registering twice is
    /// an error CoreText reports and we ignore, which is simpler than tracking state.
    public static func register() {
        for name in ["BigShoulders", "JetBrainsMono"] {
            guard let url = Bundle.module.url(forResource: name, withExtension: "ttf") else {
                continue
            }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Internal rather than private so a test can assert the files are actually in the bundle.
    static func fontURL(for file: String) -> URL? {
        Bundle.module.url(forResource: file, withExtension: "ttf")
    }
}

public nonisolated enum VaneType {
    /// Big Shoulders at an explicit weight and optical size.
    ///
    /// **Why not `.custom(_:size:)` plus `.fontWeight()`.** SwiftUI's weight modifier does not
    /// reliably drive a custom variable face's `wght` axis, and it cannot address `opsz` at all.
    /// Setting both on the font descriptor is the only way to get the family's real range — and
    /// `opsz` is the reason this face was chosen, so leaving it unset would throw away the
    /// deciding property.
    ///
    /// - Parameters:
    ///   - weight: 100-900. The figure runs at 900; labels sit lower.
    ///   - opticalSize: 10-72. **Set this to the point size the type is actually set at**, not to
    ///     a constant. That is what an optical size axis is for: a face cut for 12pt has open
    ///     apertures and loose spacing that look clumsy at 180pt, and a face cut for 180pt closes
    ///     up and tightens until it is unreadable small. Clamped to the axis range.
    public static func display(_ size: CGFloat, weight: CGFloat = 900) -> Font {
        Font(displayFont(size, weight: weight))
    }

    /// The `CTFont` behind `display(_:weight:)`, for callers that need real metrics — the
    /// odometer measures cap height and numeral advance off this.
    public static func displayFont(_ size: CGFloat, weight: CGFloat = 900) -> CTFont {
        let descriptor = CTFontDescriptorCreateWithAttributes([
            kCTFontNameAttribute: VaneFont.display,
            kCTFontVariationAttribute: [
                axis("wght"): min(max(weight, 100), 900),
                axis("opsz"): min(max(size, 10), 72),
            ],
        ] as CFDictionary)
        return CTFontCreateWithFontDescriptor(descriptor, size, nil)
    }

    /// Four-character axis tags are keyed by CoreText as big-endian 32-bit integers.
    private static func axis(_ tag: String) -> Int {
        tag.utf8.reduce(0) { $0 << 8 | Int($1) }
    }
}

public extension Font {
    /// Body and caption scale with Dynamic Type without a ceiling, because that is what they are
    /// for. The display sizes are set explicitly per use and clamped where they have to be.
    static let vaneBody = Font.system(.body)
    static let vaneCaption = Font.system(.footnote)
    static let vaneData = Font.custom(VaneFont.mono, size: 12, relativeTo: .caption2)
}

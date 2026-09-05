import CoreText
import Foundation
import SwiftUI

/// The type scale.
///
/// Archivo Narrow carries the identity, SF Pro Text carries the running text, JetBrains Mono
/// carries the data. SF for body is deliberate rather than lazy: Dynamic Type and VoiceOver
/// come free with it, and no licensed face gives those.
/// `nonisolated`: these are constants, CoreText registration is thread-safe, and the widget
/// extension has to register the same faces without touching the main actor.
public nonisolated enum VaneFont {
    public static let display = "ArchivoNarrow-Regular"
    public static let mono = "JetBrainsMono-Regular"

    /// SPM resource bundles are not scanned for fonts the way an app's Info.plist is, so the
    /// faces have to be registered by hand before first use. Idempotent — registering twice
    /// is an error CoreText reports and we ignore, which is simpler than tracking state.
    public static func register() {
        for name in [display, mono] {
            guard let url = fontURL(for: name) else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// Internal rather than private so a test can assert the files are actually in the bundle.
    /// `Bundle.module` resolves to VaneUI's own resources here; from a test target it would
    /// resolve to the test bundle and find nothing.
    static func fontURL(for postScriptName: String) -> URL? {
        Bundle.module.url(
            forResource: postScriptName == display ? "ArchivoNarrow" : "JetBrainsMono",
            withExtension: "ttf"
        )
    }
}

public extension Font {
    /// The temperature. The one number the whole screen is built around.
    /// Not Dynamic Type scaled by default — see `VaneType.reading(for:)`.
    static let vaneReading = Font.custom(VaneFont.display, fixedSize: 148)
    static let vaneDisplayLarge = Font.custom(VaneFont.display, fixedSize: 40)
    /// The context line: the sentence that is the reason this app exists.
    static let vaneContext = Font.custom(VaneFont.display, fixedSize: 28)
    static let vaneBody = Font.system(size: 17)
    static let vaneCaption = Font.system(size: 13)
    static let vaneData = Font.custom(VaneFont.mono, fixedSize: 12)
}

public nonisolated enum VaneType {
    /// Line heights, as multipliers SwiftUI can apply through `.lineSpacing`.
    /// Reading 148/132 is intentionally tighter than 1.0 — at that size the default leading
    /// leaves a gap the layout cannot absorb.
    public static let readingSize: CGFloat = 148
    public static let contextSize: CGFloat = 28

    /// Display type on a clamped curve rather than the full Dynamic Type range.
    ///
    /// Body and caption scale all the way to the accessibility sizes, because that is what
    /// they are for. A 148pt number scaled by the AX5 multiplier is roughly 380pt and there is
    /// no layout that survives it — so the reading and context sizes grow, but by less, and
    /// stop. This is the designed compromise, not a refusal to scale.
    public static func reading(for category: ContentSizeCategory) -> CGFloat {
        readingSize * clampedMultiplier(category, ceiling: 1.30)
    }

    public static func context(for category: ContentSizeCategory) -> CGFloat {
        contextSize * clampedMultiplier(category, ceiling: 1.55)
    }

    static func clampedMultiplier(_ category: ContentSizeCategory, ceiling: Double) -> CGFloat {
        let raw: Double = switch category {
        case .extraSmall: 0.90
        case .small: 0.94
        case .medium: 0.97
        case .large: 1.00
        case .extraLarge: 1.06
        case .extraExtraLarge: 1.12
        case .extraExtraExtraLarge: 1.18
        case .accessibilityMedium: 1.30
        case .accessibilityLarge: 1.45
        case .accessibilityExtraLarge: 1.60
        case .accessibilityExtraExtraLarge: 1.75
        case .accessibilityExtraExtraExtraLarge: 1.90
        @unknown default: 1.00
        }
        return CGFloat(min(raw, ceiling))
    }
}

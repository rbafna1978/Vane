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
    /// Everything below scales with Dynamic Type.
    ///
    /// `fixedSize:` and `Font.system(size:)` both opt *out* of scaling — using them is how a
    /// design system ends up with accessibility settings that do nothing at all. `relativeTo:`
    /// is what ties a custom face to the user's chosen size.
    static let vaneDisplayLarge = Font.custom(VaneFont.display, size: 40, relativeTo: .largeTitle)
    static let vaneBody = Font.system(.body)          // 17pt at Large, scales to AX5
    static let vaneCaption = Font.system(.footnote)   // 13pt at Large, scales to AX5
    static let vaneData = Font.custom(VaneFont.mono, size: 12, relativeTo: .caption2)
}

/// The reading and the context line scale on a *clamped* curve rather than the full range.
///
/// A 148pt number multiplied by the AX5 factor is roughly 380pt and no layout survives it. So
/// they grow, by less, and stop — which is a designed compromise, not a refusal to scale. Body
/// and caption above are unrestricted, because that is what they are for.
public extension View {
    func vaneReadingType() -> some View { modifier(ClampedType(role: .reading)) }
    func vaneContextType() -> some View { modifier(ClampedType(role: .context)) }
}

struct ClampedType: ViewModifier {
    enum Role { case reading, context }
    @Environment(\.dynamicTypeSize) private var size
    let role: Role

    func body(content: Content) -> some View {
        content.font(.custom(VaneFont.display, fixedSize: pointSize))
    }

    private var pointSize: CGFloat {
        switch role {
        case .reading: VaneType.reading(for: size)
        case .context: VaneType.context(for: size)
        }
    }
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
    public static func reading(for size: DynamicTypeSize) -> CGFloat {
        readingSize * clampedMultiplier(size, ceiling: 1.30)
    }

    public static func context(for size: DynamicTypeSize) -> CGFloat {
        contextSize * clampedMultiplier(size, ceiling: 1.55)
    }

    static func clampedMultiplier(_ size: DynamicTypeSize, ceiling: Double) -> CGFloat {
        let raw: Double = switch size {
        case .xSmall: 0.90
        case .small: 0.94
        case .medium: 0.97
        case .large: 1.00
        case .xLarge: 1.06
        case .xxLarge: 1.12
        case .xxxLarge: 1.18
        case .accessibility1: 1.30
        case .accessibility2: 1.45
        case .accessibility3: 1.60
        case .accessibility4: 1.75
        case .accessibility5: 1.90
        @unknown default: 1.00
        }
        return CGFloat(min(raw, ceiling))
    }
}

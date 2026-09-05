import SwiftUI
import VaneKit

/// The sentence that is the reason this app exists, and the screen's one orchestrated moment.
///
/// Gate: purpose is *preventing a jarring change*. The line genuinely appears out of nothing —
/// a cold cell has no context, and one materialises when the backfill lands. Frequency is rare
/// (once per location, then only when the day's story changes), which is where the delight
/// budget is allowed to be spent.
///
/// It rises 6pt and fades. It does not scale, blur, or animate per-glyph: this is a printed
/// instrument, and the sentence is something to read, not something to watch.
public struct ContextLine: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let context: WeatherContext?
    private let palette: Palette

    public init(_ context: WeatherContext?, palette: Palette) {
        self.context = context
        self.palette = palette
    }

    public var body: some View {
        ZStack(alignment: .leading) {
            if let context {
                Text(context.headline)
                    .vaneContextType()
                    .foregroundStyle(palette.inkColor)
                    // Low confidence means a short record. It still shows, quieter, rather
                    // than claiming the same authority as thirty years of data.
                    .opacity(context.confidence == .low ? 0.62 : 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(transition)
                    .accessibilityLabel(context.headline)
                    .id(context.headline)
            }
        }
        .animation(reduceMotion ? .easeInOut(duration: 0.25) : VaneMotion.entrance, value: context)
    }

    private var transition: AnyTransition {
        // Reduced motion keeps the fade and drops the travel. Removing the transition entirely
        // would make the sentence teleport, which is the jarring change we started with.
        reduceMotion
            ? .opacity
            : .asymmetric(
                insertion: .offset(y: 6).combined(with: .opacity),
                removal: .opacity
            )
    }
}

import SwiftUI

/// The roll of chart paper under a finger.
///
/// Gate: purpose is *spatial consistency*. The signature of this design is that the trace never
/// breaks — today is the right-hand end of one continuous roll, and dragging left moves along
/// the same paper into the archive. A drag that snapped to positions would break the illusion
/// that there is one physical sheet.
///
/// Everything here is interruptible. A second drag landing mid-settle picks up the paper where
/// it currently is and carries the existing velocity, because paper does not restart from zero
/// when you touch it again.
public struct PaperScroll<Content: View>: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var settled: CGFloat = 0
    @State private var live: CGFloat = 0

    private let contentWidth: CGFloat
    private let viewportWidth: CGFloat
    private let content: (CGFloat) -> Content

    /// - Parameter content: receives the current offset so the caller can draw only the
    ///   portion of the roll that is on screen.
    public init(
        contentWidth: CGFloat,
        viewportWidth: CGFloat,
        @ViewBuilder content: @escaping (CGFloat) -> Content
    ) {
        self.contentWidth = contentWidth
        self.viewportWidth = viewportWidth
        self.content = content
    }

    private var minOffset: CGFloat { min(0, viewportWidth - contentWidth) }

    public var body: some View {
        content(offset)
            .contentShape(.rect)
            .gesture(drag)
    }

    private var offset: CGFloat { rubberBanded(settled + live) }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 1)
            .onChanged { value in
                // No animation on the tracking path. The paper must sit exactly under the
                // finger; animating here adds lag between the touch and the content, which is
                // the difference between dragging paper and dragging a video of paper.
                live = value.translation.width
            }
            .onEnded { value in
                // Hand the finger's velocity to the spring rather than starting from rest.
                // `predictedEndTranslation` is UIKit's own projection of where the gesture was
                // heading, so momentum continues at the speed the finger was actually moving.
                let projected = settled + value.predictedEndTranslation.width
                live = 0
                settled = min(0, max(minOffset, projected))

                withAnimation(reduceMotion ? .easeOut(duration: 0.25) : VaneMotion.gesture) {
                    // Assigning inside the animation lets an interrupting drag retarget the
                    // spring instead of fighting it.
                    settled = min(0, max(minOffset, projected))
                }
            }
    }

    /// Resistance past the ends of the roll, using UIScrollView's own curve.
    ///
    /// `x * d * c / (d + c * x)` approaches `d * c` asymptotically, so the paper never quite
    /// stops moving and never runs away either — it just gets progressively harder to pull.
    /// A hard stop at the boundary reads as a bug; this reads as the end of the sheet.
    private func rubberBanded(_ raw: CGFloat) -> CGFloat {
        let c: CGFloat = 0.55
        let d = max(viewportWidth, 1)

        if raw > 0 {
            return (raw * d * c) / (d + c * raw)
        }
        if raw < minOffset {
            let past = minOffset - raw
            return minOffset - (past * d * c) / (d + c * past)
        }
        return raw
    }
}

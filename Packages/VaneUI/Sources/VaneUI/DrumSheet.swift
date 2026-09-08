import SwiftUI

/// The chart paper, as a sheet wrapped around a turning drum.
///
/// This replaces a flat rectangle that butt-joined the sky along a hairline, which read — as it
/// should have — as two coloured boxes stacked on top of each other. No amount of shadow fixes
/// that, because the problem was never the seam: it was that both regions were flat planes, and
/// two flat planes meeting at a straight line is a diagram, not a scene.
///
/// A barograph's paper is wrapped around a cylinder, and the three things that read as
/// *cylinder* rather than *rectangle* are all here:
///
/// 1. **The top edge is an arc.** Looking slightly down at a vertical drum, the circle at the
///    top projects to an ellipse, so the near edge of the sheet hangs lowest at the centre and
///    rises toward both sides. That single curve is what stops the eye reading a boundary and
///    starts it reading an object.
/// 2. **The surface is shaded across its width.** A cylinder is brightest where it faces you and
///    falls away at the turn. Without it, a curved top edge on a flat fill just looks like a
///    rectangle someone bent.
/// 3. **Skylight pools on it.** The sheet is lit by the sky above it, so the wash at its top is
///    tinted by the sky rather than being a neutral darkening.
struct DrumSheet: View {
    let palette: Palette

    /// How far the centre of the top edge hangs below the sides. Shallow on purpose: this is a
    /// wide drum seen nearly edge-on, and a deep curve reads as a bowl.
    private let sag: CGFloat = 16

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let shape = DrumTop(sag: sag)

            ZStack(alignment: .top) {
                shape.fill(palette.paperColor)

                // 2. Cylinder shading. Two symmetric gradients rather than one three-stop
                //    gradient, because the falloff is steeper at the turn than in the middle
                //    and a linear ramp across the whole width flattens exactly the part that
                //    carries the curve.
                shape
                    .fill(
                        LinearGradient(
                            stops: [
                                .init(color: palette.ink.color.opacity(0.055), location: 0),
                                .init(color: .clear, location: 0.26),
                                .init(color: .clear, location: 0.74),
                                .init(color: palette.ink.color.opacity(0.055), location: 1),
                            ],
                            startPoint: .leading, endPoint: .trailing
                        )
                    )
                    // Faded out down the sheet.
                    //
                    // Run at full strength for the whole scroll height it drew two dirty
                    // vertical bands the length of the document, darkening the ground behind
                    // every panel. The curvature is only legible near the drum's visible top
                    // edge anyway; below that there is no silhouette for it to explain, so it
                    // is doing nothing but costing contrast.
                    .mask {
                        LinearGradient(stops: [.init(color: .black, location: 0),
                                               .init(color: .black, location: 0.4),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 520)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }

                // 3. Skylight, pooling at the top of the sheet and gone within a third of a
                //    screen. Tinted by the sky's own horizon colour, so the sheet is lit by the
                //    weather above it rather than merely shaded.
                shape
                    .fill(
                        LinearGradient(
                            colors: [palette.paper.mixed(with: palette.ink, amount: 0.10).color,
                                     .clear],
                            startPoint: .top, endPoint: .bottom
                        )
                    )
                    // Masked to a fixed depth rather than gradient-stopped across the whole
                    // sheet, so the falloff length does not change with the scroll content's
                    // height — a wash that stretches to fit is a wash that disappears. The mask
                    // is itself a gradient: a hard-edged one left a visible horizontal seam
                    // partway down the page, which is the same defect this whole change set is
                    // trying to remove.
                    .mask(alignment: .top) {
                        LinearGradient(colors: [.black, .clear],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: 300)
                            .frame(maxHeight: .infinity, alignment: .top)
                    }

                // The edge of the sheet, catching the light. Not a divider — a lit edge, which
                // is why it is paper-side of the boundary and lighter than the paper, not a
                // grey rule sitting on top of it.
                shape.stroke(palette.paper.mixed(with: .init(hex: 0xFFFFFF), amount: 0.5).color,
                             lineWidth: 1)
                    .blendMode(.plusLighter)
                    .opacity(0.5)
            }
            .frame(width: width)
        }
        .ignoresSafeArea(edges: .bottom)
    }
}

/// A rectangle whose top edge sags at the centre — the near edge of a cylinder seen from
/// slightly above.
struct DrumTop: Shape {
    let sag: CGFloat

    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            // A single quadratic with the control point at twice the sag: a quadratic Bézier
            // reaches only half way to its control point at the midpoint, so 2×sag puts the
            // curve exactly `sag` below the corners where it is wanted.
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.minY + sag * 2)
            )
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

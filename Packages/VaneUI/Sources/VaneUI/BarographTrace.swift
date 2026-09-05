import SwiftUI

/// The chart. This is the app.
///
/// A barograph pen has only drawn as far as *now* — everything to the right of the pen tip has
/// not happened yet. So the recorded part of the day is a solid line and the forecast ahead of
/// it is a finer, lighter one, and the pen tip sits on the boundary. That distinction is free
/// honesty: the instrument cannot draw the future, and neither should we.
///
/// The normal is a band, not a line, because we hold daily history: the average high and the
/// average low for this calendar date. Where today's trace leaves the band is where today
/// stops being ordinary, readable without a sentence.
public struct BarographTrace: View {
    @Environment(\.dynamicTypeSize) private var typeSize

    public struct Point: Sendable, Hashable {
        public let hour: Double
        public let value: Double
        public init(hour: Double, value: Double) {
            self.hour = hour
            self.value = value
        }
    }

    private let points: [Point]
    private let normalHigh: Double?
    private let normalLow: Double?
    private let nowHour: Double
    private let palette: Palette

    public init(
        points: [Point],
        normalHigh: Double? = nil,
        normalLow: Double? = nil,
        nowHour: Double,
        palette: Palette
    ) {
        self.points = points
        self.normalHigh = normalHigh
        self.normalLow = normalLow
        self.nowHour = nowHour
        self.palette = palette
    }

    public var body: some View {
        Canvas { context, size in
            guard points.count > 1 else { return }

            let values = points.map(\.value) + [normalHigh, normalLow].compactMap { $0 }
            // Pad the range so the trace never touches the frame edge — a line grazing its own
            // bounds reads as clipped rather than as measured.
            let low = (values.min() ?? 0) - 2.5
            let high = (values.max() ?? 1) + 2.5
            let span = max(high - low, 0.001)

            let plot = CGRect(x: 0, y: 4, width: size.width, height: size.height - 22)
            func x(_ hour: Double) -> CGFloat { plot.minX + plot.width * hour / 24 }
            func y(_ value: Double) -> CGFloat {
                plot.maxY - plot.height * (value - low) / span
            }

            drawGrid(context, plot: plot, x: x)
            if let normalHigh, let normalLow {
                drawNormalBand(context, plot: plot, top: y(normalHigh), bottom: y(normalLow))
            }
            drawTrace(context, x: x, y: y)
            drawPenTip(context, x: x, y: y)
            drawHourLabels(context, plot: plot, size: size, x: x)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilitySummary)
    }

    // MARK: - Layers

    private func drawGrid(
        _ context: GraphicsContext, plot: CGRect, x: (Double) -> CGFloat
    ) {
        // Printed ruling: horizontals for value, a tick every three hours for time. Hairlines,
        // because on real chart paper the grid is underneath the reading, never competing.
        for row in 0...5 {
            let y = plot.minY + plot.height * CGFloat(row) / 5
            context.stroke(
                Path { $0.move(to: .init(x: plot.minX, y: y))
                       $0.addLine(to: .init(x: plot.maxX, y: y)) },
                with: .color(palette.gridColor), lineWidth: 0.5
            )
        }
        for hour in stride(from: 0.0, through: 24.0, by: 3) {
            context.stroke(
                Path { $0.move(to: .init(x: x(hour), y: plot.minY))
                       $0.addLine(to: .init(x: x(hour), y: plot.maxY)) },
                with: .color(palette.gridColor.opacity(0.55)), lineWidth: 0.5
            )
        }
    }

    private func drawNormalBand(
        _ context: GraphicsContext, plot: CGRect, top: CGFloat, bottom: CGFloat
    ) {
        context.fill(
            Path(CGRect(x: plot.minX, y: top, width: plot.width, height: bottom - top)),
            with: .color(palette.gridColor.opacity(0.28))
        )
        for edge in [top, bottom] {
            context.stroke(
                Path { $0.move(to: .init(x: plot.minX, y: edge))
                       $0.addLine(to: .init(x: plot.maxX, y: edge)) },
                with: .color(palette.gridColor),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }
    }

    private func drawTrace(
        _ context: GraphicsContext, x: (Double) -> CGFloat, y: (Double) -> CGFloat
    ) {
        let recorded = points.filter { $0.hour <= nowHour }
        let ahead = points.filter { $0.hour >= nowHour }

        if ahead.count > 1 {
            // The forecast: same pen, less pressure. Finer and lighter, so it reads as the same
            // line continuing rather than as a different measurement.
            context.stroke(
                path(ahead, x: x, y: y),
                with: .color(palette.traceColor.opacity(0.38)),
                style: StrokeStyle(lineWidth: 1.1, lineCap: .round, dash: [2.5, 3])
            )
        }
        if recorded.count > 1 {
            context.stroke(
                path(recorded, x: x, y: y),
                with: .color(palette.traceColor),
                style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func drawPenTip(
        _ context: GraphicsContext, x: (Double) -> CGFloat, y: (Double) -> CGFloat
    ) {
        guard let now = value(atHour: nowHour) else { return }
        let centre = CGPoint(x: x(nowHour), y: y(now))

        // A hairline dropped to the baseline: where the pen is touching the paper right now.
        context.stroke(
            Path { $0.move(to: centre); $0.addLine(to: .init(x: centre.x, y: y(now) + 400)) },
            with: .color(palette.traceColor.opacity(0.22)), lineWidth: 0.5
        )
        // Paper-coloured halo so the tip stays legible where it crosses the grid or the band.
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - 5, y: centre.y - 5, width: 10, height: 10)),
            with: .color(palette.paperColor)
        )
        context.fill(
            Path(ellipseIn: CGRect(x: centre.x - 3, y: centre.y - 3, width: 6, height: 6)),
            with: .color(palette.traceColor)
        )
    }

    private func drawHourLabels(
        _ context: GraphicsContext, plot: CGRect, size: CGSize, x: (Double) -> CGFloat
    ) {
        // The axis is a fixed width, so its labels cannot scale without colliding — at AX5 the
        // three-hourly labels overlap into unreadable pulp. Thin them to six-hourly and cap the
        // size instead. This is the designed accessibility path: fewer, larger, legible marks,
        // not the same marks made illegible.
        let step: Double = typeSize.isAccessibilitySize ? 6 : 3
        let pointSize: CGFloat = typeSize.isAccessibilitySize ? 15 : 12

        for hour in stride(from: 0.0, through: 24.0 - step, by: step) {
            let text = Text(String(format: "%02d", Int(hour)))
                .font(.custom(VaneFont.mono, fixedSize: pointSize))
                .foregroundStyle(palette.inkColor.opacity(0.45))
            // Centred on its own gridline, except the first, which would hang off the paper.
            let anchor: UnitPoint = hour == 0 ? .leading : .center
            context.draw(text, at: .init(x: x(hour), y: size.height - 7), anchor: anchor)
        }
    }

    // MARK: - Helpers

    private func path(
        _ points: [Point], x: (Double) -> CGFloat, y: (Double) -> CGFloat
    ) -> Path {
        Path { path in
            for (index, point) in points.enumerated() {
                let location = CGPoint(x: x(point.hour), y: y(point.value))
                index == 0 ? path.move(to: location) : path.addLine(to: location)
            }
        }
    }

    private func value(atHour hour: Double) -> Double? {
        points.min(by: { abs($0.hour - hour) < abs($1.hour - hour) })?.value
    }

    /// VoiceOver gets the shape as a sentence. The decorative layers — grid, band fill, pen
    /// halo — are never announced; they are paper, not content.
    private var accessibilitySummary: String {
        guard let now = value(atHour: nowHour),
              let high = points.map(\.value).max(),
              let low = points.map(\.value).min() else { return "Temperature chart" }
        var summary = "Today's temperature. Now \(Int(now.rounded())) degrees, "
        summary += "high \(Int(high.rounded())), low \(Int(low.rounded()))."
        if let normalHigh {
            summary += now > normalHigh ? " Above the usual range for this date."
                                        : " Within the usual range for this date."
        }
        return summary
    }
}

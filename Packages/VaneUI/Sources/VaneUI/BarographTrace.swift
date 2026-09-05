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
        public let precipMm: Double

        public init(hour: Double, value: Double, precipMm: Double = 0) {
            self.hour = hour
            self.value = value
            self.precipMm = precipMm
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

            // A gutter on the left for the value scale, and a row at the foot for rainfall.
            // Without the scale the trace is a shape with no magnitude — you can see that today
            // rose, but not to what.
            let gutter: CGFloat = typeSize.isAccessibilitySize ? 44 : 34
            let precipRow: CGFloat = hasPrecipitation ? 22 : 0
            let plot = CGRect(
                x: gutter, y: 4,
                width: size.width - gutter,
                height: size.height - 22 - precipRow
            )
            func x(_ hour: Double) -> CGFloat { plot.minX + plot.width * hour / 24 }
            func y(_ value: Double) -> CGFloat {
                plot.maxY - plot.height * (value - low) / span
            }

            let ticks = valueTicks(low: low, high: high)
            drawGrid(context, plot: plot, ticks: ticks, x: x, y: y)
            if let normalHigh, let normalLow {
                drawNormalBand(context, plot: plot, top: y(normalHigh), bottom: y(normalLow))
            }
            drawValueLabels(context, plot: plot, ticks: ticks, gutter: gutter, y: y)
            if hasPrecipitation {
                drawPrecipitation(context, plot: plot, size: size, x: x)
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
        _ context: GraphicsContext, plot: CGRect, ticks: [Double],
        x: (Double) -> CGFloat, y: (Double) -> CGFloat
    ) {
        // Ruling sits on the labelled values, not on arbitrary fractions of the height. A line
        // you cannot name is decoration; a line at 20 degrees is a measurement.
        for tick in ticks {
            context.stroke(
                Path { $0.move(to: .init(x: plot.minX, y: y(tick)))
                       $0.addLine(to: .init(x: plot.maxX, y: y(tick))) },
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
        // 0.28 over near-black paper is imperceptible, and "where today leaves the ordinary
        // range" is the chart's whole argument. The band is scaled against the paper it sits on
        // rather than fixed, so it stays a whisper on light stock and stays visible on dark.
        // A whisper of a fill, and the dashed edges do the work. A solid block reads as a
        // selection highlight — which is exactly how it was being read — rather than as a
        // printed reference zone. The edges are held to 3:1 (WCAG 1.4.11) because they are the
        // boundary the whole reading is made against.
        let strength = palette.paper.luminance < 0.2 ? 0.22 : 0.16
        context.fill(
            Path(CGRect(x: plot.minX, y: top, width: plot.width, height: bottom - top)),
            with: .color(palette.gridColor.opacity(strength))
        )
        for edge in [top, bottom] {
            context.stroke(
                Path { $0.move(to: .init(x: plot.minX, y: edge))
                       $0.addLine(to: .init(x: plot.maxX, y: edge)) },
                with: .color(palette.bandColor),
                style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }

        // And say what it is. An unlabelled shaded region is furniture; a labelled one is the
        // thirty-year answer the whole app is built to give.
        let caption = Text("30-YEAR NORMAL")
            .font(.custom(VaneFont.mono, fixedSize: typeSize.isAccessibilitySize ? 11 : 9))
            .foregroundStyle(palette.inkColor.opacity(0.5))
        context.draw(caption, at: .init(x: plot.maxX - 4, y: top + 9), anchor: .topTrailing)
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

    /// Round numbers, four or five of them.
    ///
    /// A scale labelled 13.4 / 17.8 / 22.2 is arithmetically correct and useless — nobody holds
    /// those. Step up through 1, 2, 5, 10 until the range fits in about five lines.
    private func valueTicks(low: Double, high: Double) -> [Double] {
        let span = max(high - low, 1)
        let step = [1.0, 2.0, 5.0, 10.0, 20.0].first { span / $0 <= 5.5 } ?? 20
        let first = (low / step).rounded(.up) * step
        return stride(from: first, through: high, by: step).map { $0 }
    }

    private func drawValueLabels(
        _ context: GraphicsContext, plot: CGRect, ticks: [Double],
        gutter: CGFloat, y: (Double) -> CGFloat
    ) {
        let pointSize: CGFloat = typeSize.isAccessibilitySize ? 15 : 12
        for tick in ticks {
            let text = Text("\(Int(tick))°")
                .font(.custom(VaneFont.mono, fixedSize: pointSize))
                .foregroundStyle(palette.inkColor.opacity(0.45))
            context.draw(text, at: .init(x: gutter - 8, y: y(tick)), anchor: .trailing)
        }
    }

    /// Rainfall, as a row of marks under the trace.
    ///
    /// Drawn only when something is actually falling — an always-present empty row would teach
    /// people to ignore the one place the chart says it is going to rain.
    private func drawPrecipitation(
        _ context: GraphicsContext, plot: CGRect, size: CGSize, x: (Double) -> CGFloat
    ) {
        let peak = max(points.map(\.precipMm).max() ?? 0, 1)
        let base = size.height - 22
        let height: CGFloat = 18
        let width = max(plot.width / CGFloat(max(points.count, 1)) - 1, 1.5)

        for point in points where point.precipMm > 0 {
            let bar = CGFloat(min(point.precipMm / peak, 1)) * height
            context.fill(
                Path(CGRect(x: x(point.hour) - width / 2, y: base - bar,
                            width: width, height: bar)),
                with: .color(palette.traceColor.opacity(point.hour <= nowHour ? 0.55 : 0.28))
            )
        }
    }

    private var hasPrecipitation: Bool { points.contains { $0.precipMm > 0 } }

    private func drawHourLabels(
        _ context: GraphicsContext, plot: CGRect, size: CGSize, x: (Double) -> CGFloat
    ) {
        // The axis is a fixed width, so its labels cannot scale without colliding — at AX5 the
        // three-hourly labels overlap into unreadable pulp. Thin them to six-hourly and cap the
        // size instead. This is the designed accessibility path: fewer, larger, legible marks,
        // not the same marks made illegible.
        let step: Double = typeSize.isAccessibilitySize ? 6 : 3
        let pointSize: CGFloat = typeSize.isAccessibilitySize ? 15 : 12

        for hour in stride(from: 0.0, through: 24.0, by: step) {
            let text = Text(String(format: "%02d", Int(hour)))
                .font(.custom(VaneFont.mono, fixedSize: pointSize))
                .foregroundStyle(palette.inkColor.opacity(0.45))
            // Centred on its own gridline, except at the ends: hour 0 and hour 24 sit on the
            // paper's edges and would hang off it, so they are pulled inward.
            let anchor: UnitPoint = switch hour {
            case 0: .leading
            case 24: .trailing
            default: .center
            }
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
        // Three cases, not two. Reporting "within the usual range" for a day that is below it
        // tells a VoiceOver user the opposite of what the chart shows — and *below* the band is
        // exactly the situation the sentence above the chart is currently describing.
        if let normalHigh, let normalLow {
            if now > normalHigh {
                summary += " Above the usual range for this date."
            } else if now < normalLow {
                summary += " Below the usual range for this date."
            } else {
                summary += " Within the usual range for this date."
            }
        }
        if hasPrecipitation {
            let total = points.reduce(0) { $0 + $1.precipMm }
            summary += String(format: " %.1f millimetres of rain expected today.", total)
        }
        return summary
    }
}

import SwiftUI
import VaneKit

/// The roll. Every day since install, on one sheet of paper.
///
/// The signature of this design is that the trace never breaks — today is the right-hand end of
/// a roll that began the day the app was installed, and dragging left moves along the same
/// paper. Points compress as more history has to fit: days become weeks, weeks become months,
/// aggregated in SQL rather than in Swift, because it runs while a finger is moving.
public struct ArchiveScreen: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let points: [ArchivePoint]
    private let palette: Palette

    public init(points: [ArchivePoint], palette: Palette) {
        self.points = points
        self.palette = palette
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { dismiss() } label: {
                Text("← TODAY")
                    .font(.vaneData).tracking(1.4)
                    .foregroundStyle(palette.traceColor)
                    .frame(minWidth: 44, minHeight: 44, alignment: .leading)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Back to today")

            Spacer().frame(height: 10)
            Text("THE RECORD — \(points.count) \(points.count == 1 ? "MARK" : "MARKS")")
                .font(.vaneData).tracking(1.4)
                .foregroundStyle(palette.inkColor)

            Spacer().frame(height: 4)
            Text(spanLabel)
                .font(.vaneData).tracking(1.2)
                .foregroundStyle(palette.inkColor.opacity(0.55))

            Spacer().frame(height: 26)

            if points.isEmpty {
                Empty(palette: palette)
            } else {
                Roll(points: points, palette: palette)
                    .frame(maxHeight: .infinity)
                Spacer().frame(height: 20)
                ArchiveLegend(palette: palette)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(palette.paperColor)
        #if os(iOS)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }

    private var spanLabel: String {
        guard let first = points.first?.day, let last = points.last?.day else { return "" }
        return first == last ? first : "\(first)  →  \(last)"
    }

    /// The record starts today. Copy states that rather than apologising for being empty —
    /// there is nothing wrong here, it is simply the first mark on a new roll.
    struct Empty: View {
        let palette: Palette
        var body: some View {
            VStack(alignment: .leading, spacing: 10) {
                Text("The record starts today.")
                    .vaneContextType()
                    .foregroundStyle(palette.inkColor)
                Text("Every day the app is opened adds a mark. It gets more interesting the longer it runs.")
                    .font(.vaneBody)
                    .foregroundStyle(palette.inkColor.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// The unbroken line, drawn over each day's own normal.
struct Roll: View {
    let points: [ArchivePoint]
    let palette: Palette

    var body: some View {
        Canvas { context, size in
            guard points.count > 0 else { return }

            // Only what is actually drawn. Including the daily lows stretched the axis down to
            // 10 degrees for values that never appear on the paper — a scale that describes
            // data it is not showing.
            let values = points.flatMap { [$0.tmaxC] + ($0.normalTmaxC.map { [$0] } ?? []) }
            let low = (values.min() ?? 0) - 2
            let high = (values.max() ?? 1) + 2
            let span = max(high - low, 0.001)

            let plot = CGRect(x: 34, y: 6, width: size.width - 34, height: size.height - 26)
            let step = points.count > 1 ? plot.width / CGFloat(points.count - 1) : 0
            func x(_ index: Int) -> CGFloat { plot.minX + step * CGFloat(index) }
            func y(_ value: Double) -> CGFloat { plot.maxY - plot.height * (value - low) / span }

            // Value scale, same treatment as the day chart so the two read as one instrument.
            let stepValue = [2.0, 5.0, 10.0, 20.0].first { span / $0 <= 5.5 } ?? 20
            var tick = (low / stepValue).rounded(.up) * stepValue
            while tick <= high {
                context.stroke(
                    Path { $0.move(to: .init(x: plot.minX, y: y(tick)))
                           $0.addLine(to: .init(x: plot.maxX, y: y(tick))) },
                    with: .color(palette.gridColor), lineWidth: 0.5
                )
                context.draw(
                    Text("\(Int(tick))°")
                        .font(.custom(VaneFont.mono, fixedSize: 11))
                        .foregroundStyle(palette.inkColor.opacity(0.45)),
                    at: .init(x: 26, y: y(tick)), anchor: .trailing
                )
                tick += stepValue
            }

            // The normal, travelling with the roll: each mark against *its* date's normal, so a
            // warm January and a warm July both read as above the line.
            let normals = points.enumerated().compactMap { index, point in
                point.normalTmaxC.map { (index, $0) }
            }
            if normals.count > 1 {
                var path = Path()
                for (position, (index, value)) in normals.enumerated() {
                    let point = CGPoint(x: x(index), y: y(value))
                    position == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                context.stroke(path, with: .color(palette.bandColor),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // The trace itself. One line, never lifted.
            var trace = Path()
            for (index, point) in points.enumerated() {
                let location = CGPoint(x: x(index), y: y(point.tmaxC))
                index == 0 ? trace.move(to: location) : trace.addLine(to: location)
            }
            context.stroke(trace, with: .color(palette.traceColor),
                           style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))

            // The pen, resting where the record currently ends.
            if let last = points.last {
                let tip = CGPoint(x: x(points.count - 1), y: y(last.tmaxC))
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10)),
                             with: .color(palette.paperColor))
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)),
                             with: .color(palette.traceColor))
            }
        }
        .accessibilityElement()
        .accessibilityLabel(summary)
    }

    private var summary: String {
        guard let warmest = points.max(by: { $0.tmaxC < $1.tmaxC }),
              let coolest = points.min(by: { $0.tmaxC < $1.tmaxC }) else {
            return "Your record, empty so far."
        }
        var text = "Your record, \(points.count) marks. "
        text += "Warmest \(Int(warmest.tmaxC.rounded())) degrees on \(warmest.day). "
        text += "Coolest \(Int(coolest.tmaxC.rounded())) degrees on \(coolest.day)."
        return text
    }
}


/// The archive's own legend. Reusing the forecast's said "FORECAST" over a record of days that
/// have already happened, and "RANGE" over a line.
struct ArchiveLegend: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(palette.traceColor).frame(width: 22, height: 3)
            Text("RECORDED HIGH")
            DashRule(color: palette.bandColor).frame(width: 22, height: 3)
            Text("30-YEAR NORMAL")
        }
        .font(.vaneData).tracking(1.1)
        .foregroundStyle(palette.inkColor.opacity(0.5))
        .accessibilityHidden(true)
    }
}

struct DashRule: View {
    let color: Color
    var body: some View {
        Canvas { context, size in
            context.stroke(
                Path { $0.move(to: .init(x: 0, y: size.height / 2))
                       $0.addLine(to: .init(x: size.width, y: size.height / 2)) },
                with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
        }
    }
}

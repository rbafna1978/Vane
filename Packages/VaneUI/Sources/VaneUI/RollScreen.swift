import SwiftUI
import VaneKit

/// One surface. The horizontal axis is time.
///
/// This replaces three pushed screens. The premise of the design is a barograph roll — past to
/// the left, future to the right, the pen at today, and the trace never broken — and pushing a
/// new screen to show yesterday contradicted that premise directly. Here nothing is pushed:
/// dragging moves the paper, and the reading, the sentence and the readout are all *functions of
/// where the pen is*, recomputed continuously rather than swapped at a threshold.
public struct RollScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var model: WeatherModel
    /// Where the pen is, in days from today. Continuous, not an index — content responds to
    /// position at every frame, which is what separates manipulation from navigation.
    @State private var scrub: Double = 0
    @State private var dragStart: Double = 0
    @State private var isDragging = false

    /// Points of paper per day. Fixed, so the roll's speed under the finger is the same whether
    /// you are in the record or the forecast.
    private let dayWidth: CGFloat = 46

    public init(model: WeatherModel) {
        _model = State(initialValue: model)
    }

    private var marks: [TimelineMark] { model.timeline }

    private var bounds: (first: Double, last: Double) {
        (marks.first?.offset ?? 0, marks.last?.offset ?? 0)
    }

    /// The mark the pen is nearest. Whole-number scrub lands exactly on one.
    private var focused: TimelineMark? {
        marks.min { abs($0.offset - scrub) < abs($1.offset - scrub) }
    }

    public var body: some View {
        let palette = model.sky.palette

        ZStack {
            palette.paperColor.ignoresSafeArea()

            if let snapshot = model.snapshot {
                VStack(alignment: .leading, spacing: 0) {
                    StationLine(snapshot: snapshot, place: model.placeName, palette: palette)

                    Spacer().frame(height: 26)
                    Header(mark: focused, snapshot: snapshot, scrub: scrub, palette: palette)

                    Spacer(minLength: 18)
                    RollCanvas(
                        marks: marks, scrub: scrub, dayWidth: dayWidth,
                        palette: palette, isDragging: isDragging,
                        onAdjust: { step in
                            withAnimation(VaneMotion.figure) {
                                scrub = min(max(scrub + step, bounds.first), bounds.last)
                            }
                        }
                    )
                    .frame(maxHeight: .infinity)
                    .contentShape(.rect)
                    .gesture(drag)

                    Spacer().frame(height: 16)
                    Readout(mark: focused, snapshot: snapshot, palette: palette)

                    Spacer().frame(height: 18)
                    StreakBar(count: model.streak, palette: palette)
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 10)
            } else {
                EmptyStateView(screen: model.screen, palette: palette) {
                    Task { await model.refresh() }
                }
            }
        }
        .animation(VaneMotion.sky, value: palette)
        .task {
            await model.refresh()
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    // Start from where the paper currently *is*, so grabbing a moving roll
                    // continues from the presentation value instead of jumping to the target.
                    dragStart = scrub
                }
                // 1:1 with the finger. No animation on the tracking path — anything here puts
                // lag between the touch and the paper, which is the whole difference between
                // dragging paper and dragging a picture of paper.
                scrub = rubberBanded(dragStart - value.translation.width / dayWidth)
            }
            .onEnded { value in
                isDragging = false
                let velocityDays = -value.predictedEndTranslation.width / dayWidth
                    + value.translation.width / dayWidth

                // Apple's momentum projection: land where the flick was *going*, then snap to
                // the nearest day from there. Snapping from the release point instead makes a
                // hard flick feel identical to a slow drag.
                let projected = dragStart - value.predictedEndTranslation.width / dayWidth
                let target = min(max(projected.rounded(), bounds.first), bounds.last)

                withAnimation(
                    reduceMotion
                        ? .easeOut(duration: 0.25)
                        : .interpolatingSpring(
                            stiffness: 200, damping: 26,
                            initialVelocity: min(max(velocityDays, -20), 20)
                        )
                ) {
                    scrub = target
                }
            }
    }

    /// Progressive resistance past the ends of the record, using UIScrollView's own curve. The
    /// roll has a beginning and an end; a hard stop reads as broken, resistance reads as "there
    /// is no more paper here".
    private func rubberBanded(_ raw: Double) -> Double {
        let constant = 0.55
        let dimension = 6.0
        if raw < bounds.first {
            let past = bounds.first - raw
            return bounds.first - (past * dimension * constant) / (dimension + constant * past)
        }
        if raw > bounds.last {
            let past = raw - bounds.last
            return bounds.last + (past * dimension * constant) / (dimension + constant * past)
        }
        return raw
    }
}

// MARK: - Header

/// The reading and the sentence, as functions of where the pen is.
///
/// Nothing here switches at a boundary: scrubbing to yesterday does not "open yesterday", it
/// moves the same three lines to different values. The number rolls rather than swapping,
/// because it is the same number changing, not a new one arriving.
struct Header: View {
    let mark: TimelineMark?
    let snapshot: Snapshot
    let scrub: Double
    let palette: Palette

    private var isToday: Bool { abs(scrub) < 0.5 }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(dayLabel)
                .font(.vaneData).tracking(1.4)
                .foregroundStyle(palette.inkColor.opacity(0.55))
                .contentTransition(.opacity)

            HStack(alignment: .top, spacing: 0) {
                RollingNumber(reading)
                    .lineLimit(1).minimumScaleFactor(0.7)
                Text("°")
                    .font(.custom(VaneFont.display, fixedSize: 46))
                    .offset(y: 34)
                    .accessibilityHidden(true)
            }
            .foregroundStyle(palette.inkColor)
            .accessibilityLabel("\(Int(reading.rounded())) degrees")

            Text(secondary)
                .font(.vaneData).tracking(1.3)
                .foregroundStyle(palette.inkColor.opacity(0.72))
                .lineLimit(1).minimumScaleFactor(0.85)
                .contentTransition(.opacity)

            Text(sentence)
                .vaneContextType()
                .foregroundStyle(palette.inkColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .topLeading)
                .contentTransition(.opacity)
        }
        .animation(VaneMotion.figure, value: mark)
    }

    /// Today shows the live reading; any other day shows that day's high, which is the only
    /// figure a past or future day actually has.
    private var reading: Double {
        isToday ? snapshot.current.tempC : (mark?.highC ?? snapshot.current.tempC)
    }

    private var dayLabel: String {
        guard let mark, !isToday else { return "TODAY" }
        guard let date = Timeline.dayFormatter(in: snapshot.timeZone).date(from: mark.dayKey)
        else { return mark.dayKey }
        return date.formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated))
            .uppercased()
    }

    private var secondary: String {
        if isToday {
            var parts: [String] = []
            let condition = snapshot.current.condition.label
            if !condition.isEmpty { parts.append(condition.uppercased()) }
            if abs(snapshot.current.feelsC - snapshot.current.tempC) >= 2 {
                parts.append("FEELS \(Int(snapshot.current.feelsC.rounded()))°")
            }
            return parts.joined(separator: "   ·   ")
        }
        guard let mark else { return "" }
        var parts: [String] = []
        if let low = mark.lowC { parts.append("LOW \(Int(low.rounded()))°") }
        if mark.precipMm > 0 { parts.append(String(format: "%.1fMM", mark.precipMm)) }
        parts.append(mark.kind == .recorded ? "RECORDED" : "FORECAST")
        return parts.joined(separator: "   ·   ")
    }

    /// Today keeps its context sentence. Every other day gets the same comparison the sentence
    /// is made of — how far it sat from its own date's normal — so the argument of the app is
    /// present at every position on the roll, not only at the anchor.
    private var sentence: String {
        if isToday, let headline = snapshot.context?.headline { return headline }
        guard let mark, let anomaly = mark.anomaly else { return "" }
        let rounded = Int(abs(anomaly).rounded())
        if rounded == 0 { return "Right on the usual mark for the date." }
        let direction = anomaly > 0 ? "warmer" : "cooler"
        return "\(rounded)° \(direction) than usual for the date."
    }
}

// MARK: - Readout

struct Readout: View {
    let mark: TimelineMark?
    let snapshot: Snapshot
    let palette: Palette

    var body: some View {
        HStack(spacing: 18) {
            if let normal = mark?.normalHighC {
                Text("NORMAL \(Int(normal.rounded()))°")
            }
            Spacer()
            Text("↑ \(time(snapshot.sun.sunrise))")
            Text("↓ \(time(snapshot.sun.sunset))")
        }
        .font(.vaneData).tracking(1.2)
        .foregroundStyle(palette.inkColor.opacity(0.6))
        .lineLimit(1)
        .accessibilityElement(children: .ignore)
        .accessibilityHidden(true)
    }

    private func time(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

// MARK: - The roll

/// The paper itself. One unbroken trace across the record, today, and the forecast.
///
/// Recorded days are solid, the forecast is finer and dashed, and the pen sits at today — the
/// same language as the day chart, at a different scale, so the two read as one instrument.
struct RollCanvas: View {
    let marks: [TimelineMark]
    let scrub: Double
    let dayWidth: CGFloat
    let palette: Palette
    let isDragging: Bool

    var body: some View {
        Canvas { context, size in
            guard marks.count > 1 else { return }

            let values = marks.flatMap { [$0.highC] + ($0.normalHighC.map { [$0] } ?? []) }
            let low = (values.min() ?? 0) - 2
            let high = (values.max() ?? 1) + 2
            let span = max(high - low, 0.001)

            let plot = CGRect(x: 34, y: 8, width: size.width - 34, height: size.height - 30)
            // The pen stays put and the paper moves under it — the fixed thing on screen is the
            // instrument, not the data.
            let penX = plot.midX
            func x(_ offset: Double) -> CGFloat { penX + CGFloat(offset - scrub) * dayWidth }
            func y(_ value: Double) -> CGFloat { plot.maxY - plot.height * (value - low) / span }

            // Value scale
            let stepValue = [2.0, 5.0, 10.0, 20.0].first { span / $0 <= 5.5 } ?? 20
            var tick = (low / stepValue).rounded(.up) * stepValue
            while tick <= high {
                context.stroke(
                    Path { $0.move(to: .init(x: plot.minX, y: y(tick)))
                           $0.addLine(to: .init(x: plot.maxX, y: y(tick))) },
                    with: .color(palette.gridColor), lineWidth: 0.5
                )
                context.draw(
                    Text("\(Int(tick))°").font(.custom(VaneFont.mono, fixedSize: 11))
                        .foregroundStyle(palette.inkColor.opacity(0.45)),
                    at: .init(x: 26, y: y(tick)), anchor: .trailing
                )
                tick += stepValue
            }

            // The normal, travelling with the paper.
            let normals = marks.compactMap { mark in mark.normalHighC.map { (mark.offset, $0) } }
            if normals.count > 1 {
                var path = Path()
                for (index, entry) in normals.enumerated() {
                    let point = CGPoint(x: x(entry.0), y: y(entry.1))
                    index == 0 ? path.move(to: point) : path.addLine(to: point)
                }
                context.stroke(path, with: .color(palette.bandColor),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // The trace. Solid where it happened, finer and dashed where it has not yet.
            let past = marks.filter { $0.offset <= 0 }
            let ahead = marks.filter { $0.offset >= 0 }
            if ahead.count > 1 {
                context.stroke(path(ahead, x: x, y: y),
                               with: .color(palette.traceColor.opacity(0.4)),
                               style: StrokeStyle(lineWidth: 1.2, lineCap: .round, dash: [2.5, 3]))
            }
            if past.count > 1 {
                context.stroke(path(past, x: x, y: y), with: .color(palette.traceColor),
                               style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
            }

            // Day ticks, so the scale is readable rather than merely continuous.
            for mark in marks where Int(mark.offset) % 7 == 0 {
                context.stroke(
                    Path { $0.move(to: .init(x: x(mark.offset), y: plot.maxY))
                           $0.addLine(to: .init(x: x(mark.offset), y: plot.maxY + 5)) },
                    with: .color(palette.gridColor), lineWidth: 0.5
                )
            }

            // The pen. Fixed at centre; the value under it is what the header is reading.
            if let focused = marks.min(by: { abs($0.offset - scrub) < abs($1.offset - scrub) }) {
                let tip = CGPoint(x: penX, y: y(focused.highC))
                context.stroke(
                    Path { $0.move(to: .init(x: penX, y: plot.minY))
                           $0.addLine(to: .init(x: penX, y: plot.maxY)) },
                    with: .color(palette.traceColor.opacity(isDragging ? 0.35 : 0.18)),
                    lineWidth: 0.75
                )
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 5, y: tip.y - 5, width: 10, height: 10)),
                             with: .color(palette.paperColor))
                context.fill(Path(ellipseIn: CGRect(x: tip.x - 3, y: tip.y - 3, width: 6, height: 6)),
                             with: .color(palette.traceColor))
            }
        }
        .accessibilityElement()
        .accessibilityLabel("The roll. \(marks.count) days, past to future.")
        .accessibilityValue(accessibilityValue)
        // A drag is not operable by VoiceOver, so the same axis is exposed as an adjustable.
        .accessibilityAdjustableAction { direction in
            adjust(direction)
        }
    }

    private var accessibilityValue: String {
        guard let focused = marks.min(by: { abs($0.offset - scrub) < abs($1.offset - scrub) })
        else { return "" }
        return "\(focused.dayKey), high \(Int(focused.highC.rounded())) degrees"
    }

    private func path(
        _ marks: [TimelineMark], x: (Double) -> CGFloat, y: (Double) -> CGFloat
    ) -> Path {
        Path { path in
            for (index, mark) in marks.enumerated() {
                let point = CGPoint(x: x(mark.offset), y: y(mark.highC))
                index == 0 ? path.move(to: point) : path.addLine(to: point)
            }
        }
    }

    var onAdjust: ((Double) -> Void)?
    private func adjust(_ direction: AccessibilityAdjustmentDirection) {
        onAdjust?(direction == .increment ? 1 : -1)
    }
}

// MARK: - Chrome

struct StationLine: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let snapshot: Snapshot
    let place: String?
    let palette: Palette

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text((place ?? "Here").uppercased())
                .font(.vaneData).tracking(1.4)
                .lineLimit(2)
            Spacer(minLength: 8)
            // Texture, not information. First thing to go when type gets large.
            if !typeSize.isAccessibilitySize {
                Text(stationCode)
                    .font(.vaneData).tracking(1.4).opacity(0.55)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(palette.inkColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(place ?? "Current location")
    }

    private var stationCode: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "ddHHmm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return "\(formatter.string(from: snapshot.observedAt))Z"
    }
}

/// Consecutive days opened, as a measured rule rather than seven dots — seven evenly spaced dots
/// at the bottom of a screen is a `UIPageControl`, and people will try to swipe it.
struct StreakBar: View {
    let count: Int
    let palette: Palette

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<28, id: \.self) { index in
                Rectangle()
                    .fill(index < min(count, 28) ? palette.traceColor : palette.gridColor)
                    .frame(width: 1, height: index % 7 == 6 ? 9 : 5)
            }
            Spacer()
        }
        .frame(height: 9, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "Opened today" : "Opened \(count) days in a row")
    }
}

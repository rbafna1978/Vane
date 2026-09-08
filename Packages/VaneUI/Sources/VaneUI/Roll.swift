import SwiftUI
import VaneKit

// Components of the roll. The surface that composes them is `VaneScreen`.

// MARK: - Header

/// The reading and the sentence, as functions of where the pen is.
///
/// Nothing here switches at a boundary: scrubbing to yesterday does not "open yesterday", it
/// moves the same three lines to different values. The number rolls rather than swapping,
/// because it is the same number changing, not a new one arriving.
/// Slices one 0-to-1 entrance into an overlapping window for one element.
///
/// Overlapping on purpose: gaps between elements read as a queue of separate animations, while
/// an overlap of roughly half each window reads as one movement passing through the layout.
nonisolated func entrancePhase(_ t: Double, start: Double, span: Double = 0.45) -> Double {
    let raw = min(max((t - start) / span, 0), 1)
    // Ease-out, because everything here is *entering* — it should arrive fast and settle.
    return 1 - pow(1 - raw, 3)
}

struct Header: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let mark: TimelineMark?
    /// The day under the pen, whether or not anything was recorded on it.
    let day: Int
    let snapshot: Snapshot
    let scrub: Double
    let palette: Palette
    var entrance: Double = 1

    private var isToday: Bool { day == 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.close) {
            // The day is a heading, not metadata. Three mono rows at one size and one opacity
            // made "SAT, SEP 5", "LOW 12° · RECORDED" and "NORMAL 27°" indistinguishable, which
            // is a hierarchy with two levels and a hole in the middle. This one is the largest
            // and darkest of the three; the other two step down from it.
            Text(dayLabel)
                .font(.custom(VaneFont.mono, size: 13, relativeTo: .footnote))
                .tracking(2.2)
                .foregroundStyle(palette.secondaryColor)
                .contentTransition(.opacity)
                .modifier(Enter(entrancePhase(entrance, start: 0)))

            // A day with no entry gets no number. Showing a dash, a zero, or the nearest
            // day's reading would all be inventing one — the honest thing a barograph does
            // when the pen was lifted is leave the paper blank.
            if let reading {
                RollingNumber(reading, unit: "°")
                    .lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(palette.inkColor)
                    // Trim the line box.
                    //
                    // A 148pt face reserves its ascender and descender whether or not the
                    // glyphs use them, and "28" uses neither — which left about 60 points of
                    // dead air above the caps and another 40 below the baseline, reading as
                    // two accidental gaps rather than as one deliberate one. Negative padding
                    // pulls the box in to roughly the cap-to-baseline extent without clipping
                    // anything, so the spacing scale controls the gaps instead of the font's
                    // metrics doing it by accident.
                    .padding(.top, -VaneType.reading(for: typeSize) * 0.15)
                    .padding(.bottom, -VaneType.reading(for: typeSize) * 0.11)
                    .accessibilityLabel("\(Int(reading.rounded())) degrees")
                    .modifier(Enter(entrancePhase(entrance, start: 0.08), rise: 22))
            } else {
                Color.clear.frame(height: VaneType.readingSize * 0.72)
                    .accessibilityHidden(true)
            }

            Text(secondary)
                .font(.vaneData).tracking(1.3)
                .foregroundStyle(palette.secondaryColor)
                .lineLimit(1).minimumScaleFactor(0.85)
                .contentTransition(.opacity)
                .modifier(Enter(entrancePhase(entrance, start: 0.18)))

            Text(sentence)
                .vaneContextType()
                .foregroundStyle(palette.inkColor)
                .fixedSize(horizontal: false, vertical: true)
                .frame(minHeight: 40, alignment: .topLeading)
                .padding(.top, Space.tight)
                .contentTransition(.opacity)
                .modifier(Enter(entrancePhase(entrance, start: 0.26)))
        }
        .animation(VaneMotion.figure, value: mark)
    }

    /// Today shows the live reading; any other day shows that day's high, which is the only
    /// figure a past or future day actually has.
    private var reading: Double? {
        if isToday { return snapshot.current.tempC }
        return mark?.highC
    }

    /// Derived from the day offset rather than from the mark, so a day with no entry is still
    /// named. The strip's axis is time; a blank day is still a date.
    private var dayLabel: String {
        guard !isToday else { return "TODAY" }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        let today = calendar.startOfDay(for: snapshot.observedAt)
        guard let date = calendar.date(byAdding: .day, value: day, to: today) else { return "" }
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
        guard let mark else { return "NO ENTRY" }
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
        guard mark != nil else {
            return "The record has no entry for this day. Vane keeps what it sees while it is open."
        }
        // The same rounded difference the panel prints, so the sentence and the figures below
        // it can never disagree by a degree.
        guard let mark, let shown = mark.displayAnomaly else { return "" }
        if shown == 0 { return "Right on the usual mark for the date." }
        return "\(abs(shown))° \(shown > 0 ? "warmer" : "cooler") than usual for the date."
    }
}

// MARK: - Readout

/// The chart's key, and the day's sun times, in words rather than notation.
///
/// Was: `NORMAL 20°    ↑ 06:46   ↓ 19:28`. Three problems. "Normal" is a statistician's word and
/// does not say normal *what*. Bare arrows are a symbol the reader has to guess at. And the chart
/// above had two dashed lines in two colours with nothing anywhere saying which was which, so
/// the single most important comparison in the app — this day against its own history — was
/// unreadable unless you already knew.
struct Readout: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let mark: TimelineMark?
    let snapshot: Snapshot
    let palette: Palette

    var body: some View {
        VStack(alignment: .leading, spacing: Space.close) {
            // The key. Drawn as the actual strokes, not described in words — a legend that says
            // "dashed line" makes you translate; a legend that *is* the dashed line does not.
            HStack(spacing: Space.block) {
                key(dash: false, color: palette.traceColor, label: "This day")
                key(dash: true, color: palette.bandColor,
                    label: "Usual for the date\(mark?.normalHighC.map { " · \(Int($0.rounded()))°" } ?? "")")
                Spacer(minLength: 0)
            }

            Text("Sunrise \(time(snapshot.sun.sunrise))     Sunset \(time(snapshot.sun.sunset))")
                .font(.vaneData).tracking(1.1)
                .foregroundStyle(palette.secondaryColor)
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
    }

    private func key(dash: Bool, color: Color, label: String) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(color)
                .frame(width: 16, height: 2)
                .mask(alignment: .leading) {
                    if dash {
                        HStack(spacing: 2.5) {
                            ForEach(0..<3, id: \.self) { _ in Rectangle().frame(width: 3.5) }
                        }
                    } else {
                        Rectangle()
                    }
                }
            Text(label)
                .font(.vaneData).tracking(1.1)
                .foregroundStyle(palette.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var spoken: String {
        var text = "Solid line, this day. Dashed line, usual for the date"
        if let normal = mark?.normalHighC { text += ", \(Int(normal.rounded())) degrees" }
        return text + ". Sunrise \(time(snapshot.sun.sunrise)), sunset \(time(snapshot.sun.sunset))."
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
    var entrance: Double = 1
    var timeZone: TimeZone = .current
    var observedAt: Date = .now

    var body: some View {
        Canvas { context, size in
            guard marks.count > 1 else { return }

            let values = marks.flatMap { [$0.highC] + ($0.normalHighC.map { [$0] } ?? []) }
            let low = (values.min() ?? 0) - 2
            let high = (values.max() ?? 1) + 2
            let span = max(high - low, 0.001)

            // The plot starts at the text margin, not at an inset of its own. Value labels sit
            // *on* the paper above their rule, the way a printed chart carries its scale,
            // rather than in a gutter that pushes the chart out of line with everything above.
            let plot = CGRect(x: 0, y: 10, width: size.width, height: size.height - 30)
            // The pen stays put and the paper moves under it — the fixed thing on screen is the
            // instrument, not the data.
            let penX = plot.midX
            func x(_ offset: Double) -> CGFloat { penX + CGFloat(offset - scrub) * dayWidth }
            func y(_ value: Double) -> CGFloat { plot.maxY - plot.height * (value - low) / span }

            // MARK: The printed grid
            //
            // Direction A has said "printed hairline grid" since GATE 2 and the paper was a flat
            // fill for four phases. It is not decoration: ruling is what makes a blank stretch
            // read as chart stock with nothing recorded on it, instead of as a broken screen.
            // On a new install most of the roll *is* blank, so this carries the whole surface.

            // Vertical: one rule per day, travelling with the paper. Every seventh is a week
            // boundary and gets the weight, which is how a barograph drum is actually printed.
            let firstDay = Int((scrub - Double(plot.width / dayWidth) / 2 - 1).rounded(.down))
            let lastDay = Int((scrub + Double(plot.width / dayWidth) / 2 + 1).rounded(.up))
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = timeZone
            let todayStart = calendar.startOfDay(for: observedAt)

            for day in firstDay...lastDay {
                let isWeek = day % 7 == 0
                context.stroke(
                    Path { $0.move(to: .init(x: x(Double(day)), y: plot.minY))
                           $0.addLine(to: .init(x: x(Double(day)), y: plot.maxY)) },
                    with: .color(palette.gridColor.opacity(isWeek ? 0.85 : 0.35)),
                    lineWidth: 0.5
                )

                // The axis this chart did not have.
                //
                // It was a time series with nothing on its time axis: no dates, no days, not
                // even a "today". Every reading on it was unplaceable, which is most of why a
                // first-time reader could not decode the screen. Labels every other day, so
                // they do not collide at 46 points per day.
                guard day % 2 == 0,
                      let date = calendar.date(byAdding: .day, value: day, to: todayStart)
                else { continue }
                let label = day == 0
                    ? "TODAY"
                    : date.formatted(.dateTime.weekday(.abbreviated)).uppercased()
                context.draw(
                    Text(label)
                        .font(.custom(VaneFont.mono, fixedSize: 9))
                        .foregroundStyle(day == 0 ? palette.traceColor : palette.secondaryColor),
                    at: .init(x: x(Double(day)), y: plot.maxY + 12), anchor: .center
                )
            }

            // Horizontal: a labelled rule at each step, and an unlabelled half-step between —
            // the minor ruling is most of what your eye reads as "printed" rather than "drawn".
            let stepValue = [2.0, 5.0, 10.0, 20.0].first { span / $0 <= 5.5 } ?? 20
            var minor = (low / (stepValue / 2)).rounded(.up) * (stepValue / 2)
            while minor <= high {
                context.stroke(
                    Path { $0.move(to: .init(x: plot.minX, y: y(minor)))
                           $0.addLine(to: .init(x: plot.maxX, y: y(minor))) },
                    with: .color(palette.gridColor.opacity(0.3)), lineWidth: 0.5
                )
                minor += stepValue / 2
            }

            var tick = (low / stepValue).rounded(.up) * stepValue
            while tick <= high {
                context.stroke(
                    Path { $0.move(to: .init(x: plot.minX, y: y(tick)))
                           $0.addLine(to: .init(x: plot.maxX, y: y(tick))) },
                    with: .color(palette.gridColor.opacity(0.85)), lineWidth: 0.5
                )
                // Above the rule and hard left, sitting on the paper. Two points of optical
                // offset because a baseline set exactly on a rule reads as touching it.
                context.draw(
                    Text("\(Int(tick))°").font(.custom(VaneFont.mono, fixedSize: 10))
                        .foregroundStyle(palette.secondaryColor),
                    at: .init(x: plot.minX + 1, y: y(tick) - 3), anchor: .bottomLeading
                )
                tick += stepValue
            }

            // The normal, travelling with the paper.
            let normals = marks.compactMap { mark in mark.normalHighC.map { (mark.offset, $0) } }
            if normals.count > 1 {
                var path = Path()
                var previous: Double?
                for entry in normals {
                    let point = CGPoint(x: x(entry.0), y: y(entry.1))
                    if let previous, entry.0 - previous <= 1.0 {
                        path.addLine(to: point)
                    } else {
                        path.move(to: point)
                    }
                    previous = entry.0
                }
                context.stroke(path, with: .color(palette.bandColor),
                               style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }

            // The trace. Solid where it happened, finer and dashed where it has not yet.
            let past = marks.filter { $0.offset <= 0 }
            let ahead = marks.filter { $0.offset >= 0 }
            if ahead.count > 1 {
                // Lighter than the record and dashed, because it has not happened — but not so
                // light that it disappears. On a new install the forecast is most of what there
                // is to look at, and at 40% of a hairline it read as a smudge.
                context.stroke(
                    // Trimmed by the entrance, so the pen lays the forecast down left to right
                    // rather than the whole line appearing at once. This is the barograph doing
                    // the one thing a barograph does, and it is the difference between a chart
                    // that was printed and an instrument that is running.
                    path(ahead, x: x, y: y).trimmedPath(from: 0, to: max(entrance, 0.001)),
                    with: .color(palette.traceColor.opacity(0.62)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, dash: [3, 3.5])
                )
            }
            if past.count > 1 {
                // The record draws from its far end toward today, arriving at the pen — the
                // direction the drum actually turns.
                context.stroke(
                    path(past, x: x, y: y).trimmedPath(from: 0, to: max(entrance, 0.001)),
                    with: .color(palette.traceColor),
                    style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round)
                )
            }

            // The guide line is always there — it is the instrument, and the instrument does
            // not disappear on a day with no reading.
            context.stroke(
                Path { $0.move(to: .init(x: penX, y: plot.minY))
                       $0.addLine(to: .init(x: penX, y: plot.maxY)) },
                with: .color(palette.traceColor.opacity(isDragging ? 0.35 : 0.18)),
                lineWidth: 0.75
            )
            // The nib only touches the paper where there is a reading, and only on the exact
            // day under it. Nearest-mark would float the nib off the trace whenever the record
            // had a gap, which is precisely where it must not.
            if let focused = marks.first(where: { $0.offset == scrub.rounded() }), entrance > 0.55 {
                let tip = CGPoint(x: penX, y: y(focused.highC))
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
        guard let focused = marks.first(where: { $0.offset == scrub.rounded() })
        else { return "No entry for this day" }
        return "\(focused.dayKey), high \(Int(focused.highC.rounded())) degrees"
    }

    /// The trace, lifted across any day that has no entry.
    ///
    /// Joining two marks three days apart with a straight line draws two readings that were
    /// never taken and makes the record look continuous when it is not. A real barograph leaves
    /// the paper blank when the pen is off it, and so does this one.
    private func path(
        _ marks: [TimelineMark], x: (Double) -> CGFloat, y: (Double) -> CGFloat
    ) -> Path {
        Path { path in
            var previous: Double?
            for mark in marks {
                let point = CGPoint(x: x(mark.offset), y: y(mark.highC))
                if let previous, mark.offset - previous <= 1.0 {
                    path.addLine(to: point)
                } else {
                    path.move(to: point)
                }
                previous = mark.offset
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
                Text(updatedAt)
                    .font(.vaneData).tracking(1.4).opacity(0.55)
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(palette.inkColor)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(place ?? "Current location")
    }

    /// Was `081915Z` — a METAR observation group, day-of-month plus Zulu time. It is exactly
    /// the vernacular the brief asks the visual language to come from, and it is also completely
    /// opaque to anyone who has not filed a flight plan. The instrument vocabulary is kept where
    /// it is *explained* by what sits beside it — the Beaufort description, the okta labels, the
    /// 1013 line — and dropped where it is only decoration standing in an information slot.
    private var updatedAt: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: snapshot.observedAt)
        return String(format: "UPDATED %02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// Consecutive days opened, as a measured rule rather than seven dots — seven evenly spaced dots
/// at the bottom of a screen is a `UIPageControl`, and people will try to swipe it.
struct StreakBar: View {
    let count: Int
    let palette: Palette

    var body: some View {
        HStack(alignment: .bottom, spacing: Space.block) {
            HStack(alignment: .bottom, spacing: 4) {
                ForEach(0..<28, id: \.self) { index in
                    Rectangle()
                        .fill(index < min(count, 28) ? palette.traceColor : palette.gridColor)
                        .frame(width: 1, height: index % 7 == 6 ? 9 : 5)
                }
            }
            // A bare row of ticks is an artefact, not information. Nobody counts 28 hairlines
            // to find out they have a four-day streak.
            Text(count == 1 ? "OPENED 1 DAY IN A ROW" : "OPENED \(count) DAYS IN A ROW")
                .font(.vaneData).tracking(1.4)
                .foregroundStyle(palette.secondaryColor)
            Spacer(minLength: 0)
        }
        .frame(height: 11, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "Opened today" : "Opened \(count) days in a row")
    }
}

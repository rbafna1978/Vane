import SwiftUI
import VaneKit

/// The depth axis.
///
/// These are not screens and there is no way to navigate to them: they sit below the roll on the
/// same scroll, and every one of them is a function of `mark` — the day the pen is currently on.
/// Scrubbing the roll sideways to September 3rd makes all of them read September 3rd. That
/// composition of two continuous axes is the whole reason the app does not need navigation.
///
/// Where a panel has no data for the focused day it says so in its own words. It never shows a
/// zero, a dash, or a plausible-looking empty chart.

// MARK: - Chrome

/// One panel. Deliberately identical framing for all of them — the label, the rule, the content —
/// because a panel that styles itself differently to seem interesting is the SaaS card kit the
/// brief bans, and because a consistent frame is what lets the *contents* be the varied thing.
struct Panel<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let title: String
    let palette: Palette
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // At accessibility sizes the title takes the whole width and the rule drops below
            // it. Sharing a row, the title wrapped mid-word ("AGAINS / T / NORMAL") and ran
            // straight through its own rule. An eyebrow that has to be deciphered is worse than
            // one that costs a line.
            let stack = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
                : AnyLayout(HStackLayout(spacing: 8))

            stack {
                Text(title)
                    .font(.vaneData).tracking(1.6)
                    .foregroundStyle(palette.secondaryColor)
                    .fixedSize(horizontal: false, vertical: true)
                // The rule runs to the edge rather than boxing the panel. A barograph chart is
                // ruled, not carded.
                Rectangle().fill(palette.gridColor)
                    .frame(maxWidth: .infinity).frame(height: 0.5)
            }
            content
        }
        .padding(.vertical, 20)
        .accessibilityElement(children: .contain)
    }
}

/// Shown where a panel genuinely has nothing for the focused day. The record keeps daily figures
/// only, so scrubbing back past the forecast window really does lose the hourly detail — saying
/// that is more useful than drawing a flat line and letting someone believe the wind dropped.
struct PanelUnavailable: View {
    let reason: String
    let palette: Palette

    var body: some View {
        Text(reason)
            .font(.vaneBody)
            .foregroundStyle(palette.secondaryColor)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Hour by hour

struct HourlyPanel: View {
    let hours: [ForecastHour]
    let palette: Palette

    var body: some View {
        Panel(title: "HOUR BY HOUR", palette: palette) {
            if hours.count < 2 {
                PanelUnavailable(
                    reason: "The record keeps one high and one low for each past day. Hour by hour starts today.",
                    palette: palette
                )
            } else {
                HourlyCurve(hours: hours, palette: palette)
                    .frame(height: 132)
                    .accessibilityElement()
                    .accessibilityLabel(summary)
            }
        }
    }

    private var summary: String {
        guard let warmest = hours.max(by: { $0.tempC < $1.tempC }),
              let coolest = hours.min(by: { $0.tempC < $1.tempC })
        else { return "Hourly temperature" }
        let formatter = DateFormatter()
        formatter.dateFormat = "H"
        let wettest = hours.filter { ($0.precipProbability ?? 0) >= 40 }.count
        var text = "Warmest at \(formatter.string(from: warmest.t)) hundred, "
        text += "\(Int(warmest.tempC.rounded())) degrees. "
        text += "Coolest \(Int(coolest.tempC.rounded())) degrees."
        if wettest > 0 { text += " \(wettest) hours with a 40 percent chance of rain or more." }
        return text
    }
}

/// Temperature as the trace, precipitation probability as columns beneath it.
///
/// Two quantities on one plot, sharing the x axis and nothing else. The probability columns get
/// their own baseline at the bottom third rather than a second y axis, because a right-hand axis
/// on a phone is three more labels for a number nobody reads exactly.
struct HourlyCurve: View {
    let hours: [ForecastHour]
    let palette: Palette

    var body: some View {
        Canvas { context, size in
            let temps = hours.map(\.tempC)
            let low = (temps.min() ?? 0) - 1
            let high = (temps.max() ?? 1) + 1
            let span = max(high - low, 0.001)

            // Inset on the left for the temperature scale, and on the right so the last hour
            // label is not sliced in half by the edge.
            let plot = CGRect(x: 32, y: 4, width: size.width - 44, height: size.height - 22)
            let rainBase = plot.maxY
            let rainHeight = plot.height * 0.34

            func x(_ index: Int) -> CGFloat {
                plot.minX + plot.width * CGFloat(index) / CGFloat(max(hours.count - 1, 1))
            }
            func y(_ value: Double) -> CGFloat {
                plot.maxY - (plot.height - rainHeight) * (value - low) / span
            }

            // Precipitation probability first, so the temperature trace draws over it.
            for (index, hour) in hours.enumerated() {
                let probability = Double(hour.precipProbability ?? 0) / 100
                guard probability > 0.02 else { continue }
                let width = plot.width / CGFloat(hours.count) * 0.62
                let height = rainHeight * probability
                context.fill(
                    Path(CGRect(x: x(index) - width / 2, y: rainBase - height,
                                width: width, height: height)),
                    // Held at the band token's 3:1, because a probability the user is meant to
                    // read is information, not ruling.
                    with: .color(palette.bandColor.opacity(0.55))
                )
            }

            // Two labelled gridlines, at the day's own high and low. A fixed 5-degree ladder
            // would put two or three lines on a flat day and eight on a swinging one; the
            // extremes are the numbers being looked for either way, and they are always two.
            for value in [high - 1, low + 1] {
                context.stroke(
                    Path { $0.move(to: .init(x: plot.minX, y: y(value)))
                           $0.addLine(to: .init(x: plot.maxX, y: y(value))) },
                    with: .color(palette.gridColor), lineWidth: 0.5
                )
                context.draw(
                    Text("\(Int(value.rounded()))°").font(.custom(VaneFont.mono, fixedSize: 11))
                        .foregroundStyle(palette.secondaryColor),
                    at: CGPoint(x: plot.minX - 6, y: y(value)), anchor: .trailing
                )
            }

            var trace = Path()
            for (index, hour) in hours.enumerated() {
                let point = CGPoint(x: x(index), y: y(hour.tempC))
                index == 0 ? trace.move(to: point) : trace.addLine(to: point)
            }
            context.stroke(trace, with: .color(palette.traceColor),
                           style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))

            // Hour labels every six hours. Three-hourly overlaps into pulp at this width.
            let formatter = DateFormatter()
            formatter.dateFormat = "HH"
            for (index, hour) in hours.enumerated() {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = .current
                let h = calendar.component(.hour, from: hour.t)
                guard h % 6 == 0 else { continue }
                context.draw(
                    Text(formatter.string(from: hour.t))
                        .font(.custom(VaneFont.mono, fixedSize: 11))
                        .foregroundStyle(palette.secondaryColor),
                    at: CGPoint(x: x(index), y: size.height - 8), anchor: .center
                )
            }
        }
    }
}

// MARK: - Pressure

/// The barograph, finally drawing pressure.
///
/// The direction has been called The Barograph since GATE 2 while the app downloaded pressure and
/// threw it away. This panel is that instrument doing its actual job: mean-sea-level pressure
/// against the 1013.25 hPa standard atmosphere, and the three-hour tendency, which is the number
/// a forecaster reads off a real barograph before they read the level.
struct PressurePanel: View {
    let hours: [ForecastHour]
    let palette: Palette

    private var readings: [(Date, Double)] {
        hours.compactMap { hour in hour.pressureHpa.map { (hour.t, $0) } }
    }

    var body: some View {
        Panel(title: "PRESSURE", palette: palette) {
            if readings.count < 4 {
                PanelUnavailable(
                    reason: "Pressure is recorded from today forward. The archive keeps temperature and rainfall only.",
                    palette: palette
                )
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        // No thousands separator: 1,016 hPa is a number formatted for prose.
                        // An instrument reads 1016, and every pressure scale ever printed
                        // agrees with the instrument.
                        Text("\(Int((readings.last?.1 ?? 0).rounded()), format: .number.grouping(.never)) hPa")
                            .font(.custom(VaneFont.mono, size: 22))
                        Text(tendencyLabel)
                            .font(.vaneData).tracking(1.2)
                            .foregroundStyle(palette.secondaryColor)
                    }
                    .foregroundStyle(palette.inkColor)

                    PressureTrace(readings: readings, palette: palette)
                        .frame(height: 92)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Pressure \(Int((readings.last?.1 ?? 0).rounded())) hectopascals, \(tendencyLabel.lowercased())"
                )
            }
        }
    }

    /// Change over three hours. The WMO tendency thresholds a synoptic observer uses: under
    /// 0.5 hPa is steady, 0.5 to 3 is the ordinary range, and 3 hPa in three hours is the
    /// classic "rapidly" that precedes weather worth knowing about.
    private var tendencyLabel: String {
        guard readings.count >= 4 else { return "" }
        let index = max(0, readings.count - 4)
        let change = (readings.last?.1 ?? 0) - readings[index].1
        let size = abs(change)
        if size < 0.5 { return "STEADY" }
        let direction = change > 0 ? "RISING" : "FALLING"
        let rate = size >= 3 ? " RAPIDLY" : ""
        return "\(direction)\(rate)   ·   \(String(format: "%+.1f", change)) IN 3H"
    }
}

struct PressureTrace: View {
    let readings: [(Date, Double)]
    let palette: Palette

    var body: some View {
        Canvas { context, size in
            let values = readings.map(\.1)
            // The standard atmosphere is always inside the frame, so the trace is always read
            // against it rather than against a window that floats to fit the data.
            let low = min(values.min() ?? 1000, 1013.25) - 2
            let high = max(values.max() ?? 1020, 1013.25) + 2
            let span = max(high - low, 0.001)

            func x(_ index: Int) -> CGFloat {
                size.width * CGFloat(index) / CGFloat(max(readings.count - 1, 1))
            }
            func y(_ value: Double) -> CGFloat {
                size.height - size.height * (value - low) / span
            }

            let standardY = y(1013.25)
            // The rule stops short of the label rather than running under it. A dashed line
            // crossing its own caption is the reason printed charts break the rule for the key.
            let labelWidth: CGFloat = 34
            context.stroke(
                Path { $0.move(to: .init(x: 0, y: standardY))
                       $0.addLine(to: .init(x: size.width - labelWidth, y: standardY)) },
                with: .color(palette.bandColor), style: StrokeStyle(lineWidth: 1, dash: [3, 3])
            )
            context.draw(
                Text("1013").font(.custom(VaneFont.mono, fixedSize: 10))
                    .foregroundStyle(palette.secondaryColor),
                at: CGPoint(x: size.width, y: standardY), anchor: .trailing
            )

            var trace = Path()
            for (index, reading) in readings.enumerated() {
                let point = CGPoint(x: x(index), y: y(reading.1))
                index == 0 ? trace.move(to: point) : trace.addLine(to: point)
            }
            context.stroke(trace, with: .color(palette.traceColor),
                           style: StrokeStyle(lineWidth: 1.9, lineCap: .round, lineJoin: .round))
        }
    }
}

// MARK: - Wind

struct WindPanel: View {
    let knots: Double?
    let degrees: Int?
    let palette: Palette

    var body: some View {
        Panel(title: "WIND", palette: palette) {
            if let knots, let degrees {
                HStack(alignment: .center, spacing: 22) {
                    WindRose(degrees: degrees, knots: knots, palette: palette)
                        .frame(width: 78, height: 78)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("\(Int(knots.rounded())) kt")
                            .font(.custom(VaneFont.mono, size: 22))
                            .foregroundStyle(palette.inkColor)
                        Text("\(compass(degrees))   ·   FORCE \(beaufort(knots))")
                            .font(.vaneData).tracking(1.2)
                            .foregroundStyle(palette.secondaryColor)
                        Text(beaufortDescription(knots))
                            .font(.vaneBody)
                            .foregroundStyle(palette.secondaryColor)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(
                    "Wind from the \(compassSpoken(degrees)), \(Int(knots.rounded())) knots. \(beaufortDescription(knots))"
                )
            } else {
                PanelUnavailable(
                    reason: "Wind is recorded from today forward.", palette: palette
                )
            }
        }
    }

    private func compass(_ degrees: Int) -> String {
        let points = ["N", "NNE", "NE", "ENE", "E", "ESE", "SE", "SSE",
                      "S", "SSW", "SW", "WSW", "W", "WNW", "NW", "NNW"]
        // 16 points, so each spans 22.5 degrees; the +11.25 offset centres the bucket on its
        // own bearing rather than starting at it.
        return points[Int(((Double(degrees) + 11.25) / 22.5).rounded(.down)) % 16]
    }

    private func compassSpoken(_ degrees: Int) -> String {
        let names = ["north", "north north-east", "north-east", "east north-east",
                     "east", "east south-east", "south-east", "south south-east",
                     "south", "south south-west", "south-west", "west south-west",
                     "west", "west north-west", "north-west", "north north-west"]
        return names[Int(((Double(degrees) + 11.25) / 22.5).rounded(.down)) % 16]
    }

    /// The Beaufort scale, by its actual knot boundaries.
    private func beaufort(_ knots: Double) -> Int {
        let limits: [Double] = [1, 3, 6, 10, 16, 21, 27, 33, 40, 47, 55, 63]
        return limits.firstIndex { knots < $0 } ?? 12
    }

    /// Beaufort's own descriptions are the reason the scale has outlived every attempt to
    /// replace it: they describe what you can see, not what an instrument reads.
    private func beaufortDescription(_ knots: Double) -> String {
        switch beaufort(knots) {
        case 0: "Smoke rises straight up."
        case 1: "Smoke drifts. Vanes do not turn."
        case 2: "Leaves rustle. You can feel it on your face."
        case 3: "Leaves and small twigs in constant motion."
        case 4: "Dust and loose paper lift. Small branches move."
        case 5: "Small trees sway."
        case 6: "Large branches move. Umbrellas are hard to use."
        case 7: "Whole trees in motion. Walking into it takes effort."
        case 8: "Twigs break off trees. Progress on foot is difficult."
        case 9: "Slates and chimney pots come off."
        case 10: "Trees uprooted. Considerable structural damage."
        case 11: "Widespread damage."
        default: "Devastation."
        }
    }
}

/// A wind rose, not an arrow in a circle.
///
/// Sixteen ticks with the cardinals lengthened, and the barb pointing the way the wind is
/// *going* — meteorological convention names the direction it comes from, which is why the barb
/// is drawn opposite the stated bearing and the label still says where it is from.
struct WindRose: View {
    let degrees: Int
    let knots: Double
    let palette: Palette

    var body: some View {
        Canvas { context, size in
            let centre = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = min(size.width, size.height) / 2 - 2

            for point in 0..<16 {
                let angle = Double(point) * 22.5 * .pi / 180 - .pi / 2
                let inner = radius * (point % 4 == 0 ? 0.74 : 0.87)
                context.stroke(
                    Path {
                        $0.move(to: .init(x: centre.x + cos(angle) * inner,
                                          y: centre.y + sin(angle) * inner))
                        $0.addLine(to: .init(x: centre.x + cos(angle) * radius,
                                             y: centre.y + sin(angle) * radius))
                    },
                    with: .color(palette.gridColor),
                    lineWidth: point % 4 == 0 ? 1 : 0.5
                )
            }

            // Coming *from* `degrees`, so it blows toward the opposite bearing.
            let heading = (Double(degrees) + 180) * .pi / 180 - .pi / 2
            let tip = CGPoint(x: centre.x + cos(heading) * radius * 0.66,
                              y: centre.y + sin(heading) * radius * 0.66)
            let tail = CGPoint(x: centre.x - cos(heading) * radius * 0.58,
                               y: centre.y - sin(heading) * radius * 0.58)

            context.stroke(Path { $0.move(to: tail); $0.addLine(to: tip) },
                           with: .color(palette.traceColor),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round))

            for side in [-1.0, 1.0] {
                let wing = heading + .pi + side * 0.42
                context.stroke(
                    Path {
                        $0.move(to: tip)
                        $0.addLine(to: .init(x: tip.x + cos(wing) * radius * 0.26,
                                             y: tip.y + sin(wing) * radius * 0.26))
                    },
                    with: .color(palette.traceColor),
                    style: StrokeStyle(lineWidth: 2, lineCap: .round)
                )
            }
        }
    }
}

// MARK: - Against normal

/// What the whole app is arguing, stated as a measurement rather than a sentence.
struct NormalPanel: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let mark: TimelineMark?
    let years: Int?
    let palette: Palette

    var body: some View {
        Panel(title: "AGAINST NORMAL", palette: palette) {
            if let mark, let normalHigh = mark.normalHighC, let anomaly = mark.anomaly,
               let shown = mark.displayAnomaly {
                VStack(alignment: .leading, spacing: 12) {
                    AnomalyBar(anomaly: anomaly, palette: palette)
                        .frame(height: 26)
                        .accessibilityHidden(true)

                    // Three across normally; stacked at accessibility sizes, where the labels
                    // are wider than a third of the screen and the columns overlapped.
                    let columns = typeSize.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                        : AnyLayout(HStackLayout(alignment: .top, spacing: 0))

                    columns {
                        column("THIS DAY", "\(Int(mark.highC.rounded()))°")
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        column("NORMAL", "\(Int(normalHigh.rounded()))°")
                        if !typeSize.isAccessibilitySize { Spacer(minLength: 8) }
                        // Derived from the two rounded readings beside it, so the row is
                        // arithmetically true as printed.
                        column("DIFFERENCE", "\(shown > 0 ? "+" : "")\(shown)°")
                    }
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(spoken(shown: shown, normal: normalHigh, high: mark.highC))
            } else {
                PanelUnavailable(
                    reason: "The normals for this place are still being worked out. They arrive once the archive has been read.",
                    palette: palette
                )
            }
        }
    }

    private func column(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(.vaneData).tracking(1.3)
                .foregroundStyle(palette.secondaryColor)
                .fixedSize(horizontal: false, vertical: true)
            // `relativeTo:` rather than a fixed size, so the figure scales with the label
            // instead of staying 20pt while its caption grows past it.
            Text(value).font(.custom(VaneFont.mono, size: 20, relativeTo: .title3))
                .foregroundStyle(palette.inkColor)
        }
    }

    private func spoken(shown: Int, normal: Double, high: Double) -> String {
        let base = "\(Int(high.rounded())) degrees against a normal of \(Int(normal.rounded()))"
        let years = years.map { " over \($0) years" } ?? ""
        if shown == 0 { return "\(base)\(years). Right on the mark." }
        return "\(base)\(years). \(abs(shown)) degrees \(shown > 0 ? "warmer" : "cooler") than usual."
    }
}

/// The anomaly as a signed bar from a centred zero, scaled to ±10°C.
///
/// ±10 is a fixed scale on purpose: a scale that fits the data would make every day's bar look
/// equally dramatic, which is the exact opposite of what a panel about how unusual a day is
/// should do. A one-degree day gets a short bar, and that is the information.
struct AnomalyBar: View {
    let anomaly: Double
    let palette: Palette

    var body: some View {
        Canvas { context, size in
            let centre = size.width / 2
            let extent = min(abs(anomaly) / 10, 1) * (size.width / 2)
            let midY = size.height / 2

            context.stroke(
                Path { $0.move(to: .init(x: 0, y: midY)); $0.addLine(to: .init(x: size.width, y: midY)) },
                with: .color(palette.gridColor), lineWidth: 0.5
            )
            context.stroke(
                Path { $0.move(to: .init(x: centre, y: 0)); $0.addLine(to: .init(x: centre, y: size.height)) },
                with: .color(palette.bandColor), lineWidth: 1
            )

            let rect = CGRect(
                x: anomaly >= 0 ? centre : centre - extent,
                y: midY - 5, width: max(extent, 1), height: 10
            )
            // The alert colour is the other half of the saturated budget and this is what it is
            // for: a day far enough from normal to be the reason someone opened the app.
            let far = abs(anomaly) >= 5
            context.fill(Path(rect), with: .color(far ? palette.alertColor : palette.traceColor))
        }
    }
}

// MARK: - The roll

/// The barograph chart, as a panel.
///
/// It was the main screen from GATE 2 until now. It is a good instrument and it was the wrong
/// hero: a first-time reader could take nothing from it at a glance, and its density was the
/// single largest reason the opening surface read as a document rather than as a moment. As a
/// panel it keeps every property that made it worth building — the unbroken trace, the normals
/// behind it, the ruling — for the people who scroll to it.
struct RollPanel: View {
    let marks: [TimelineMark]
    let scrub: Double
    let dayWidth: CGFloat
    let palette: Palette
    let timeZone: TimeZone
    let observedAt: Date

    var body: some View {
        Panel(title: "THE ROLL", palette: palette) {
            if marks.count < 2 {
                PanelUnavailable(
                    reason: "The roll fills in as the days pass. Vane keeps every day you open it.",
                    palette: palette
                )
            } else {
                RollCanvas(
                    marks: marks, scrub: scrub, dayWidth: dayWidth,
                    palette: palette, isDragging: false, entrance: 1,
                    timeZone: timeZone, observedAt: observedAt
                )
                .frame(height: 190)
            }
        }
    }
}

import SwiftUI
import VaneKit

/// The only screen most people will ever see.
public struct MainScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: WeatherModel
    @State private var contextVisible = false
    /// The chart expands to fill whatever the sheet leaves it, so the content needs to know how
    /// tall the sheet is. Inside a ScrollView `maxHeight: .infinity` alone means nothing.
    @State private var height: CGFloat = 0

    public init(model: WeatherModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        let sky = model.sky
        let palette = sky.palette

        GeometryReader { geometry in
        ZStack {
            palette.paperColor.ignoresSafeArea()

            if let snapshot = model.snapshot {
                // Scrolls only when it has to. At accessibility sizes the content grows taller
                // than the screen, and a ZStack centres overflow — which pushed the station
                // line up under the status bar and the streak dots off the bottom. At normal
                // sizes everything fits and `.basedOnSize` keeps it feeling like a fixed sheet
                // rather than a scrolling list.
                ScrollView {
                    content(snapshot, palette: palette)
                        .onAppear { LaunchMetrics.firstMeaningfulPaint() }
                }
                .scrollBounceBehavior(.basedOnSize)
            } else {
                EmptyStateView(screen: model.screen, palette: palette) {
                    Task { await model.refresh() }
                }
            }
        }
        .animation(VaneMotion.sky, value: palette)
        .onAppear { height = geometry.size.height }
        }
        .task {
            await model.refresh()
        }
        // Driven by the data, not by a flag set once. The previous version set `contextVisible`
        // only inside `.task`, so a cell that was cold on first fetch and warm on a later one
        // would keep its sentence hidden forever.
        .onChange(of: model.snapshot?.context) { _, context in
            contextVisible = context != nil
        }
    }

    private func content(_ snapshot: Snapshot, palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StationLine(snapshot: snapshot, place: model.placeName, palette: palette)

            Spacer().frame(height: 32)
            Reading(snapshot: snapshot, palette: palette)

            Spacer().frame(height: 6)
            ConditionLine(snapshot: snapshot, palette: palette)

            Spacer().frame(height: 14)
            // No reserved height. A cold cell has no sentence, and holding 76pt of empty paper
            // for one leaves a hole that reads as a rendering bug. When the sentence does
            // arrive it pushes into the sheet and the chart yields — which is the arrival
            // being visible, rather than something popping into a pre-cut slot.
            ContextLine(snapshot.context, palette: palette)

            Spacer().frame(height: 28)
            BarographTrace(
                points: snapshot.arc.map {
                    .init(hour: hour(of: $0.t, in: snapshot), value: $0.tempC,
                          precipMm: $0.precipMm)
                },
                normalHigh: snapshot.normal?.tmaxC,
                normalLow: snapshot.normal?.tminC,
                nowHour: hour(of: snapshot.observedAt, in: snapshot),
                palette: palette
            )
            // Flexible, not a fixed 200pt. The trace is the signature of this design and was
            // the smallest voice on the screen while a third of the paper sat empty below it.
            // A chart fills its sheet.
            .frame(minHeight: 200, maxHeight: .infinity)

            Spacer().frame(height: 24)
            Footer(snapshot: snapshot, palette: palette)

            Spacer().frame(height: 20)
            StreakBar(count: model.streak, palette: palette)
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .leading)
    }

    /// Hours since local midnight, in the *location's* own timezone — which the arc's own
    /// timestamps carry. Using the device calendar would put the pen in the wrong place for
    /// anyone looking at a city they are not standing in.
    private func hour(of date: Date, in snapshot: Snapshot) -> Double {
        // The arc begins at the location's own local midnight by construction, so hours since
        // its first point *is* the position on the day's axis — no calendar arithmetic needed,
        // and none that could pick up the device's zone by accident.
        guard let midnight = snapshot.arc.first?.t else { return 12 }
        return date.timeIntervalSince(midnight) / 3_600
    }
}

// MARK: - Pieces

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
            // The station timestamp is texture, not information — nobody reads it and VoiceOver
            // never announces it. At accessibility sizes it is the first thing to go, so the
            // place name keeps the whole width instead of both truncating into ellipses.
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

struct Reading: View {
    let snapshot: Snapshot
    let palette: Palette

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            RollingNumber(snapshot.current.tempC)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // The ring sits at the digits' cap height, not above them. A degree mark floating
            // clear of the number reads as a stray dot rather than as part of the reading.
            Text("°")
                .font(.custom(VaneFont.display, fixedSize: 46))
                .offset(y: 34)
                .accessibilityHidden(true)
        }
        .foregroundStyle(palette.inkColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(Int(snapshot.current.tempC.rounded())) degrees")
    }
}

/// What it is actually doing out, and what it feels like.
///
/// Sits directly under the reading and above the sentence, because that is the order of the
/// questions: how warm, what kind of day, and then — the part only this app answers — is that
/// unusual. Kept in the data face so it stays quieter than the sentence below it.
struct ConditionLine: View {
    let snapshot: Snapshot
    let palette: Palette

    var body: some View {
        Text(parts.joined(separator: "   ·   "))
            .font(.vaneData).tracking(1.3)
            .foregroundStyle(palette.inkColor.opacity(0.72))
            .accessibilityLabel(voiceOver)
    }

    private var parts: [String] {
        var parts: [String] = []
        let condition = snapshot.current.condition.label
        if !condition.isEmpty { parts.append(condition.uppercased()) }
        // Only when it disagrees with the reading by enough to change what someone wears.
        // Printing "feels like 20" next to 20 is noise dressed as data.
        if abs(snapshot.current.feelsC - snapshot.current.tempC) >= 2 {
            parts.append("FEELS \(Int(snapshot.current.feelsC.rounded()))°")
        }
        parts.append("\(snapshot.current.humidity)% RH")
        return parts
    }

    private var voiceOver: String {
        var summary = snapshot.current.condition.label
        if summary.isEmpty { summary = "Conditions" }
        if abs(snapshot.current.feelsC - snapshot.current.tempC) >= 2 {
            summary += ". Feels like \(Int(snapshot.current.feelsC.rounded())) degrees"
        }
        return summary + ". Humidity \(snapshot.current.humidity) percent."
    }
}

struct Footer: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let snapshot: Snapshot
    let palette: Palette

    var body: some View {
        // One row normally, stacked at accessibility sizes. Three truncated fragments
        // ("↑… ↓ 1… 285…") carry no information at all; three full lines do.
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 18))

        layout {
            Text("↑ \(time(snapshot.sun.sunrise))")
            Text("↓ \(time(snapshot.sun.sunset))")
            if !typeSize.isAccessibilitySize { Spacer() }
            Text("\(snapshot.current.windDeg)° \(Int(snapshot.current.windKt.rounded()))KT")
        }
        .font(.vaneData).tracking(1.2)
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(palette.inkColor.opacity(0.72))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            """
            Sunrise \(time(snapshot.sun.sunrise)). Sunset \(time(snapshot.sun.sunset)). \
            Wind \(Int(snapshot.current.windKt.rounded())) knots \
            from \(snapshot.current.windDeg) degrees.
            """
        )
    }

    /// 24-hour, in the location's own zone.
    ///
    /// `.hour(.twoDigits(amPM: .omitted))` renders 19:33 as "07:33" — a 12-hour clock with the
    /// half of the information that disambiguates it removed. On an instrument, that is not a
    /// formatting preference, it is a wrong number.
    private func time(_ date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = snapshot.timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }
}

/// Consecutive days opened, as a measured rule rather than seven dots.
///
/// Seven evenly spaced dots at the bottom of a screen is a `UIPageControl`, and people will try
/// to swipe it. A tick rule is the instrument's own vocabulary — a scale with a mark on it —
/// and cannot be mistaken for navigation.
struct StreakBar: View {
    let count: Int
    let palette: Palette

    private var weeks: Int { max(1, Int(ceil(Double(min(count, 28)) / 7))) }

    var body: some View {
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(0..<28, id: \.self) { index in
                Rectangle()
                    .fill(index < min(count, 28) ? palette.traceColor : palette.gridColor)
                    // Taller every seventh mark, the way a ruler marks its units. Gives the run
                    // a readable length without printing a number that would start to nag.
                    .frame(width: 1, height: index % 7 == 6 ? 9 : 5)
            }
            Spacer()
        }
        .frame(height: 9, alignment: .bottom)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(count == 1 ? "Opened today" : "Opened \(count) days in a row")
    }
}

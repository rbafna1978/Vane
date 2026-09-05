import SwiftUI
import VaneKit

/// The only screen most people will ever see.
public struct MainScreen: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var model: WeatherModel
    @State private var contextVisible = false

    public init(model: WeatherModel) {
        _model = State(initialValue: model)
    }

    public var body: some View {
        let sky = model.sky
        let palette = sky.palette

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
        .task {
            await model.refresh()
            // The entry moment: the sentence arrives a beat after the reading it explains.
            // Only when there is one to arrive, and only once.
            if model.snapshot?.context != nil { contextVisible = true }
        }
    }

    private func content(_ snapshot: Snapshot, palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            StationLine(snapshot: snapshot, place: model.placeName, palette: palette)

            Spacer().frame(height: 32)
            Reading(snapshot: snapshot, palette: palette)

            Spacer().frame(height: 8)
            ContextLine(contextVisible ? snapshot.context : nil, palette: palette)
                .frame(minHeight: 76, alignment: .topLeading)

            Spacer().frame(height: 28)
            BarographTrace(
                points: snapshot.arc.map {
                    .init(hour: hour(of: $0.t, in: snapshot), value: $0.tempC)
                },
                normalHigh: snapshot.normal?.tmaxC,
                normalLow: snapshot.normal?.tminC,
                nowHour: hour(of: snapshot.observedAt, in: snapshot),
                palette: palette
            )
            .frame(height: 200)

            Spacer().frame(height: 24)
            Footer(snapshot: snapshot, palette: palette)

            Spacer().frame(height: 20)
            StreakDots(count: model.streak, palette: palette)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
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

struct StreakDots: View {
    let count: Int
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<7, id: \.self) { index in
                Circle()
                    .fill(index < min(count, 7) ? palette.traceColor : palette.gridColor)
                    .frame(width: 5, height: 5)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            count == 1 ? "Opened today" : "Opened \(count) days in a row"
        )
    }
}

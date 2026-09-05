import SwiftUI
import VaneKit

/// The extended forecast, read against thirty years of record.
///
/// Every weather app has a seven-day list. What makes this one is the same thing that makes the
/// main screen: each day is shown against **its own calendar date's normal**, on a shared axis,
/// so a warm day sits visibly right of a cool one and a heat wave is a shape before it is a
/// number.
public struct DetailScreen: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.dismiss) private var dismiss
    let forecast: Forecast?
    let place: String?
    let palette: Palette
    let timeZone: TimeZone

    public init(forecast: Forecast?, place: String?, palette: Palette, timeZone: TimeZone) {
        self.forecast = forecast
        self.place = place
        self.palette = palette
        self.timeZone = timeZone
    }

    /// One axis for every row. Rows scaled individually would each look average.
    private var bounds: (low: Double, high: Double) {
        let days = forecast?.daily ?? []
        let values = days.flatMap { day -> [Double] in
            [day.tminC, day.tmaxC] + (day.normal.map { [$0.tminC, $0.tmaxC] } ?? [])
        }
        let low = (values.min() ?? 0) - 1
        let high = (values.max() ?? 1) + 1
        return (low, max(high, low + 1))
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                // The stock circular chrome button is glass and shadow dropped onto printed
                // paper. This is the same face as everything else on the sheet.
                Button { dismiss() } label: {
                    Text("← TODAY")
                        .font(.vaneData).tracking(1.4)
                        .foregroundStyle(palette.traceColor)
                        .frame(minWidth: 44, minHeight: 44, alignment: .leading)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Back to today")

                Spacer().frame(height: 10)
                Text((place ?? "Here").uppercased())
                    .font(.vaneData).tracking(1.4)
                    .foregroundStyle(palette.inkColor)

                Spacer().frame(height: 22)
                Text("NEXT \(forecast?.daily.count ?? 0) DAYS")
                    .font(.vaneData).tracking(1.4)
                    .foregroundStyle(palette.inkColor.opacity(0.55))

                Spacer().frame(height: 12)
                ForEach(Array((forecast?.daily ?? []).enumerated()), id: \.element.id) { index, day in
                    DayRow(
                        day: day, isToday: index == 0, bounds: bounds,
                        palette: palette, timeZone: timeZone
                    )
                    if day.id != forecast?.daily.last?.id {
                        Rectangle().fill(palette.gridColor.opacity(0.5)).frame(height: 0.5)
                    }
                }

                Spacer().frame(height: 18)
                Legend(palette: palette)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 24)
        }
        .background(palette.paperColor)
        // The package builds for macOS so its tests run without a simulator; the navigation
        // bar API is iOS-only.
        #if os(iOS)
        .navigationBarBackButtonHidden()
        .toolbar(.hidden, for: .navigationBar)
        #endif
    }
}

struct DayRow: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    let day: ForecastDay
    let isToday: Bool
    let bounds: (low: Double, high: Double)
    let palette: Palette
    let timeZone: TimeZone

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))

        layout {
            Text(label)
                .font(.vaneData).tracking(1.2)
                .foregroundStyle(palette.inkColor.opacity(isToday ? 1 : 0.72))
                .frame(width: typeSize.isAccessibilitySize ? nil : 66, alignment: .leading)

            RangeBar(day: day, bounds: bounds, palette: palette)
                .frame(height: 14)

            Text(temperatures)
                .font(.vaneData).tracking(1.2)
                .foregroundStyle(palette.inkColor)
                .frame(width: typeSize.isAccessibilitySize ? nil : 74, alignment: .trailing)
        }
        // 44pt even though rows are not yet tappable: the detail of a day is where tapping will
        // go, and a row that has to grow later is a row that gets re-laid-out later.
        .frame(minHeight: 44)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(voiceOver)
    }

    private var label: String {
        if isToday { return "TODAY" }
        var formatter = Date.FormatStyle(date: .abbreviated).locale(.current)
        formatter.timeZone = timeZone
        let weekday = day.d.formatted(.dateTime.weekday(.abbreviated).locale(.current))
        let dayNumber = Calendar.current.component(.day, from: day.d)
        return "\(weekday.uppercased()) \(dayNumber)"
    }

    private var temperatures: String {
        "\(Int(day.tminC.rounded()))°  \(Int(day.tmaxC.rounded()))°"
    }

    private var voiceOver: String {
        var summary = isToday ? "Today" : day.d.formatted(.dateTime.weekday(.wide).day().month(.wide))
        summary += ". High \(Int(day.tmaxC.rounded())), low \(Int(day.tminC.rounded()))."
        if let anomaly = day.highAnomaly, abs(anomaly) >= 1 {
            let direction = anomaly > 0 ? "above" : "below"
            summary += " \(Int(abs(anomaly).rounded())) degrees \(direction) the usual high for this date."
        }
        if let probability = day.precipProbability, probability > 0 {
            summary += " \(probability) percent chance of rain"
            summary += day.precipMm > 0
                ? String(format: ", %.1f millimetres.", day.precipMm) : "."
        }
        if !day.condition.label.isEmpty { summary += " \(day.condition.label)." }
        return summary
    }
}

/// The day's high-to-low range, drawn over its own 30-year normal range.
///
/// Where the solid bar sits relative to the light track *is* the reading — an unusually warm day
/// hangs off the right end of its own history, and you see that before you read a number.
struct RangeBar: View {
    let day: ForecastDay
    let bounds: (low: Double, high: Double)
    let palette: Palette

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                if let normal = day.normal {
                    Capsule()
                        .fill(palette.gridColor.opacity(0.55))
                        .frame(width: width(normal.tminC, normal.tmaxC, in: geometry.size.width,
                                            minimum: 2),
                               height: 12)
                        .offset(x: position(normal.tminC, in: geometry.size.width))
                }
                Capsule()
                    .fill(palette.traceColor)
                    .frame(width: width(day.tminC, day.tmaxC, in: geometry.size.width, minimum: 3),
                           height: 4)
                    .offset(x: position(day.tminC, in: geometry.size.width))
            }
            .frame(height: 14, alignment: .center)
        }
        .accessibilityHidden(true)
    }

    private func position(_ value: Double, in total: CGFloat) -> CGFloat {
        total * (value - bounds.low) / (bounds.high - bounds.low)
    }

    /// A minimum width so a day whose high and low barely differ still draws something. A
    /// zero-width capsule reads as missing data rather than as a still day.
    private func width(
        _ from: Double, _ to: Double, in total: CGFloat, minimum: CGFloat
    ) -> CGFloat {
        max(position(to, in: total) - position(from, in: total), minimum)
    }
}

struct Legend: View {
    let palette: Palette

    var body: some View {
        HStack(spacing: 8) {
            Capsule().fill(palette.gridColor.opacity(0.55)).frame(width: 22, height: 8)
            Text("30-YEAR NORMAL RANGE")
            Capsule().fill(palette.traceColor).frame(width: 22, height: 3)
            Text("FORECAST")
        }
        .font(.vaneData).tracking(1.1)
        .foregroundStyle(palette.inkColor.opacity(0.5))
        .accessibilityHidden(true)
    }
}

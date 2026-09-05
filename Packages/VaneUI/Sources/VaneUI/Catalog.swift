import SwiftUI
import VaneKit

/// The design system, on screen, so it can be judged rather than described.
///
/// No sliders. The day strip *is* the control — drag along it and the palette, the trace and
/// the reading all move together, because they are all functions of the same instant. iOS
/// slider chrome in the middle of a printed chart was borrowed furniture.
public struct Catalog: View {
    @State private var hour: Double = 13
    @State private var oktas: Int = 0
    @State private var contextIndex = 0

    private let samples: [WeatherContext?] = [
        WeatherContext(headline: "Warmest September 5th in 30 years.",
                       kind: .percentile, confidence: .high),
        WeatherContext(headline: "8 straight days cooler than normal.",
                       kind: .streak, confidence: .high),
        WeatherContext(headline: "47 days since it last rained here.",
                       kind: .since, confidence: .low),
        nil,
    ]

    /// METAR cloud cover, in eighths of sky. The real notation, because the brief asks for a
    /// visual language taken from meteorology's instruments rather than from a settings screen.
    private let coverage = [
        (0, "SKC", "clear"), (2, "FEW", "few"), (4, "SCT", "scattered"),
        (6, "BKN", "broken"), (8, "OVC", "overcast"),
    ]

    public init() {}

    private var cloud: Double { Double(oktas) / 8 }

    private var sky: SkyState { skyState(atHour: hour) }

    private func skyState(atHour hour: Double) -> SkyState {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 9, 5)
        components.hour = Int(hour)
        components.minute = Int((hour - hour.rounded(.down)) * 60)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        return SkyState.now(
            latitude: 37.8, longitude: -122.25,
            date: calendar.date(from: components) ?? .now, cloudCover: cloud
        )
    }

    /// A plausible day: coolest before dawn, peak in mid-afternoon.
    private var tracePoints: [BarographTrace.Point] {
        (0...48).map { step in
            let h = Double(step) / 2
            let phase = (h - 4) / 24 * 2 * .pi
            return .init(hour: h, value: 17.5 - 6.2 * cos(phase))
        }
    }

    private var reading: Double {
        tracePoints.min(by: { abs($0.hour - hour) < abs($1.hour - hour) })?.value ?? 0
    }

    public var body: some View {
        let state = sky
        let palette = state.palette

        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                header(state)
                dayStrip(palette)
                BarographTrace(
                    points: tracePoints, normalHigh: 25.7, normalLow: 14.4,
                    nowHour: hour, palette: palette
                )
                .frame(height: 190)
                coverageControl(palette)
                reading(palette)
                ContextLine(samples[contextIndex], palette: palette)
                    .frame(minHeight: 74, alignment: .topLeading)
                Button("Next context line") { contextIndex = (contextIndex + 1) % samples.count }
                    .font(.vaneBody)
                    .foregroundStyle(palette.traceColor)
                typeSpecimen(palette)
            }
            .padding(24)
        }
        .background(palette.paperColor)
        .animation(VaneMotion.sky, value: palette)
    }

    private func header(_ state: SkyState) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("VANE — DESIGN SYSTEM").font(.vaneData).tracking(1.4)
            Text(String(
                format: "%02d:%02d  %@  SUN %.1f°/%.0f°",
                Int(hour), Int((hour - hour.rounded(.down)) * 60),
                state.phase.label, state.elevation, state.azimuth
            ))
            .font(.vaneData).tracking(1.4).opacity(0.6)
        }
        .foregroundStyle(state.palette.inkColor)
    }

    /// Every hour of one day, side by side — and the scrubber.
    ///
    /// A ramp has to be judged as a ramp: seeing dawn, noon, dusk and midnight at once is what
    /// catches a muddy transition, which one instant behind a control never will.
    private func dayStrip(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("ONE DAY — 37.8N 122.25W  ·  DRAG TO SCRUB")
                .font(.vaneData).tracking(1.2).foregroundStyle(palette.inkColor.opacity(0.55))

            GeometryReader { geometry in
                HStack(spacing: 0) {
                    ForEach(0..<24, id: \.self) { h in
                        skyState(atHour: Double(h)).palette.paperColor
                    }
                }
                .overlay(alignment: .leading) {
                    // The pen tip again, at day scale: where in the day we are standing.
                    Rectangle()
                        .fill(palette.traceColor)
                        .frame(width: 2)
                        .offset(x: geometry.size.width * hour / 24)
                }
                .contentShape(.rect)
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { value in
                        hour = min(23.99, max(0, value.location.x / geometry.size.width * 24))
                    }
                )
            }
            .frame(height: 44)
            .clipShape(.rect(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2)
                .strokeBorder(palette.gridColor, lineWidth: 0.5))
        }
    }

    private func coverageControl(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("CLOUD  \(oktas)/8 OKTAS")
                .font(.vaneData).tracking(1.2).foregroundStyle(palette.inkColor.opacity(0.55))
            HStack(spacing: 0) {
                ForEach(coverage, id: \.0) { value, code, _ in
                    Button { oktas = value } label: {
                        Text(code)
                            .font(.vaneData).tracking(1.2)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 7)
                            .background(oktas == value ? palette.traceColor : .clear)
                            .foregroundStyle(oktas == value ? palette.paperColor : palette.inkColor)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(coverage.first { $0.0 == value }?.2 ?? code)
                }
            }
            .overlay(RoundedRectangle(cornerRadius: 2)
                .strokeBorder(palette.gridColor, lineWidth: 0.5))
            .clipShape(.rect(cornerRadius: 2))
        }
    }

    private func reading(_ palette: Palette) -> some View {
        RollingNumber(reading)
            .foregroundStyle(palette.inkColor)
            .accessibilityLabel("\(Int(reading.rounded())) degrees")
    }

    private func typeSpecimen(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Display L 40").font(.vaneDisplayLarge)
            Text("Context 28 — the sentence that carries the product").font(.vaneContext)
            Text("Body 17 — SF Pro Text, because Dynamic Type and VoiceOver come free with it.")
                .font(.vaneBody)
            Text("Caption 13 — secondary labels").font(.vaneCaption)
            Text("DATA 12 — KOAK 051756Z 28012KT").font(.vaneData).tracking(1.2)
        }
        .foregroundStyle(palette.inkColor)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview("Catalog") { Catalog() }

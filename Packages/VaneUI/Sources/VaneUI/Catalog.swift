import SwiftUI
import VaneKit

/// The design system, on screen, so it can be judged rather than described.
///
/// Time is a slider. That is the point: the palette is a function of where the sun is, and the
/// only way to know whether dusk reads correctly is to scrub through it and watch.
public struct Catalog: View {
    @State private var hour: Double = 13
    @State private var cloud: Double = 0
    @State private var temperature: Double = 21
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

    public init() {}

    private var sky: SkyState {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 9, 5)
        components.hour = Int(hour)
        components.minute = Int((hour - hour.rounded(.down)) * 60)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        return SkyState.now(
            latitude: 37.8, longitude: -122.25,
            date: calendar.date(from: components) ?? .now,
            cloudCover: cloud
        )
    }

    public var body: some View {
        let state = sky
        let palette = state.palette

        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header(state)
                dayStrip()
                grid(palette)
                reading(palette)
                ContextLine(samples[contextIndex], palette: palette)
                    .frame(minHeight: 80, alignment: .topLeading)
                controls(palette)
                typeSpecimen(palette)
            }
            .padding(24)
        }
        .background(palette.paperColor)
        .animation(VaneMotion.sky, value: palette)
    }

    private func header(_ state: SkyState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("VANE — DESIGN SYSTEM")
                .font(.vaneData)
                .tracking(1.4)
            Text(state.phase.rawValue.uppercased())
                .font(.vaneData)
                .tracking(1.4)
                .opacity(0.6)
            Text(String(format: "SUN %.1f° ELEV   %.0f° AZ", state.elevation, state.azimuth))
                .font(.vaneData)
                .tracking(1.4)
                .opacity(0.6)
        }
        .foregroundStyle(state.palette.inkColor)
    }

    /// Every hour of one day, side by side.
    ///
    /// A slider shows one instant; the ramp is the thing that has to be judged. Seeing dawn,
    /// noon, dusk and midnight at once is how you catch a muddy transition or a moment where
    /// the ink stops reading — which is exactly the failure the contrast guarantee exists for.
    private func dayStrip() -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("ONE DAY — 37.8N 122.25W").font(.vaneData).tracking(1.2)
                .foregroundStyle(sky.palette.inkColor)
            HStack(spacing: 0) {
                ForEach(0..<24, id: \.self) { hour in
                    let p = palette(atHour: Double(hour))
                    VStack(spacing: 0) {
                        ZStack {
                            p.paperColor
                            Rectangle().fill(p.traceColor)
                                .frame(height: 3).offset(y: 6)
                            Text("\(hour)")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundStyle(p.inkColor)
                                .offset(y: -8)
                        }
                    }
                    .frame(height: 46)
                }
            }
            .clipShape(.rect(cornerRadius: 2))
            .overlay(RoundedRectangle(cornerRadius: 2)
                .strokeBorder(sky.palette.gridColor, lineWidth: 0.5))
        }
        .accessibilityHidden(true)
    }

    private func palette(atHour hour: Double) -> Palette {
        var components = DateComponents()
        (components.year, components.month, components.day) = (2026, 9, 5)
        components.hour = Int(hour)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: -7 * 3600)!
        return SkyState.now(
            latitude: 37.8, longitude: -122.25,
            date: calendar.date(from: components) ?? .now, cloudCover: cloud
        ).palette
    }

    /// A stand-in for the trace: printed grid, dashed normal, one unbroken pen line.
    private func grid(_ palette: Palette) -> some View {
        Canvas { context, size in
            for row in 0...6 {
                let y = size.height * CGFloat(row) / 6
                context.stroke(
                    Path { $0.move(to: .init(x: 0, y: y)); $0.addLine(to: .init(x: size.width, y: y)) },
                    with: .color(palette.gridColor), lineWidth: 0.5
                )
            }
            let normalY = size.height * 0.42
            context.stroke(
                Path { $0.move(to: .init(x: 0, y: normalY))
                       $0.addLine(to: .init(x: size.width, y: normalY)) },
                with: .color(palette.gridColor),
                style: StrokeStyle(lineWidth: 1, dash: [4, 4])
            )
            var trace = Path()
            trace.move(to: .init(x: 0, y: size.height * 0.72))
            for step in 1...48 {
                let t = CGFloat(step) / 48
                let wave = sin(t * .pi) * 0.34 + sin(t * .pi * 3) * 0.03
                trace.addLine(to: .init(x: size.width * t, y: size.height * (0.74 - wave)))
            }
            context.stroke(trace, with: .color(palette.traceColor),
                           style: StrokeStyle(lineWidth: 1.75, lineCap: .round))
        }
        .frame(height: 150)
        .accessibilityHidden(true)
    }

    private func reading(_ palette: Palette) -> some View {
        RollingNumber(temperature)
            .foregroundStyle(palette.inkColor)
            .accessibilityLabel("\(Int(temperature)) degrees")
    }

    private func controls(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            labelled("TIME  \(String(format: "%02d:%02d", Int(hour), Int((hour - hour.rounded(.down)) * 60)))",
                     palette) { Slider(value: $hour, in: 0...23.99) }
            labelled("CLOUD  \(Int(cloud * 100))%", palette) { Slider(value: $cloud, in: 0...1) }
            labelled("READING  \(Int(temperature))°", palette) {
                Slider(value: $temperature, in: -20...45, step: 1)
            }
            Button("Next context line") {
                contextIndex = (contextIndex + 1) % samples.count
            }
            .font(.vaneBody)
            .foregroundStyle(palette.traceColor)
        }
        .tint(palette.traceColor)
    }

    private func labelled<C: View>(
        _ title: String, _ palette: Palette, @ViewBuilder control: () -> C
    ) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.vaneData).tracking(1.2).foregroundStyle(palette.inkColor)
            control()
        }
    }

    private func typeSpecimen(_ palette: Palette) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Display L 40").font(.vaneDisplayLarge)
            Text("Context 28 — the sentence that carries the product")
                .font(.vaneContext)
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

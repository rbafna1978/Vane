import SwiftUI
import VaneKit

/// The four colours the sky shader composites, plus the luminance floor it is guaranteed to
/// stay above.
///
/// This exists so no colour decision happens inside `Sky.metal`. The shader mixes; the mixing
/// inputs are derived here, in linear light, by the same `RGB` code that is already tested — and
/// the worst-case luminance comes out of the same derivation rather than being measured off a
/// rendered frame, which would be both slow and a frame late.
public nonisolated struct SkyScene: Sendable, Hashable {
    public let zenith: RGB
    public let horizon: RGB
    public let light: RGB
    public let cloud: RGB

    /// Sun/moon position in unit view space, y down. Off-frame values are legitimate: the sun
    /// is genuinely not in view for most of the day, and clamping it to the edge would park a
    /// fake sun in the corner.
    public let sunPoint: CGPoint

    public let elevation: Double
    public let cover: Double
    public let precip: Double
    /// Signed drift in view-widths per second. Wind from the west pushes cloud to the right.
    public let wind: Double

    /// The worst ground any text over the sky can land on.
    ///
    /// With a rendered scene the paper token is no longer what is behind the text, so contrast
    /// cannot be held against it. Cloud can cover any pixel and the gradient's own endpoints
    /// bound the rest; the luminary only ever lightens, so it cannot lower the floor. Taking the
    /// darkest of the three and holding ink against *that* is conservative in the right
    /// direction — it can only ever over-deliver contrast, never under-deliver it.
    public var worstGround: RGB {
        [zenith, horizon, cloud].min { $0.luminance < $1.luminance } ?? zenith
    }

    /// Ink that clears WCAG AA against the darkest the scene can be, for the text that sits
    /// over the sky rather than over paper.
    public func ink(_ palette: Palette) -> RGB {
        palette.ink.meetingContrast(4.5, against: worstGround)
    }

    /// - Parameters:
    ///   - windDeg: meteorological convention — the direction the wind is coming *from*.
    public static func from(
        sky: SkyState, cover: Double, precipMm: Double, windKt: Double, windDeg: Int
    ) -> SkyScene {
        let palette = sky.palette

        // The sky gets its own colour ramp rather than being mixed out of the paper tokens.
        //
        // That was the first attempt and it was wrong: eau-de-nil chart stock darkened toward
        // ink produces a grey-green wash that reads as fog at every hour of the day. Paper is
        // paper and sky is sky. What keeps the two in one world is the pull toward the paper's
        // own neutral at the end of this function — the sky is desaturated to sit beside the
        // chart, not tinted to pretend it is made of the same material.
        let elevation = sky.elevation

        // Three regimes, blended by elevation rather than switched: full day, the low-sun
        // hour, and night. Every boundary is a smoothstep, so nothing snaps.
        let day = smoothstep(2, 18, elevation)
        let golden = smoothstep(-8, 2, elevation) * (1 - smoothstep(2, 14, elevation))
        let night = 1 - smoothstep(-14, -2, elevation)

        // Deliberately below the saturation of a real photographed sky. The brief spends its
        // saturated budget on the trace and the alert, and a postcard blue behind a barograph
        // would take that budget back.
        let dayZenith = RGB(hex: 0x6E93B8)
        let dayHorizon = RGB(hex: 0xC3D2DA)
        let goldenZenith = RGB(hex: 0x7E7C9C)
        let goldenHorizon = RGB(hex: 0xE0B189)
        let nightZenith = RGB(hex: 0x0B1120)
        let nightHorizon = RGB(hex: 0x1D2634)

        // Weighted blend, normalised, so the three regimes always sum to one and no elevation
        // can produce an unlit gap between them.
        let total = max(day + golden + night, 0.001)
        func blend(_ d: RGB, _ g: RGB, _ n: RGB) -> RGB {
            d.mixed(with: g, amount: golden / max(day + golden, 0.001))
                .mixed(with: n, amount: night / total)
        }
        var zenith = blend(dayZenith, goldenZenith, nightZenith)
        var horizon = blend(dayHorizon, goldenHorizon, nightHorizon)

        // Overcast collapses the gradient toward a single grey. A solid deck genuinely has no
        // visible zenith-to-horizon falloff, and drawing one anyway is the tell that a sky is
        // decorative rather than derived.
        let flat = min(1, max(0, cover)) * 0.8
        let overcast = RGB(hex: 0x9BA5A8).mixed(with: palette.ink, amount: night * 0.75)
        zenith = zenith.mixed(with: overcast, amount: flat)
        horizon = horizon.mixed(with: overcast, amount: flat)

        // The pull that keeps sky and paper in one world.
        let muted = 0.22
        zenith = zenith.mixed(with: zenith.neutral, amount: muted)
        horizon = horizon.mixed(with: horizon.neutral, amount: muted)

        let daylight = smoothstep(-6, 6, elevation)
        let light = elevation > -0.833 ? RGB(hex: 0xFFEBC4) : RGB(hex: 0xE6EDF2)

        // Cloud is lit by whatever the sky is lit by, so it drains with the daylight instead of
        // staying a bright white deck after dark.
        let cloud = RGB(hex: 0xC8D0D3)
            .mixed(with: RGB(hex: 0x8E9BA3), amount: min(1, max(0, cover)) * 0.6)
            .mixed(with: palette.ink, amount: (1 - daylight) * 0.74)

        return SkyScene(
            zenith: zenith,
            horizon: horizon,
            light: light,
            cloud: cloud,
            sunPoint: viewPoint(azimuth: sky.azimuth, elevation: sky.elevation),
            elevation: sky.elevation,
            cover: min(1, max(0, cover)),
            // 4mm/h is a downpour. Above that the field stops getting denser and only the
            // sound would change, so the scale saturates there rather than filling the screen.
            precip: min(1, max(0, precipMm / 4.0)),
            wind: windDrift(knots: windKt, degrees: windDeg)
        )
    }

    /// Where the luminary sits in the frame.
    ///
    /// The frame is not a photograph of a compass direction. It has one fixed convention —
    /// **east is left, west is right** — which makes the sun travel left to right through the
    /// day everywhere on Earth, in the same direction as the roll's own time axis.
    ///
    /// The first version projected onto a plane facing the equator, which is physically what a
    /// viewer sees but produced a sun running right to left in the southern hemisphere: facing
    /// north from Sydney, the sun genuinely does rise on your right. Correct, and wrong for this
    /// interface — the chart under it reads left to right, and there is no horizon in the frame
    /// to contradict the simpler convention. This is a deliberate departure from the physical
    /// view, and the only one in the app.
    ///
    /// `sin(azimuth)` is the east-west component: +1 due east, 0 at the meridian, -1 due west.
    /// It is monotonic across the day in both hemispheres, which is exactly the property the
    /// equator-facing projection lacked, and it needs no latitude at all.
    static func viewPoint(azimuth: Double, elevation: Double) -> CGPoint {
        let east = sin(azimuth * .pi / 180)

        // Horizon at 78% down the frame: ground-side room for the instrument, and the sun still
        // climbs most of the height at midsummer noon.
        let horizonY = 0.78
        return CGPoint(
            x: 0.5 - 0.5 * east,
            y: horizonY - (elevation / 70) * horizonY
        )
    }

    /// How fast the cloud deck crosses the frame, signed.
    ///
    /// Wind direction is meteorological — the bearing it blows *from* — so the deck travels
    /// toward `degrees + 180`. In the frame's east-left convention, moving east is moving left,
    /// which makes the drift the negated eastward component of the travel direction:
    /// `-sin(degrees + 180)`, which is `sin(degrees)`. A westerly (270) therefore drifts left,
    /// because it is blowing toward the east.
    static func windDrift(knots: Double, degrees: Int) -> Double {
        let along = sin(Double(degrees) * .pi / 180)
        // 40kt across the frame in about four seconds: fast enough to read as a gale, slow
        // enough not to strobe at 30Hz. Saturated, so a hurricane does not tear the deck apart.
        return along * min(knots, 40) / 160
    }
}

/// The sky, rendered.
///
/// Ambient rather than interactive: nothing here responds to touch, and under our own rules
/// weather is content, not decoration. That is why the reduced-motion path is a still frame of
/// the same shader rather than a hidden view — removing the weather is not an accommodation.
public struct SkyView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let scene: SkyScene
    private let phaseLabel: String

    public init(scene: SkyScene, phaseLabel: String) {
        self.scene = scene
        self.phaseLabel = phaseLabel
    }

    public var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            TimelineView(.animation(minimumInterval: interval, paused: paused)) { timeline in
                let t = timeline.date.timeIntervalSinceReferenceDate

                Rectangle().colorEffect(
                    ShaderLibrary.bundle(.module).vaneSky(
                        .float2(size),
                        // Wrapped to a day. A float32 holding seconds since 2001 has lost so
                        // much mantissa by now that the noise field visibly quantises and the
                        // rain stops moving smoothly — the classic long-running-shader bug.
                        .float(paused ? 0 : t.truncatingRemainder(dividingBy: 86_400)),
                        .float2(scene.sunPoint),
                        .float(scene.elevation),
                        .float(scene.cover),
                        .float(scene.precip),
                        .float(scene.wind),
                        .color(scene.zenith.color),
                        .color(scene.horizon.color),
                        .color(scene.light.color),
                        .color(scene.cloud.color)
                    )
                )
            }
        }
        .ignoresSafeArea()
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
    }

    /// 30Hz for cloud drift, which moves a few pixels a second and is indistinguishable from
    /// 120 — and costs a quarter as much on a full-screen fragment pass. Rain has visible
    /// per-drop motion and gets 60. Neither is worth 120Hz on an ambient layer.
    private var interval: Double {
        switch ProcessInfo.processInfo.thermalState {
        case .serious, .critical: return 1
        default: return scene.precip > 0.001 ? 1.0 / 60 : 1.0 / 30
        }
    }

    private var paused: Bool {
        reduceMotion || ProcessInfo.processInfo.thermalState == .critical
    }

    private var accessibilityLabel: String {
        var parts = [phaseLabel.lowercased().capitalized]
        let oktas = Int((scene.cover * 8).rounded())
        parts.append(oktas == 0 ? "clear sky" : "\(oktas) eighths cloud")
        if scene.precip > 0.001 { parts.append("precipitation") }
        return parts.joined(separator: ", ")
    }
}

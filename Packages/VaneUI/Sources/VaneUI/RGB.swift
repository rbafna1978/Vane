import SwiftUI

/// A colour we can actually do arithmetic on.
///
/// SwiftUI's `Color` is opaque and cannot be interpolated, and the sky ramp is nothing but
/// interpolation, so the palette is computed here and converted at the last moment.
/// `nonisolated` inside a main-actor-by-default module: this is pure arithmetic, and the
/// widget extension needs to compute a palette without being dragged onto the main actor.
public nonisolated struct RGB: Sendable, Hashable {
    public var r: Double, g: Double, b: Double

    public init(_ r: Double, _ g: Double, _ b: Double) { (self.r, self.g, self.b) = (r, g, b) }

    public init(hex: UInt32) {
        self.init(
            Double((hex >> 16) & 0xFF) / 255,
            Double((hex >> 8) & 0xFF) / 255,
            Double(hex & 0xFF) / 255
        )
    }

    public var color: Color { Color(.sRGB, red: r, green: g, blue: b) }

    /// The same colour with its chroma removed, at matching luminance. What an overcast sky
    /// does to a scene: not darker, just less coloured.
    public var neutral: RGB {
        let grey = (max(r, g, b) + min(r, g, b)) / 2
        return RGB(grey, grey, grey)
    }

    /// WCAG relative luminance.
    public var luminance: Double {
        func lin(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
        return 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)
    }

    public func contrast(against other: RGB) -> Double {
        let (a, b) = (luminance, other.luminance)
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    /// Push this colour away from `background` until it meets `target` contrast, or until it
    /// runs out of room at black or white.
    ///
    /// Needed because the palette crossfades: paper travels light-to-dark across dusk while ink
    /// travels dark-to-light, and without this they pass each other and contrast collapses to
    /// about 1.5:1 — the interface becomes unreadable at precisely the hour someone is outside
    /// looking at the sky. Binary search rather than an analytic solve because the blend is in
    /// linear light and the inverse is not worth deriving for twenty cheap iterations.
    public func meetingContrast(_ target: Double, against background: RGB) -> RGB {
        guard contrast(against: background) < target else { return self }
        let away: RGB = background.luminance > 0.18 ? RGB(0, 0, 0) : RGB(1, 1, 1)

        var low = 0.0, high = 1.0
        for _ in 0..<20 {
            let mid = (low + high) / 2
            if mixed(with: away, amount: mid).contrast(against: background) < target {
                low = mid
            } else {
                high = mid
            }
        }
        return mixed(with: away, amount: high)
    }

    /// Blend in linear light, not in sRGB.
    ///
    /// sRGB values are gamma-encoded, so a straight average of two colours lands darker and
    /// muddier than the light physically would — the classic grey band halfway through a
    /// gradient. Undoing the transfer function, mixing, and re-applying it is what keeps
    /// twilight reading as light draining out of the sky rather than as a dimmer switch.
    public func mixed(with other: RGB, amount t: Double) -> RGB {
        let t = min(1, max(0, t))
        func toLinear(_ c: Double) -> Double {
            c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        func toGamma(_ c: Double) -> Double {
            c <= 0.0031308 ? c * 12.92 : 1.055 * pow(c, 1 / 2.4) - 0.055
        }
        func mix(_ a: Double, _ b: Double) -> Double {
            toGamma(toLinear(a) + (toLinear(b) - toLinear(a)) * t)
        }
        return RGB(mix(r, other.r), mix(g, other.g), mix(b, other.b))
    }
}

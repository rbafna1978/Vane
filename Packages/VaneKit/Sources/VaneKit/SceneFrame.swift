import Foundation

/// How real-world bearings map into the frame the scene is drawn in.
///
/// Kept from Direction A's sky when the rest of it was deleted, because it is not about skies:
/// it is the answer to "the sun is at azimuth 280° — where does that go on screen", and the
/// instrument scene asks exactly the same question for its lighting and for where the vane
/// points. It cost two bugs to get right and both were the kind that look fine until someone
/// opens the app in the wrong hemisphere.
///
/// **The frame has one convention: east is left, west is right.** The sun therefore travels left
/// to right through the day everywhere on Earth.
///
/// The first version projected onto a plane facing the equator, which is what a viewer physically
/// sees and produced a sun running *backwards* south of the equator — facing north from Sydney,
/// the sun genuinely does rise on your right. Correct, and wrong for an interface. This is a
/// deliberate departure from the physical view, and the only one in the app.
public enum SceneFrame {
    /// The east-west component of a bearing: +1 due east, 0 on the meridian, -1 due west.
    ///
    /// `sin` is the whole trick. It is monotonic across the day in both hemispheres, which the
    /// equator-facing projection was not, and it needs no latitude at all — so there is no
    /// hemisphere branch to get wrong.
    public static func eastWest(azimuth: Double) -> Double {
        sin(azimuth * .pi / 180)
    }

    /// Horizontal position in the frame, 0 (due east) to 1 (due west).
    public static func x(azimuth: Double) -> Double {
        0.5 - 0.5 * eastWest(azimuth: azimuth)
    }

    /// How fast something carried on the wind crosses the frame, signed.
    ///
    /// Wind direction is meteorological — the bearing it blows *from* — so anything it carries
    /// travels toward `degrees + 180`. Moving east is moving left in this frame, which makes the
    /// drift the negated eastward component of the travel direction: `-sin(degrees + 180)`, which
    /// is `sin(degrees)`. A westerly therefore drifts left, because it is blowing toward the east.
    ///
    /// - Parameter perSecond: frame widths per second at the saturation speed.
    public static func windDrift(knots: Double, degrees: Int, perSecond: Double = 0.25) -> Double {
        // Saturated at 40kt: a hurricane must not tear the scene apart, and above a gale the
        // extra speed is not legible anyway.
        sin(Double(degrees) * .pi / 180) * min(knots, 40) / 40 * perSecond
    }
}

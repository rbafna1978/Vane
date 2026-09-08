import Foundation
import Testing
import VaneKit
@testable import VaneUI

/// Each of these guards a defect that was on screen during this phase, not a hypothetical one.
@Suite("The rendered sky")
struct SkySceneTests {
    /// The frame fixes east on the left, so the sun runs left to right through the day
    /// everywhere. The equator-facing projection this replaced ran it backwards south of the
    /// equator, where the azimuth wrap falls in the middle of the day.
    @Test func `the sun crosses left to right in both hemispheres`() {
        // Northern: rises east (90), noon due south (180), sets west (270).
        let northMorning = SkyScene.viewPoint(azimuth: 100, elevation: 10)
        let northNoon = SkyScene.viewPoint(azimuth: 180, elevation: 60)
        let northEvening = SkyScene.viewPoint(azimuth: 260, elevation: 10)
        #expect(northMorning.x < northNoon.x)
        #expect(northNoon.x < northEvening.x)
        #expect(abs(northNoon.x - 0.5) < 0.001)

        // Southern: the sun passes through *north*, so azimuth runs 80 -> 0/360 -> 280. The
        // wrap through zero is exactly what broke the previous projection.
        let southMorning = SkyScene.viewPoint(azimuth: 80, elevation: 10)
        let southNoon = SkyScene.viewPoint(azimuth: 0, elevation: 60)
        let southEvening = SkyScene.viewPoint(azimuth: 280, elevation: 10)
        #expect(southMorning.x < southNoon.x)
        #expect(southNoon.x < southEvening.x)
        #expect(abs(southNoon.x - 0.5) < 0.001)

        // Due east is hard left, due west is hard right, in both hemispheres.
        #expect(abs(SkyScene.viewPoint(azimuth: 90, elevation: 0).x - 0.0) < 0.001)
        #expect(abs(SkyScene.viewPoint(azimuth: 270, elevation: 0).x - 1.0) < 0.001)
    }

    @Test func `the sun climbs as elevation rises`() {
        let low = SkyScene.viewPoint(azimuth: 180, elevation: 2)
        let high = SkyScene.viewPoint(azimuth: 180, elevation: 60)
        #expect(high.y < low.y)   // y is measured downward
        // The horizon sits where the sun sits at elevation zero.
        #expect(abs(SkyScene.viewPoint(azimuth: 180, elevation: 0).y - 0.78) < 0.001)
    }

    /// Wind direction is meteorological: the bearing it blows *from*. In the frame's east-left
    /// convention a westerly is blowing toward the east, which is leftward.
    @Test func `wind drifts cloud away from where it comes from`() {
        #expect(SkyScene.windDrift(knots: 20, degrees: 270) < 0)   // westerly -> toward east -> left
        #expect(SkyScene.windDrift(knots: 20, degrees: 90) > 0)    // easterly -> toward west -> right
        // Straight up or down the meridian barely moves the deck across the frame.
        #expect(abs(SkyScene.windDrift(knots: 20, degrees: 180)) < 0.001)
        #expect(abs(SkyScene.windDrift(knots: 20, degrees: 0)) < 0.001)
        #expect(SkyScene.windDrift(knots: 0, degrees: 270) == 0)
    }

    /// A gale must not accelerate without limit; at 30Hz an unclamped drift strobes.
    @Test func `drift saturates in a gale`() {
        #expect(SkyScene.windDrift(knots: 60, degrees: 270)
                == SkyScene.windDrift(knots: 140, degrees: 270))
    }

    /// With a rendered ground the paper token is no longer what sits behind the text, so ink
    /// has to be held against the scene. This is the guarantee the whole legibility story rests
    /// on and it is cheap to check across the whole day.
    @Test func `ink clears AA against the darkest the scene can be`() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/London")!

        for hour in 0..<24 {
            for cover in [0.0, 0.5, 1.0] {
                let date = calendar.date(
                    from: DateComponents(year: 2026, month: 9, day: 8, hour: hour)
                )!
                let sky = SkyState.now(
                    latitude: 51.5, longitude: -0.13, date: date, cloudCover: cover
                )
                let scene = SkyScene.from(
                    sky: sky, cover: cover, precipMm: 0, windKt: 10, windDeg: 270
                )
                let ink = scene.ink(sky.palette)
                #expect(
                    ink.contrast(against: scene.worstGround) >= 4.49,
                    "hour \(hour) cover \(cover)"
                )
            }
        }
    }

    @Test func `precipitation saturates at a downpour`() {
        let sky = SkyState.now(latitude: 51.5, longitude: -0.13)
        func scene(_ mm: Double) -> SkyScene {
            SkyScene.from(sky: sky, cover: 0.8, precipMm: mm, windKt: 10, windDeg: 270)
        }
        #expect(scene(0).precip == 0)
        #expect(scene(2).precip == 0.5)
        #expect(scene(4).precip == 1)
        #expect(scene(40).precip == 1)
    }
}

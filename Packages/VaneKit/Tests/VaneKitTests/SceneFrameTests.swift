import Foundation
import Testing
@testable import VaneKit

@Suite("Scene frame")
struct SceneFrameTests {
    /// The frame fixes east on the left, so the sun runs left to right through the day
    /// everywhere. The equator-facing projection this replaced ran it backwards south of the
    /// equator, where the azimuth wrap falls in the middle of the day.
    @Test func `the sun crosses left to right in both hemispheres`() {
        // Northern: rises east (90), noon due south (180), sets west (270).
        #expect(SceneFrame.x(azimuth: 100) < SceneFrame.x(azimuth: 180))
        #expect(SceneFrame.x(azimuth: 180) < SceneFrame.x(azimuth: 260))

        // Southern: the sun passes through *north*, so azimuth runs 80 -> 0/360 -> 280. That
        // wrap through zero is exactly what broke the previous projection.
        #expect(SceneFrame.x(azimuth: 80) < SceneFrame.x(azimuth: 0))
        #expect(SceneFrame.x(azimuth: 0) < SceneFrame.x(azimuth: 280))

        // Due east is hard left, due west hard right, the meridian dead centre.
        #expect(abs(SceneFrame.x(azimuth: 90) - 0) < 0.0001)
        #expect(abs(SceneFrame.x(azimuth: 270) - 1) < 0.0001)
        #expect(abs(SceneFrame.x(azimuth: 180) - 0.5) < 0.0001)
        #expect(abs(SceneFrame.x(azimuth: 0) - 0.5) < 0.0001)
    }

    /// Wind direction is the bearing it blows *from*. In an east-left frame a westerly is
    /// blowing toward the east, which is leftward.
    @Test func `wind drifts away from where it comes from`() {
        #expect(SceneFrame.windDrift(knots: 20, degrees: 270) < 0)  // westerly -> east -> left
        #expect(SceneFrame.windDrift(knots: 20, degrees: 90) > 0)   // easterly -> west -> right
        // Straight up or down the meridian barely crosses the frame at all.
        #expect(abs(SceneFrame.windDrift(knots: 20, degrees: 180)) < 0.0001)
        #expect(abs(SceneFrame.windDrift(knots: 20, degrees: 0)) < 0.0001)
        #expect(SceneFrame.windDrift(knots: 0, degrees: 270) == 0)
    }

    /// A gale must not accelerate without limit; an unclamped drift strobes at any frame rate.
    @Test func `drift saturates in a gale`() {
        #expect(SceneFrame.windDrift(knots: 60, degrees: 270)
                == SceneFrame.windDrift(knots: 140, degrees: 270))
    }
}

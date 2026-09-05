import SwiftUI

/// The motion vocabulary. Three curves, named, used everywhere — a design system with a dozen
/// ad-hoc durations is not a system.
///
/// Springs rather than eased durations on anything a finger can touch mid-flight, because a
/// duration-based animation cannot be retargeted without a visible seam. `bounce` stays low:
/// this is a printed instrument, and paper does not wobble.
public nonisolated enum VaneMotion {
    /// Data changing under you. Fast, no overshoot — a number that bounces reads as a slot
    /// machine rather than as a reading.
    public static let figure = Animation.smooth(duration: 0.28)

    /// Content entering. Ease-out, because an entrance should decelerate into place; ease-in
    /// on an entrance is the single most common motion mistake.
    public static let entrance = Animation.smooth(duration: 0.34)

    /// Anything under a finger, or released from one. Interruptible and retargetable.
    public static let gesture = Animation.spring(response: 0.42, dampingFraction: 0.82)

    /// The palette crossing dusk. Long, because the sun is not in a hurry, and because a
    /// visible colour step is worse than no transition at all.
    public static let sky = Animation.easeInOut(duration: 1.2)
}

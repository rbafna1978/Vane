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

    /// Content entering. `.smooth` is a zero-bounce spring, not an eased curve — it decelerates
    /// into place like an ease-out and stays retargetable, which an eased duration is not.
    /// 280ms keeps it inside the sub-300ms UI budget.
    public static let entrance = Animation.smooth(duration: 0.28)

    /// Anything under a finger, or released from one. Interruptible and retargetable.
    public static let gesture = Animation.spring(response: 0.42, dampingFraction: 0.82)

    /// The palette crossing dusk. Long, because the sun is not in a hurry and a visible colour
    /// step is worse than no transition.
    ///
    /// Only ever for time passing on its own. Never attach it to a value a finger is driving —
    /// at 1.2s the colour trails the gesture by more than a second and the control feels broken.
    public static let sky = Animation.easeInOut(duration: 1.2)
}

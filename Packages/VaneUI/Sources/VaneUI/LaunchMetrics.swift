import Foundation
import os

/// Cold launch to first meaningful paint. The brief's budget is 1.2s.
///
/// Measured from process start — `kinfo_proc` gives the kernel's own record of when the process
/// began, which includes dyld and everything before `main`. Timing from `init` instead would
/// quietly exclude the slowest part of a cold launch and report a number that flatters us.
@MainActor
public enum LaunchMetrics {
    private static let log = Logger(subsystem: "com.rishitbafna.vane", category: "launch")
    // MainActor-isolated rather than `nonisolated(unsafe)`: it is only ever touched from a
    // view's onAppear, so the isolation is real and the compiler can check it.
    private static var reported = false

    nonisolated public static func processStart() -> Date? {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        guard sysctl(&mib, 4, &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1e6)
    }

    /// Call when the first frame with real content is on screen. Only the first call counts —
    /// a later re-render is not a launch.
    public static func firstMeaningfulPaint() {
        guard !reported, let start = processStart() else { return }
        reported = true
        let elapsed = Date.now.timeIntervalSince(start)
        log.info("first meaningful paint: \(elapsed * 1000, format: .fixed(precision: 1))ms")
    }
}

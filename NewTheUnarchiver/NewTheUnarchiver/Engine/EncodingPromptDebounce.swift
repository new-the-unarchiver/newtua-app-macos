import Foundation

/// Decides whether an encoding-preview reopen should fire now, be skipped,
/// or scheduled for later. The actual reopen is the caller's job — this is a
/// pure value to keep timing tests locale- and clock-independent.
///
/// Contract:
/// - The first submit always runs (no baseline yet).
/// - Submitting the same value that was last resolved is skipped.
/// - A different value within `window` of the last resolved time is scheduled
///   for the remaining interval; outside the window it runs immediately.
struct EncodingPromptDebounce: Equatable {
    enum Decision: Equatable {
        case runNow
        case skipNoChange
        case scheduleAfter(TimeInterval)
    }

    let window: TimeInterval
    private var lastResolved: Resolved?

    private struct Resolved: Equatable {
        let encoding: String?
        let at: Date
    }

    init(window: TimeInterval) {
        self.window = window
    }

    func submit(_ encoding: String?, at now: Date) -> Decision {
        guard let last = lastResolved else { return .runNow }
        if last.encoding == encoding { return .skipNoChange }
        let elapsed = now.timeIntervalSince(last.at)
        if elapsed >= window { return .runNow }
        return .scheduleAfter(window - elapsed)
    }

    mutating func recordResolved(_ encoding: String?, at now: Date) {
        lastResolved = Resolved(encoding: encoding, at: now)
    }
}

import Foundation
import Newtua

/// Buffers progress ticks so the UI is updated at most `intervalHz` times per
/// second. The engine can fire callbacks far more often than SwiftUI can
/// usefully render — anything above ~24 Hz is wasted work.
///
/// Not thread-safe by itself: the caller (a serial DispatchQueue per job) is
/// expected to serialize `feed`/`flush` calls. `@unchecked Sendable` is the
/// asserted form of that contract — it lets the throttle be captured by the
/// engine's `@Sendable` progress closure without lockless cross-thread access.
nonisolated final class ProgressThrottle: @unchecked Sendable {
    private let interval: TimeInterval
    private let now: @Sendable () -> Date
    private var lastEmit: Date
    private var lastEmitted: Newtua.Progress?
    private var buffered: Newtua.Progress?

    init(intervalHz: Double = 24, now: @escaping @Sendable () -> Date = Date.init) {
        self.interval = 1.0 / intervalHz
        self.now = now
        self.lastEmit = .distantPast
    }

    /// Feed an incoming tick. Returns the snapshot to emit immediately, or nil
    /// if it should be buffered or coalesced.
    ///
    /// Coalescing rules:
    /// - `started`/`finished` ticks always emit — those are state changes the
    ///   UI must see.
    /// - Otherwise the tick is dropped when within `interval` of the last
    ///   emit, or when identical to the last emitted snapshot (a no-op for
    ///   `@Observable` observers).
    func feed(_ p: Newtua.Progress) -> Newtua.Progress? {
        if p.started || p.finished {
            return emit(p, at: now())
        }
        if p == lastEmitted {
            buffered = nil
            return nil
        }
        buffered = p
        let t = now()
        if t.timeIntervalSince(lastEmit) >= interval {
            return emit(p, at: t)
        }
        return nil
    }

    /// The latest buffered (un-emitted) tick, if any. Cleared after read.
    /// Use this at completion to flush a final snapshot to the UI.
    func flush() -> Newtua.Progress? {
        guard let p = buffered, p != lastEmitted else {
            buffered = nil
            return nil
        }
        return emit(p, at: now())
    }

    private func emit(_ p: Newtua.Progress, at t: Date) -> Newtua.Progress {
        lastEmit = t
        lastEmitted = p
        buffered = nil
        return p
    }
}

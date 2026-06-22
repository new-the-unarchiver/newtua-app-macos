import Foundation
import Newtua

/// Buffers progress ticks so the UI is updated at most `intervalHz` times per
/// second. The engine can fire callbacks far more often than SwiftUI can
/// usefully render — anything above ~24 Hz is wasted work.
///
/// Not thread-safe by itself: the caller (a serial DispatchQueue per job) is
/// expected to serialize `feed`/`flush` calls.
final class ProgressThrottle {
    private let interval: TimeInterval
    private let now: () -> Date
    private var lastEmit: Date
    private var lastEmitted: Newtua.Progress?
    private var buffered: Newtua.Progress?

    init(intervalHz: Double = 24, now: @escaping () -> Date = Date.init) {
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
            return emit(p)
        }
        if p == lastEmitted {
            buffered = nil
            return nil
        }
        buffered = p
        if now().timeIntervalSince(lastEmit) >= interval {
            return emit(p)
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
        return emit(p)
    }

    private func emit(_ p: Newtua.Progress) -> Newtua.Progress {
        lastEmit = now()
        lastEmitted = p
        buffered = nil
        return p
    }
}

import Foundation

/// State machine that drives the queue window's auto-hide behaviour.
/// The window stays open across a brief debounce window so an add/cancel
/// burst doesn't flash the window away.
@MainActor
final class QueueWindowVisibility {
    enum State: Equatable {
        case hidden
        case shown
        case pendingHide(deadline: Date)
    }

    private(set) var state: State = .hidden
    let hideDelay: TimeInterval

    init(hideDelay: TimeInterval = 0.3) {
        self.hideDelay = hideDelay
    }

    var shouldShow: Bool {
        switch state {
        case .hidden: false
        case .shown, .pendingHide: true
        }
    }

    /// Returns the deadline at which `tick(at:)` should run, or `nil` when
    /// no pending hide is scheduled.
    @discardableResult
    func observe(isEmpty: Bool, at now: Date) -> Date? {
        if !isEmpty {
            state = .shown
            return nil
        }
        switch state {
        case .hidden:
            return nil
        case .shown:
            let deadline = now.addingTimeInterval(hideDelay)
            state = .pendingHide(deadline: deadline)
            return deadline
        case .pendingHide(let deadline):
            return deadline
        }
    }

    @discardableResult
    func tick(at now: Date) -> Bool {
        if case .pendingHide(let deadline) = state, now >= deadline {
            state = .hidden
        }
        return shouldShow
    }
}

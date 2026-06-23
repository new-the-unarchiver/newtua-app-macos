import Foundation
import CoreServices

/// Adapter over Launch Services' per-UTI default handler. Read-only methods
/// are pure queries (no side effects); `setDefaultHandler` registers the
/// caller bundle as the default app for that UTI for the current user.
///
/// All methods are `@MainActor` because the only caller is the Archive
/// Formats Preferences tab, which lives on main. Launch Services itself is
/// thread-safe but we don't need the flexibility.
@MainActor
protocol FileAssociationsService: AnyObject {
    /// Bundle ID of the current default handler for `uti`, or `nil` if Launch
    /// Services hasn't registered one (e.g. unknown UTI on the system).
    func defaultHandler(forUTI uti: String) -> String?

    /// Make `bundleID` the default handler for `uti`. Idempotent — setting the
    /// same value the user already has is fine.
    func setDefaultHandler(_ bundleID: String, forUTI uti: String) throws
}

/// Concrete adapter that talks to Launch Services. Backed by the same
/// CoreServices API the original The Unarchiver used. No entitlements
/// required; works without App Sandbox.
@MainActor
final class LaunchServicesFileAssociations: FileAssociationsService {
    struct FailedToSet: Error, Equatable {
        let uti: String
        let status: OSStatus
    }

    func defaultHandler(forUTI uti: String) -> String? {
        LSCopyDefaultRoleHandlerForContentType(uti as CFString, .all)
            .map { $0.takeRetainedValue() as String }
    }

    func setDefaultHandler(_ bundleID: String, forUTI uti: String) throws {
        let status = LSSetDefaultRoleHandlerForContentType(
            uti as CFString,
            .all,
            bundleID as CFString
        )
        if status != noErr {
            throw FailedToSet(uti: uti, status: status)
        }
    }
}

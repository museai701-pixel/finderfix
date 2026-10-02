import Foundation

/// Shared "cut" state: the extension records cut items here, the container-background
/// "Paste" action (and the Paste hotkey) claims them here.
enum CutState {
    /// Cuts older than this are treated as expired.
    static let expiry: TimeInterval = 60 * 60 // 1 hour

    static func set(paths: [String]) {
        let defaults = AppGroup.defaults
        defaults?.set(paths, forKey: AppGroup.Keys.cutItemPaths)
        defaults?.set(Date(), forKey: AppGroup.Keys.cutClaimDate)
    }

    /// Returns the cut paths, or [] when there is no live cut.
    /// Does NOT clear — the Paste action clears after a successful move.
    static func claimedPaths() -> [String] {
        guard let defaults = AppGroup.defaults,
              let date = defaults.object(forKey: AppGroup.Keys.cutClaimDate) as? Date,
              Date().timeIntervalSince(date) < expiry,
              let paths = defaults.stringArray(forKey: AppGroup.Keys.cutItemPaths),
              !paths.isEmpty else {
            return []
        }
        return paths
    }

    static func clear() {
        AppGroup.defaults?.removeObject(forKey: AppGroup.Keys.cutItemPaths)
        AppGroup.defaults?.removeObject(forKey: AppGroup.Keys.cutClaimDate)
    }

    static var hasLiveCut: Bool { !claimedPaths().isEmpty }
}

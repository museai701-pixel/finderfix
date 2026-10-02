import Foundation

/// AppleScript bridge to Finder.
///
/// Requires the `com.apple.security.automation.apple-events` entitlement and the
/// `NSAppleEventsUsageDescription` string. macOS prompts the user for Automation
/// consent on first use; if consent is denied, every call below returns nil/false
/// gracefully — the app never crashes and the UI falls back to guide modes.
///
/// All calls must run on the main thread (NSAppleScript is not thread-safe).
/// Callers in this app (AppDelegate, HotKeyManager, SwiftUI actions) are all main-thread.
enum FinderBridge {

    // MARK: - Private runner

    /// Runs `source` and returns the result descriptor, or nil on any error
    /// (denied consent, Finder busy, script error…).
    private static func run(_ source: String) -> NSAppleEventDescriptor? {
        var errorInfo: NSDictionary?
        guard let script = NSAppleScript(source: source) else { return nil }
        let result = script.executeAndReturnError(&errorInfo)
        if errorInfo != nil {
            return nil
        }
        return result
    }

    // MARK: - Selection & target

    /// POSIX paths of the current Finder selection, via `selection as alias list`.
    /// Returns [] when nothing is selected or Finder can't be reached.
    static func frontmostFinderSelectionURLs() -> [URL] {
        let source = """
        tell application "Finder"
            if (count of selection) = 0 then return ""
            set thePaths to {}
            repeat with anItem in (get selection)
                set end of thePaths to POSIX path of (anItem as alias)
            end repeat
            set AppleScript's text item delimiters to linefeed
            return thePaths as text
        end tell
        """
        guard let text = run(source)?.stringValue, !text.isEmpty else { return [] }
        return text
            .components(separatedBy: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { URL(fileURLWithPath: $0) }
    }

    /// POSIX path of the frontmost Finder window's target folder.
    /// Returns nil when no Finder window is open or Finder can't be reached.
    static func frontmostFinderTargetURL() -> URL? {
        let source = """
        tell application "Finder"
            if (count of Finder windows) = 0 then return ""
            return POSIX path of (target of front Finder window as alias)
        end tell
        """
        guard let text = run(source)?.stringValue else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(fileURLWithPath: trimmed)
    }

    // MARK: - Hidden files

    /// Toggles Finder's `AppleShowAllFiles` default.
    ///
    /// Sandbox reality: a sandboxed app cannot write another app's preferences
    /// directly, so the write goes *through Finder itself* via Apple Events
    /// (`tell application "Finder" to do shell script ...`). Telling Finder to
    /// quit relaunches it automatically, applying the change.
    ///
    /// - Returns: true if the toggle was sent; false on any failure (including
    ///   denied Automation consent) — callers must show the manual fallback.
    @discardableResult
    static func toggleHiddenFiles() -> Bool {
        let source = """
        tell application "Finder"
            set isShowing to do shell script "defaults read com.apple.finder AppleShowAllFiles 2>/dev/null || echo 0"
            if isShowing starts with "1" or isShowing starts with "true" then
                do shell script "defaults write com.apple.finder AppleShowAllFiles -bool false"
            else
                do shell script "defaults write com.apple.finder AppleShowAllFiles -bool true"
            end if
            quit
        end tell
        """
        guard run(source) != nil else {
            NSLog("[FinderFix] toggleHiddenFiles failed (automation denied or Finder unreachable)")
            return false
        }
        return true
    }
}

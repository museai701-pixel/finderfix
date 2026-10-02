import AppKit
import Carbon
import Combine

// MARK: - Model

/// The three Finder-scoped actions driven by global hotkeys.
enum HotKeyAction: String, CaseIterable, Identifiable {
    case cut
    case paste
    case newFile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .cut: return "Cut files"
        case .paste: return "Paste (move here)"
        case .newFile: return "New file here"
        }
    }

    /// Carbon EventHotKeyID. Must be unique within our 'FFix' signature.
    /// Nonisolated: pure computation, read from the nonisolated Carbon procs.
    nonisolated var hotKeyID: Int {
        switch self {
        case .cut: return 1
        case .paste: return 2
        case .newFile: return 3
        }
    }

    nonisolated var keyCode: UInt32 {
        switch self {
        case .cut: return UInt32(kVK_ANSI_X)
        case .paste: return UInt32(kVK_ANSI_V)
        case .newFile: return UInt32(kVK_ANSI_N)
        }
    }

    nonisolated var defaultsKey: String { "ff.hotkey.modifiers." + rawValue }

    nonisolated var defaultModifiers: UInt32 { UInt32(controlKey) | UInt32(cmdKey) }
}

/// Modifier presets offered in Settings. No free-form recorder: presets are
/// robust, localizable, and can't collide with typing.
struct HotKeyPreset: Identifiable, Hashable {
    let name: String
    let modifiers: UInt32
    var id: String { name }

    nonisolated static let all: [HotKeyPreset] = [
        HotKeyPreset(name: "⌃⌘", modifiers: UInt32(controlKey) | UInt32(cmdKey)),
        HotKeyPreset(name: "⌥⌘", modifiers: UInt32(optionKey) | UInt32(cmdKey)),
        HotKeyPreset(name: "⇧⌃⌘", modifiers: UInt32(shiftKey) | UInt32(controlKey) | UInt32(cmdKey)),
        HotKeyPreset(name: "⌃⌥⌘", modifiers: UInt32(controlKey) | UInt32(optionKey) | UInt32(cmdKey)),
    ]
}

private nonisolated func fourCC(_ string: String) -> FourCharCode {
    let bytes = Array(string.utf8.prefix(4))
        + Array(repeating: UInt8(0), count: max(0, 4 - string.utf8.count))
    return (UInt32(bytes[0]) << 24) | (UInt32(bytes[1]) << 16)
        | (UInt32(bytes[2]) << 8) | UInt32(bytes[3])
}

/// Carbon hot-key event proc. Runs on the main event loop; forwards to the
/// singleton on the main queue. Nonisolated: Carbon requires a plain C function
/// pointer, which cannot carry actor isolation.
private nonisolated func hotKeyEventProc(
    _ nextHandler: EventHandlerCallRef?,
    _ event: EventRef?,
    _ userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return noErr }
    var hotKeyID = EventHotKeyID()
    let status = withUnsafeMutablePointer(to: &hotKeyID) { ptr in
        GetEventParameter(
            event,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            ptr
        )
    }
    guard status == noErr else { return noErr }
    let id = Int(hotKeyID.id)
    // Carbon delivers hot-key events on the main event loop, but hop to the
    // main actor explicitly — the manager is @MainActor in Swift 6 mode.
    Task { @MainActor in
        HotKeyManager.shared.receivedHotKey(id: id)
    }
    return noErr
}

// MARK: - Manager

/// Global hotkeys via Carbon RegisterEventHotKey.
///
/// Why Carbon: it is NOT deprecated for this purpose — Apple never shipped a
/// modern replacement for registering global hotkeys, and it works fully
/// sandboxed with no permission dialogs (this is what KeyboardShortcuts,
/// Dato, Lungo and others ship).
///
/// Safe defaults (deliberately NOT bare ⌘X/⌘V/⌘N, which belong to Finder and
/// text editing): ⌃⌘X cut, ⌃⌘V paste, ⌃⌘N new file. Each fires only while
/// Finder is the frontmost app.
///
/// ── OPTIONAL PRO PATH (Developer ID distribution only, NOT implemented) ──
/// A true system-wide ⌘X-for-files hijack (like Taurine/Command X) needs a
/// CGEventTap that rewrites ⌘X→⌘C / ⌘V→⌥⌘V in place while Finder is frontmost,
/// plus an AX probe to leave text fields alone. That tap requires Accessibility
/// trust, which sandboxed App Store apps can never obtain (AXIsProcessTrusted
/// always returns false in the sandbox). Keep this app on the App Store path.
/// ──────────────────────────────────────────────────────────────────────────
@MainActor
final class HotKeyManager: ObservableObject {

    static let shared = HotKeyManager()

    /// Selected preset index per action (keyed by `HotKeyAction.rawValue`).
    /// Drives the Settings pickers; any change re-registers the hotkeys.
    /// (@MainActor keeps @Published mutation checking clean in Swift 6.)
    @Published var presetSelections: [String: Int] = [:]

    nonisolated private static let signature: FourCharCode = fourCC("FFix")

    // Carbon refs are touched from deinit (nonisolated), so they opt out of
    // actor isolation. All mutation still happens on the main thread in practice.
    nonisolated(unsafe) private var eventHandler: EventHandlerRef?
    nonisolated(unsafe) private var hotKeyRefs: [EventHotKeyRef?] = []

    private init() {
        for action in HotKeyAction.allCases {
            presetSelections[action.rawValue] = indexOfPreset(matching: storedModifiers(for: action))
        }
    }

    // MARK: - Lifecycle

    func start() {
        installHandlerOnce()
        reregister()
    }

    func stop() {
        unregisterAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }

    deinit {
        unregisterAll()
        if let handler = eventHandler {
            RemoveEventHandler(handler)
        }
    }

    // MARK: - Settings binding

    func presetIndex(for action: HotKeyAction) -> Int {
        presetSelections[action.rawValue] ?? 0
    }

    func setPreset(_ index: Int, for action: HotKeyAction) {
        guard HotKeyPreset.all.indices.contains(index) else { return }
        presetSelections[action.rawValue] = index
        UserDefaults.standard.set(
            Int64(HotKeyPreset.all[index].modifiers),
            forKey: action.defaultsKey
        )
        reregister()
    }

    // MARK: - Carbon plumbing (nonisolated: only touches nonisolated(unsafe)
    // storage, UserDefaults, and NSLog — safe to call from deinit)

    nonisolated private func installHandlerOnce() {
        guard eventHandler == nil else { return }
        var spec = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )
        var handlerRef: EventHandlerRef?
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            hotKeyEventProc,
            1,
            &spec,
            nil,
            &handlerRef
        )
        if status == noErr {
            eventHandler = handlerRef
        } else {
            NSLog("[FinderFix] InstallEventHandler failed: %d", status)
        }
    }

    nonisolated private func reregister() {
        unregisterAll()
        for action in HotKeyAction.allCases {
            let hotKeyID = EventHotKeyID(
                signature: Self.signature,
                id: UInt32(action.hotKeyID)
            )
            var ref: EventHotKeyRef?
            let status = RegisterEventHotKey(
                action.keyCode,
                modifiers(for: action),
                hotKeyID,
                GetEventDispatcherTarget(),
                0,
                &ref
            )
            if status == noErr {
                hotKeyRefs.append(ref)
            } else {
                NSLog("[FinderFix] RegisterEventHotKey failed for %@: %d", action.rawValue, status)
            }
        }
    }

    nonisolated private func unregisterAll() {
        for ref in hotKeyRefs {
            if let ref {
                UnregisterEventHotKey(ref)
            }
        }
        hotKeyRefs.removeAll()
    }

    nonisolated private func modifiers(for action: HotKeyAction) -> UInt32 {
        storedModifiers(for: action)
    }

    nonisolated private func storedModifiers(for action: HotKeyAction) -> UInt32 {
        if UserDefaults.standard.object(forKey: action.defaultsKey) != nil {
            let stored = UserDefaults.standard.integer(forKey: action.defaultsKey)
            return UInt32(truncatingIfNeeded: stored)
        }
        return action.defaultModifiers
    }

    nonisolated private func indexOfPreset(matching modifiers: UInt32) -> Int {
        HotKeyPreset.all.firstIndex(where: { $0.modifiers == modifiers }) ?? 0
    }

    // MARK: - Dispatch

    /// Called on the main queue from the Carbon event proc.
    func receivedHotKey(id: Int) {
        // Hotkeys act only when Finder is frontmost — never steal keystrokes
        // from other apps.
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.apple.finder" else {
            return
        }
        guard let action = HotKeyAction.allCases.first(where: { $0.hotKeyID == id }) else {
            return
        }
        switch action {
        case .cut: cutSelection()
        case .paste: pasteCutItems()
        case .newFile: newFileHere()
        }
    }

    // MARK: - Actions

    /// ⌃⌘X — record Finder's current selection as the pending cut.
    private func cutSelection() {
        let urls = FinderBridge.frontmostFinderSelectionURLs()
        guard !urls.isEmpty else { return }
        CutState.set(paths: urls.map(\.path))
        NSLog("[FinderFix] cut %d item(s)", urls.count)
    }

    /// ⌃⌘V — move the pending cut items into the frontmost Finder window's folder.
    private func pasteCutItems() {
        let paths = CutState.claimedPaths()
        guard !paths.isEmpty else { return }
        guard let target = FinderBridge.frontmostFinderTargetURL() else { return }

        // The move needs a security-scoped bookmark for the destination folder.
        guard let scopedRoot = BookmarkStore.scopedRoot(containing: target) else {
            // No access yet — guide the user to grant it instead of failing silently.
            OnboardingWindow.show(initialStep: 1)
            return
        }
        defer { scopedRoot.stopAccessingSecurityScopedResource() }

        do {
            let moved = try FileOperations.moveItems(
                paths.map { URL(fileURLWithPath: $0) },
                to: target
            )
            CutState.clear()
            NSLog("[FinderFix] pasted %d item(s) to %@", moved.count, target.path)
        } catch {
            // Don't leave a zombie cut behind; report and clear.
            NSLog("[FinderFix] paste failed: %@", String(describing: error))
            CutState.clear()
        }
    }

    /// ⌃⌘N — create a new file from the default template in the frontmost
    /// Finder window's folder.
    private func newFileHere() {
        guard let target = FinderBridge.frontmostFinderTargetURL() else { return }
        guard let scopedRoot = BookmarkStore.scopedRoot(containing: target) else {
            OnboardingWindow.show(initialStep: 1)
            return
        }
        defer { scopedRoot.stopAccessingSecurityScopedResource() }

        guard let template = Templates.all().first else { return }
        let url = FileOperations.uniqueURL(
            in: target,
            baseName: template.name,
            pathExtension: template.ext
        )
        do {
            try FileOperations.createFile(at: url, contents: Data(template.content.utf8))
            NSLog("[FinderFix] created %@", url.path)
            // Best-effort: reveal the new file in Finder. Never fatal if it fails.
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            NSLog("[FinderFix] new-file failed: %@", String(describing: error))
        }
    }
}

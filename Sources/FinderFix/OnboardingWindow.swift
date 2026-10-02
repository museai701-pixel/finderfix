import AppKit
import SwiftUI

/// First-launch onboarding: a 2-step window.
///
/// Step 0 — enable the Finder Sync extension (written guide).
/// Step 1 — grant folder access (NSOpenPanel; never inside the extension).
///
/// Also reused as the "guide window": the menu-bar items and the hidden-files
/// fallback open it at a specific step instead of failing silently.
enum OnboardingWindow {
    private static var window: NSWindow?

    static func show(initialStep: Int = 0, showHiddenFilesHelp: Bool = false) {
        if let existing = window {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingView(
            initialStep: min(max(initialStep, 0), 1),
            showHiddenFilesHelp: showHiddenFilesHelp,
            onDone: { close() }
        )
        let hosting = NSHostingController(rootView: view)
        let window = NSWindow(contentViewController: hosting)
        window.title = "Welcome to FinderFix"
        window.styleMask = [.titled, .closable]
        window.setContentSize(NSSize(width: 540, height: 460))
        window.center()
        window.isReleasedWhenClosed = false
        self.window = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func close() {
        window?.close()
        window = nil
    }
}

private struct OnboardingView: View {
    @State private var step: Int
    private let showHiddenFilesHelp: Bool
    private let onDone: () -> Void

    @State private var grantedCount = 0

    init(initialStep: Int, showHiddenFilesHelp: Bool, onDone: @escaping () -> Void) {
        _step = State(initialValue: initialStep)
        self.showHiddenFilesHelp = showHiddenFilesHelp
        self.onDone = onDone
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Progress header.
            HStack(spacing: 8) {
                stepDot(index: 0, title: "Enable extension")
                stepDot(index: 1, title: "Grant folder access")
            }

            Divider()

            if step == 0 {
                extensionStep
            } else {
                foldersStep
            }

            Spacer()

            // Footer navigation.
            HStack {
                Spacer()
                if step == 0 {
                    Button("Continue") { step = 1 }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("Done") { onDone() }
                        .buttonStyle(.borderedProminent)
                        .disabled(BookmarkStore.bookmarkedPaths().isEmpty && grantedCount == 0)
                }
            }
        }
        .padding(24)
        .frame(width: 540, height: 460)
    }

    private func stepDot(index: Int, title: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(index == step ? Color.accentColor : Color.secondary.opacity(0.3))
                .frame(width: 10, height: 10)
            Text(title)
                .font(.callout)
                .foregroundStyle(index == step ? .primary : .secondary)
        }
    }

    // MARK: - Step 0: extension guide

    private var extensionStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Enable the Finder extension")
                .font(.title2)
                .fontWeight(.semibold)
            Text("FinderFix's right-click menu lives inside Finder. Turn it on once:")
                .font(.callout)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                guideRow(1, "Open System Settings → General → Login Items & Extensions.")
                guideRow(2, "Under Extensions, click ⓘ, open the “Finder” section.")
                guideRow(3, "Turn on FinderFix, then right-click any file in Finder.")
            }
            .font(.callout)

            Button("Open System Settings") {
                // Settings root only — deeper pane URLs are undocumented.
                if let url = URL(string: "x-apple.systempreferences:") {
                    NSWorkspace.shared.open(url)
                }
            }

            if showHiddenFilesHelp {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Hidden-files toggle needs help")
                        .font(.headline)
                    Text("The automatic toggle couldn't reach Finder. Grant Automation permission: System Settings → Privacy & Security → Automation → FinderFix → enable “Finder”. Or run in Terminal:")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                    Text("defaults write com.apple.finder AppleShowAllFiles -bool true; killall Finder")
                        .font(.callout.monospaced())
                        .textSelection(.enabled)
                        .padding(8)
                        .background(.quaternary)
                        .cornerRadius(6)
                }
            }
        }
    }

    private func guideRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).").fontWeight(.semibold).frame(width: 20, alignment: .trailing)
            Text(text)
        }
    }

    // MARK: - Step 1: folder grant

    private var foldersStep: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Grant folder access")
                .font(.title2)
                .fontWeight(.semibold)
            Text("macOS only lets FinderFix work inside folders you choose. Pick your usual working folders (Desktop, Documents, Downloads…). You can add or remove folders later in Settings.")
                .font(.callout)
                .foregroundStyle(.secondary)

            Button("Choose Folders…") {
                let panel = NSOpenPanel()
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                panel.allowsMultipleSelection = true
                panel.canCreateDirectories = false
                panel.prompt = "Grant Access"
                guard panel.runModal() == .OK else { return }
                for url in panel.urls {
                    if BookmarkStore.saveBookmark(for: url) {
                        grantedCount += 1
                    }
                }
                // Wake the Finder Sync extension so it watches the new folders.
                DistributedNotificationCenter.default().post(
                    name: AppGroup.foldersChangedNotification,
                    object: nil
                )
            }
            .buttonStyle(.borderedProminent)

            if grantedCount > 0 {
                Label("\(grantedCount) folder\(grantedCount == 1 ? "" : "s") granted", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .font(.callout)
            } else {
                Text("No folders granted yet — FinderFix can't create or move files until you grant at least one.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

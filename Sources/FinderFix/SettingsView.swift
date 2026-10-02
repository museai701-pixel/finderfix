import AppKit
import SwiftUI

/// FinderFix Settings window, hosted by AppDelegate in a plain NSWindow.
struct SettingsView: View {
    @ObservedObject private var hotKeys = HotKeyManager.shared

    @State private var folders: [String] = BookmarkStore.bookmarkedPaths()
    @State private var customTemplates: [FileTemplate] = Templates.custom()
    @State private var hiddenFilesMessage: String?
    @State private var showHiddenFilesManual = false

    var body: some View {
        TabView {
            extensionTab
                .tabItem { Label("Extension", systemImage: "puzzlepiece.extension") }
            foldersTab
                .tabItem { Label("Folders", systemImage: "folder") }
            hotkeysTab
                .tabItem { Label("Hotkeys", systemImage: "keyboard") }
            templatesTab
                .tabItem { Label("Templates", systemImage: "doc.badge.plus") }
            hiddenFilesTab
                .tabItem { Label("Hidden Files", systemImage: "eye.slash") }
        }
        .frame(width: 560, height: 520)
        .padding()
    }

    // MARK: - (a) Extension

    private var extensionTab: some View {
        Form {
            Section("Enable the Finder extension") {
                Text("FinderFix's right-click menu lives in a Finder Sync extension. Turn it on once:")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    stepRow(1, "Open System Settings.")
                    stepRow(2, "Go to General → Login Items & Extensions.")
                    stepRow(3, "Under Extensions, click the ⓘ button, then open the “Finder” section.")
                    stepRow(4, "Turn on FinderFix.")
                    stepRow(5, "Right-click any file or folder in Finder — the FinderFix menu appears.")
                }
                .padding(.vertical, 4)
                Button("Open System Settings") {
                    // Intentionally the settings ROOT: deeper extension-pane URLs
                    // are undocumented and break between macOS releases.
                    if let url = URL(string: "x-apple.systempreferences:") {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .fontWeight(.semibold)
                .frame(width: 20, alignment: .trailing)
            Text(text)
        }
        .font(.callout)
    }

    // MARK: - (b) Folders

    private var foldersTab: some View {
        Form {
            Section("Folder access") {
                Text("FinderFix can only act inside folders you've granted access to (macOS sandbox rule). Grant your usual working folders — e.g. Desktop, Documents, Downloads.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Grant Access…") { grantFolderAccess() }
                if folders.isEmpty {
                    Text("No folders granted yet.")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    List {
                        ForEach(folders, id: \.self) { path in
                            HStack {
                                Image(systemName: "folder")
                                    .foregroundStyle(.secondary)
                                Text(path)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                Spacer()
                                Button("Remove") {
                                    BookmarkStore.removeBookmark(forPath: path)
                                    notifyFoldersChanged()
                                    refreshFolders()
                                }
                                .buttonStyle(.link)
                            }
                        }
                    }
                    .frame(minHeight: 120)
                }
            }
        }
    }

    private func grantFolderAccess() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.canCreateDirectories = false
        panel.prompt = "Grant Access"
        panel.message = "Choose folders where FinderFix may create, move, and paste files."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            BookmarkStore.saveBookmark(for: url)
        }
        notifyFoldersChanged()
        refreshFolders()
    }

    private func refreshFolders() {
        folders = BookmarkStore.bookmarkedPaths()
    }

    /// Tell the Finder Sync extension to re-register its watched folders.
    private func notifyFoldersChanged() {
        DistributedNotificationCenter.default().post(
            name: AppGroup.foldersChangedNotification,
            object: nil
        )
    }

    // MARK: - (c) Hotkeys

    private var hotkeysTab: some View {
        Form {
            Section("Global hotkeys (Finder only)") {
                Text("These fire only while Finder is the frontmost app. Pick a modifier preset per action — changes apply immediately.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                ForEach(HotKeyAction.allCases) { action in
                    HStack {
                        Text(action.title)
                        Spacer()
                        Text(keyGlyph(for: action))
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                        Picker("", selection: Binding(
                            get: { hotKeys.presetIndex(for: action) },
                            set: { hotKeys.setPreset($0, for: action) }
                        )) {
                            ForEach(HotKeyPreset.all.indices, id: \.self) { i in
                                Text(HotKeyPreset.all[i].name).tag(i)
                            }
                        }
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }
                Text("Defaults: ⌃⌘X cut · ⌃⌘V paste · ⌃⌘N new file. Bare ⌘X/⌘V/⌘N are intentionally not offered — they belong to Finder and text editing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func keyGlyph(for action: HotKeyAction) -> String {
        switch action {
        case .cut: return "X"
        case .paste: return "V"
        case .newFile: return "N"
        }
    }

    // MARK: - (d) Templates

    private var templatesTab: some View {
        Form {
            Section("Built-in templates") {
                ForEach(Templates.builtIn) { template in
                    HStack {
                        Image(systemName: "doc")
                            .foregroundStyle(.secondary)
                        Text(template.name)
                        Spacer()
                        Text(".\(template.ext)")
                            .foregroundStyle(.secondary)
                            .font(.callout.monospaced())
                    }
                }
            }
            Section("Your templates") {
                if customTemplates.isEmpty {
                    Text("No custom templates yet. Add one below — it appears in Finder's New File menu.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach(customTemplates.indices, id: \.self) { i in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            TextField("Name", text: $customTemplates[i].name)
                            TextField("ext", text: $customTemplates[i].ext)
                                .frame(width: 70)
                            Spacer()
                            Button(role: .destructive) {
                                customTemplates.remove(at: i)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.plain)
                            .foregroundStyle(.red)
                        }
                        TextField("Starting content (optional)", text: $customTemplates[i].content)
                            .font(.callout.monospaced())
                    }
                    .padding(.vertical, 4)
                    Divider()
                }
                Button("Add Template") {
                    customTemplates.append(FileTemplate(name: "New Document", ext: "txt", content: ""))
                }
            }
        }
        .onChange(of: customTemplates) { _, newValue in
            Templates.saveCustom(newValue)
        }
    }

    // MARK: - (e) Hidden Files

    private var hiddenFilesTab: some View {
        Form {
            Section("Show / hide hidden files") {
                Text("Toggles Finder's hidden-file visibility. Finder relaunches automatically to apply the change.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button("Toggle Now") {
                    if FinderBridge.toggleHiddenFiles() {
                        hiddenFilesMessage = "Toggled — Finder is relaunching."
                        showHiddenFilesManual = false
                    } else {
                        // Automation was denied or Finder unreachable: fall back
                        // to manual instructions instead of failing silently.
                        hiddenFilesMessage = nil
                        showHiddenFilesManual = true
                    }
                }
                if let message = hiddenFilesMessage {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                if showHiddenFilesManual {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Automatic toggle needs Automation permission for Finder (System Settings → Privacy & Security → Automation → FinderFix → Finder). Or do it manually in Terminal:")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                        Text("defaults write com.apple.finder AppleShowAllFiles -bool true; killall Finder")
                            .font(.callout.monospaced())
                            .textSelection(.enabled)
                            .padding(8)
                            .background(.quaternary)
                            .cornerRadius(6)
                        Text("Use -bool false to hide them again.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("From Finder") {
                Text("You can also toggle from Finder's right-click menu: FinderFix → Show/Hide Hidden Files. (The extension asks this app to perform the toggle.)")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

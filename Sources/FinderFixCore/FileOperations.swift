import AppKit
import Foundation

// MARK: - Templates

/// A New-File template: {name, ext, content}.
struct FileTemplate: Codable, Identifiable, Equatable {
    var id: String { name + "." + ext }
    var name: String
    var ext: String
    var content: String
}

enum Templates {
    static let builtIn: [FileTemplate] = [
        FileTemplate(name: "Text Document", ext: "txt", content: ""),
        FileTemplate(name: "Markdown Document", ext: "md", content: "# \n"),
        FileTemplate(name: "Rich Text Document", ext: "rtf",
                     content: "{\\rtf1\\ansi\\ansicpg1252\\cocoartf2709\\cocoasubrtf870\n{\\fonttbl}\n\\pard\\tx0\\par}"),
    ]

    static func custom() -> [FileTemplate] {
        guard let defaults = AppGroup.defaults,
              let data = defaults.data(forKey: AppGroup.Keys.customTemplates),
              let decoded = try? JSONDecoder().decode([FileTemplate].self, from: data) else {
            return []
        }
        return decoded
    }

    static func saveCustom(_ templates: [FileTemplate]) {
        if let data = try? JSONEncoder().encode(templates) {
            AppGroup.defaults?.set(data, forKey: AppGroup.Keys.customTemplates)
        }
    }

    static func all() -> [FileTemplate] { builtIn + custom() }
}

// MARK: - File operations

enum FileOperations {

    /// A non-colliding destination URL inside `directory`. Never overwrites.
    static func uniqueURL(in directory: URL, baseName: String, pathExtension: String) -> URL {
        let cleanBase = baseName.isEmpty ? "untitled" : baseName
        var candidate = directory.appendingPathComponent(cleanBase).appendingPathExtension(pathExtension)
        var i = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = directory.appendingPathComponent("\(cleanBase) \(i)").appendingPathExtension(pathExtension)
            i += 1
        }
        return candidate
    }

    static func createFile(at url: URL, contents: Data) throws {
        try contents.write(to: url, options: .atomic)
    }

    /// Moves each source into `destination`. Name collisions are uniquified, never overwritten.
    /// - Returns: final URLs of the moved items.
    @discardableResult
    static func moveItems(_ sources: [URL], to destination: URL) throws -> [URL] {
        var moved: [URL] = []
        for src in sources {
            let base = src.deletingPathExtension().lastPathComponent
            let dest = uniqueURL(in: destination, baseName: base, pathExtension: src.pathExtension)
            try FileManager.default.moveItem(at: src, to: dest)
            moved.append(dest)
        }
        return moved
    }

    /// Copies the POSIX paths of `urls` (one per line) to the general pasteboard.
    static func copyPOSIXPaths(_ urls: [URL]) {
        let text = urls.map { $0.path }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Copies file names (one per line) to the general pasteboard.
    static func copyFileNames(_ urls: [URL]) {
        let text = urls.map { $0.lastPathComponent }.joined(separator: "\n")
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
}

// MARK: - Clipboard → file

struct ClipboardFilePayload {
    let baseName: String
    let pathExtension: String
    let data: Data
}

enum ClipboardReader {
    /// Reads the general pasteboard and returns data suitable for "Paste as File".
    /// Prefers images (PNG, then TIFF) over text. Returns nil when nothing usable is present.
    /// Pasteboard reads are permitted from the sandboxed extension.
    static func payload() -> ClipboardFilePayload? {
        let pb = NSPasteboard.general
        if let data = pb.data(forType: .png) {
            return ClipboardFilePayload(baseName: "Clipboard Image", pathExtension: "png", data: data)
        }
        if let data = pb.data(forType: .tiff) {
            return ClipboardFilePayload(baseName: "Clipboard Image", pathExtension: "tiff", data: data)
        }
        if let text = pb.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return ClipboardFilePayload(baseName: "Clipboard Text", pathExtension: "txt", data: Data(text.utf8))
        }
        return nil
    }
}

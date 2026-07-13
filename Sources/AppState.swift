import SwiftUI
import Combine

struct FileNode: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    var children: [FileNode]?
    var id: URL { url }
}

enum DocMode: String, CaseIterable, Identifiable {
    case markdown = "Markdown"
    case html = "HTML"
    var id: String { rawValue }
}

final class AppState: ObservableObject {
    @Published var rootURL: URL
    @Published var tree: [FileNode] = []
    @Published var selection: URL?
    @Published var text: String = ""
    @Published var mode: DocMode = .markdown
    @Published var isDirty = false
    @Published var showPreview = true
    @Published var previewHTML: String = ""
    @Published var statusMessage: String = "Ready"
    @Published var errorMessage: String?

    private(set) var currentFile: URL?
    let format = FormatController()
    private var cancellables = Set<AnyCancellable>()
    private static let editableExtensions: Set<String> = ["md", "markdown", "txt", "html", "htm"]

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let root = docs.appendingPathComponent("MyMarkdown", isDirectory: true)
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        rootURL = root
        createWelcomeFileIfNeeded()
        refreshTree()

        $text
            .debounce(for: .milliseconds(250), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePreview() }
            .store(in: &cancellables)

        $text
            .debounce(for: .seconds(1.0), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.saveCurrent() }
            .store(in: &cancellables)
    }

    // MARK: - File tree

    func refreshTree() {
        tree = Self.scan(rootURL)
    }

    private static func scan(_ dir: URL) -> [FileNode] {
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return [] }

        var nodes: [FileNode] = []
        for url in contents {
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
            if isDir {
                nodes.append(FileNode(url: url, name: url.lastPathComponent,
                                      isDirectory: true, children: scan(url)))
            } else if editableExtensions.contains(url.pathExtension.lowercased()) {
                nodes.append(FileNode(url: url, name: url.lastPathComponent,
                                      isDirectory: false, children: nil))
            }
        }
        return nodes.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    /// Folder that new files/folders should land in, based on current selection.
    var targetFolder: URL {
        guard let sel = selection else { return rootURL }
        let isDir = (try? sel.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        return isDir ? sel : sel.deletingLastPathComponent()
    }

    // MARK: - Documents

    func open(_ url: URL) {
        guard !((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false) else { return }
        saveCurrent()
        currentFile = url
        text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        mode = ["html", "htm"].contains(url.pathExtension.lowercased()) ? .html : .markdown
        isDirty = false
        statusMessage = url.lastPathComponent
        updatePreview()
        DispatchQueue.main.async { [weak self] in
            self?.format.textView?.undoManager?.removeAllActions()
        }
    }

    func textEdited(_ newText: String) {
        text = newText
        if currentFile != nil { isDirty = true }
    }

    func saveCurrent() {
        guard isDirty, let url = currentFile else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            isDirty = false
            let f = DateFormatter()
            f.timeStyle = .medium
            statusMessage = "Saved \(f.string(from: Date()))"
        } catch {
            errorMessage = "Couldn't save \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    func updatePreview() {
        previewHTML = mode == .markdown ? Markdown.toHTML(text) : text
    }

    // MARK: - File operations

    @discardableResult
    func createFile(named rawName: String, in folder: URL? = nil) -> String? {
        do {
            var name = try ItemNameRules.normalizedName(rawName)
            if !name.contains(".") { name += ".md" }
            let url = (folder ?? targetFolder).appendingPathComponent(name)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                return "A file named \(name) already exists there."
            }
            try "".write(to: url, atomically: true, encoding: .utf8)
            refreshTree()
            selection = url
            open(url)
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @discardableResult
    func createFolder(named rawName: String, in folder: URL? = nil) -> String? {
        do {
            let name = try ItemNameRules.normalizedName(rawName)
            let url = (folder ?? targetFolder).appendingPathComponent(name, isDirectory: true)
            guard !FileManager.default.fileExists(atPath: url.path) else {
                return "A folder named \(name) already exists there."
            }
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
            refreshTree()
            selection = url
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    @discardableResult
    func rename(_ url: URL, to rawName: String) -> String? {
        saveCurrent()
        let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false
        do {
            let baseName = try ItemNameRules.normalizedName(rawName, keepingExtension: isDir ? nil : url.pathExtension)
            let dest = ItemNameRules.renamedURL(from: url, baseName: baseName, isDirectory: isDir)
            if dest.standardizedFileURL == url.standardizedFileURL { return nil }
            guard !FileManager.default.fileExists(atPath: dest.path) else {
                return "An item named \(dest.lastPathComponent) already exists there."
            }
            try FileManager.default.moveItem(at: url, to: dest)
            currentFile = ItemNameRules.remappedURL(currentFile, from: url, to: dest)
            selection = ItemNameRules.remappedURL(selection, from: url, to: dest)
            if let currentFile {
                statusMessage = currentFile.lastPathComponent
            }
            refreshTree()
            return nil
        } catch {
            return error.localizedDescription
        }
    }

    func moveToTrash(_ url: URL) {
        do {
            try FileManager.default.trashItem(at: url, resultingItemURL: nil)
            if currentFile == url || currentFile?.path.hasPrefix(url.path + "/") == true {
                currentFile = nil
                text = ""
                isDirty = false
                selection = nil
                statusMessage = "Ready"
                updatePreview()
            }
            refreshTree()
        } catch {
            errorMessage = "Couldn't move to Trash: \(error.localizedDescription)"
        }
    }

    /// Every folder in the vault, depth-first, for the "Move To" menu.
    var allFolders: [(url: URL, title: String)] {
        var out: [(URL, String)] = []
        func walk(_ nodes: [FileNode], depth: Int) {
            for node in nodes where node.isDirectory {
                out.append((node.url, String(repeating: "\u{2003}", count: depth) + node.name))
                walk(node.children ?? [], depth: depth + 1)
            }
        }
        walk(tree, depth: 0)
        return out
    }

    /// Moves a file or folder into another folder (drag & drop or "Move To").
    /// Items dragged in from outside the vault are copied instead.
    func move(_ source: URL, into destinationFolder: URL) {
        let fm = FileManager.default
        let src = source.standardizedFileURL
        let destDir = destinationFolder.standardizedFileURL
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: src.path),
              fm.fileExists(atPath: destDir.path, isDirectory: &isDir),
              isDir.boolValue else { return }
        guard src != destDir,
              src.deletingLastPathComponent().path != destDir.path else { return }
        if destDir.path.hasPrefix(src.path + "/") {
            errorMessage = "Can't move a folder into itself."
            return
        }

        // Pick a non-conflicting destination name
        var dest = destDir.appendingPathComponent(src.lastPathComponent)
        let base = dest.deletingPathExtension().lastPathComponent
        let ext = dest.pathExtension
        var counter = 2
        while fm.fileExists(atPath: dest.path) {
            let name = ext.isEmpty ? "\(base) \(counter)" : "\(base) \(counter).\(ext)"
            dest = destDir.appendingPathComponent(name)
            counter += 1
        }

        do {
            let insideVault = src.path.hasPrefix(rootURL.standardizedFileURL.path + "/")
            if insideVault {
                try fm.moveItem(at: src, to: dest)
            } else {
                try fm.copyItem(at: src, to: dest)
            }
            // Keep the open document pointed at its new location
            if let current = currentFile {
                if current.standardizedFileURL == src {
                    currentFile = dest
                    selection = dest
                } else if current.path.hasPrefix(src.path + "/") {
                    let suffix = String(current.path.dropFirst(src.path.count))
                    let remapped = URL(fileURLWithPath: dest.path + suffix)
                    currentFile = remapped
                    selection = remapped
                }
            }
            refreshTree()
            statusMessage = "Moved \(dest.lastPathComponent) to \(destDir.lastPathComponent)"
        } catch {
            errorMessage = "Couldn't move: \(error.localizedDescription)"
        }
    }

    func revealInFinder(_ url: URL?) {
        let target = url ?? currentFile ?? rootURL
        NSWorkspace.shared.activateFileViewerSelecting([target])
    }

    func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    // MARK: - Welcome file

    private func createWelcomeFileIfNeeded() {
        let fm = FileManager.default
        let contents = (try? fm.contentsOfDirectory(atPath: rootURL.path)) ?? []
        guard contents.filter({ !$0.hasPrefix(".") }).isEmpty else { return }
        let welcome = rootURL.appendingPathComponent("Welcome to MarkPad.md")
        let body = """
        # Welcome to MarkPad 👋

        Everything you write here is saved as a plain **Markdown file** in \
        `Documents/MyMarkdown` — ready to paste into Claude, ChatGPT, Copilot, or anywhere else.

        ## The basics

        - Files and folders live in the **sidebar**. Right-click for rename, delete, and more.
        - **⌘N** makes a new file, **⌘⇧N** makes a new folder. Nest folders as deep as you like.
        - Your work **autosaves** about a second after you stop typing.
        - Toggle the **live preview** with the sidebar-shaped button in the toolbar.
        - Switch a document between **Markdown and HTML** mode with the picker in the toolbar.

        ## Formatting cheat sheet

        | You type | You get |
        |---|---|
        | `**bold**` | **bold** |
        | `*italic*` | *italic* |
        | `# Heading` | a big heading |
        | `- item` | a bullet list |
        | `[title](https://example.com)` | a link |
        | `` `code` `` | `code` |

        > Tip: select some text and press **⌘B** or **⌘I** — MarkPad wraps it for you.

        ## Importing your Apple Notes

        Choose **File → Import from Apple Notes…** and MarkPad will copy your notes
        into an “Apple Notes Import” folder here, converted to Markdown.
        macOS will ask permission the first time — that's normal.

        Happy writing!
        """
        try? body.write(to: welcome, atomically: true, encoding: .utf8)
    }
}

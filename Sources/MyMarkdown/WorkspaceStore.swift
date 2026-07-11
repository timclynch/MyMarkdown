import AppKit
import Combine
import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var rootURL: URL
    @Published var tree: [FileNode] = []
    @Published var selectedURL: URL? {
        didSet { loadSelection() }
    }
    @Published var text = ""
    @Published var selection = NSRange(location: 0, length: 0)
    @Published var editorMode: EditorMode = .write
    @Published var searchText = ""
    @Published var statusMessage = "Ready"
    @Published var isShowingRename = false
    @Published var renameText = ""

    private var saveTask: Task<Void, Never>?
    private var isLoading = false
    private let fileManager = FileManager.default
    private let rootKey = "MyMarkdown.workspaceRoot"

    init() {
        let stored = UserDefaults.standard.string(forKey: rootKey)
        let defaultRoot = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MyMarkdown Library", isDirectory: true)
        rootURL = stored.map { URL(fileURLWithPath: $0, isDirectory: true) } ?? defaultRoot
        prepareRoot()
        reloadTree()
    }

    var selectedKind: DocumentKind? {
        guard let selectedURL else { return nil }
        return DocumentKind(rawValue: selectedURL.pathExtension.lowercased())
    }

    var selectedName: String {
        selectedURL?.deletingPathExtension().lastPathComponent ?? "MyMarkdown"
    }

    var selectedRelativePath: String {
        guard let selectedURL else { return rootURL.path }
        return selectedURL.path.replacingOccurrences(of: rootURL.path + "/", with: "")
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var filteredTree: [FileNode] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return tree }
        return filter(nodes: tree, query: query.lowercased())
    }

    func reloadTree() {
        tree = nodes(at: rootURL)
        statusMessage = "Updated"
    }

    func chooseRootFolder() {
        let panel = NSOpenPanel()
        panel.title = "Choose Your MyMarkdown Folder"
        panel.prompt = "Use This Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = rootURL
        guard panel.runModal() == .OK, let url = panel.url else { return }

        saveImmediately()
        rootURL = url
        UserDefaults.standard.set(url.path, forKey: rootKey)
        selectedURL = nil
        prepareRoot()
        reloadTree()
    }

    func revealRoot() {
        NSWorkspace.shared.activateFileViewerSelecting([rootURL])
    }

    func createDocument(kind: DocumentKind) {
        let parent = destinationFolder()
        let base = kind == .markdown ? "Untitled Note" : "Untitled Page"
        let url = uniqueURL(in: parent, base: base, extension: kind.rawValue)
        let initial: String
        if kind == .markdown {
            initial = "# \(url.deletingPathExtension().lastPathComponent)\n\n"
        } else {
            initial = "<!doctype html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>\(url.deletingPathExtension().lastPathComponent)</title>\n</head>\n<body>\n  <h1>\(url.deletingPathExtension().lastPathComponent)</h1>\n  <p>Start writing here.</p>\n</body>\n</html>\n"
        }
        do {
            try initial.write(to: url, atomically: true, encoding: .utf8)
            reloadTree()
            selectedURL = url
            statusMessage = "Created \(url.lastPathComponent)"
        } catch {
            present(error: error)
        }
    }

    func createFolder() {
        let parent = destinationFolder()
        let url = uniqueFolderURL(in: parent, base: "New Project")
        do {
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
            reloadTree()
            statusMessage = "Created \(url.lastPathComponent)"
        } catch {
            present(error: error)
        }
    }

    func beginRename() {
        guard let selectedURL else { return }
        renameText = selectedURL.deletingPathExtension().lastPathComponent
        isShowingRename = true
    }

    func finishRename() {
        guard let oldURL = selectedURL else { return }
        let clean = sanitize(renameText)
        guard !clean.isEmpty else { return }
        let newURL = oldURL.deletingLastPathComponent()
            .appendingPathComponent(clean)
            .appendingPathExtension(oldURL.pathExtension)
        guard newURL != oldURL else { return }
        do {
            saveImmediately()
            try fileManager.moveItem(at: oldURL, to: newURL)
            selectedURL = nil
            reloadTree()
            selectedURL = newURL
        } catch {
            present(error: error)
        }
    }

    func deleteSelection() {
        guard let url = selectedURL else { return }
        let alert = NSAlert()
        alert.messageText = "Move “\(url.lastPathComponent)” to the Trash?"
        alert.informativeText = "You can recover it from the Trash if you change your mind."
        alert.addButton(withTitle: "Move to Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        do {
            saveTask?.cancel()
            _ = try fileManager.trashItem(at: url, resultingItemURL: nil)
            selectedURL = nil
            text = ""
            reloadTree()
        } catch {
            present(error: error)
        }
    }

    func textDidChange(_ newValue: String) {
        text = newValue
        guard !isLoading else { return }
        scheduleSave()
    }

    func saveImmediately() {
        saveTask?.cancel()
        guard let selectedURL, selectedKind != nil, !isLoading else { return }
        do {
            try text.write(to: selectedURL, atomically: true, encoding: .utf8)
            statusMessage = "Saved"
        } catch {
            present(error: error)
        }
    }

    func apply(_ action: FormattingAction) {
        guard selectedKind != nil else { return }
        let nsText = text as NSString
        let safeLocation = min(selection.location, nsText.length)
        let safeLength = min(selection.length, nsText.length - safeLocation)
        let range = NSRange(location: safeLocation, length: safeLength)
        let chosen = nsText.substring(with: range)

        let replacement: String
        let cursorOffset: Int
        if selectedKind == .html {
            (replacement, cursorOffset) = htmlReplacement(action, chosen: chosen)
        } else {
            (replacement, cursorOffset) = markdownReplacement(action, chosen: chosen)
        }

        text = nsText.replacingCharacters(in: range, with: replacement)
        selection = NSRange(location: safeLocation + cursorOffset, length: chosen.isEmpty ? 0 : chosen.utf16.count)
        scheduleSave()
    }

    private func loadSelection() {
        saveImmediately()
        guard let url = selectedURL else { text = ""; return }
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return }
        guard DocumentKind(rawValue: url.pathExtension.lowercased()) != nil else { return }
        do {
            isLoading = true
            text = try String(contentsOf: url, encoding: .utf8)
            selection = NSRange(location: 0, length: 0)
            isLoading = false
            statusMessage = "Opened \(url.lastPathComponent)"
        } catch {
            isLoading = false
            present(error: error)
        }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(450))
            guard !Task.isCancelled else { return }
            self?.saveImmediately()
        }
    }

    private func prepareRoot() {
        do {
            try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        } catch {
            present(error: error)
        }
    }

    private func nodes(at url: URL) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        let urls = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { child in
            let values = try? child.resourceValues(forKeys: Set(keys))
            let isDirectory = values?.isDirectory == true
            guard isDirectory || DocumentKind(rawValue: child.pathExtension.lowercased()) != nil else { return nil }
            return FileNode(url: child, isDirectory: isDirectory, children: isDirectory ? nodes(at: child) : nil)
        }.sorted {
            if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
            return $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func filter(nodes: [FileNode], query: String) -> [FileNode] {
        nodes.compactMap { node in
            if node.isDirectory {
                let children = filter(nodes: node.children ?? [], query: query)
                if node.name.lowercased().contains(query) || !children.isEmpty {
                    return FileNode(url: node.url, isDirectory: true, children: children)
                }
                return nil
            }
            let nameMatches = node.name.lowercased().contains(query)
            let contentMatches = (try? String(contentsOf: node.url, encoding: .utf8).lowercased().contains(query)) == true
            return (nameMatches || contentMatches) ? node : nil
        }
    }

    private func destinationFolder() -> URL {
        guard let selectedURL else { return rootURL }
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: selectedURL.path, isDirectory: &isDirectory), isDirectory.boolValue {
            return selectedURL
        }
        return selectedURL.deletingLastPathComponent()
    }

    private func uniqueURL(in folder: URL, base: String, extension ext: String) -> URL {
        var number = 1
        var url = folder.appendingPathComponent(base).appendingPathExtension(ext)
        while fileManager.fileExists(atPath: url.path) {
            number += 1
            url = folder.appendingPathComponent("\(base) \(number)").appendingPathExtension(ext)
        }
        return url
    }

    private func uniqueFolderURL(in folder: URL, base: String) -> URL {
        var number = 1
        var url = folder.appendingPathComponent(base, isDirectory: true)
        while fileManager.fileExists(atPath: url.path) {
            number += 1
            url = folder.appendingPathComponent("\(base) \(number)", isDirectory: true)
        }
        return url
    }

    private func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "/", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func markdownReplacement(_ action: FormattingAction, chosen: String) -> (String, Int) {
        switch action {
        case .heading: return ("## " + (chosen.isEmpty ? "Heading" : chosen), 3)
        case .bold: return ("**" + (chosen.isEmpty ? "bold text" : chosen) + "**", 2)
        case .italic: return ("_" + (chosen.isEmpty ? "italic text" : chosen) + "_", 1)
        case .bulletedList: return prefixLines(chosen, prefix: "- ")
        case .numberedList: return numberedLines(chosen)
        case .checklist: return prefixLines(chosen, prefix: "- [ ] ")
        case .quote: return prefixLines(chosen, prefix: "> ")
        case .link: return ("[" + (chosen.isEmpty ? "link text" : chosen) + "](https://)", 1)
        case .code: return chosen.contains("\n") ? ("```\n\(chosen)\n```", 4) : ("`" + (chosen.isEmpty ? "code" : chosen) + "`", 1)
        }
    }

    private func htmlReplacement(_ action: FormattingAction, chosen: String) -> (String, Int) {
        let content = chosen.isEmpty ? "text" : chosen
        switch action {
        case .heading: return ("<h2>\(content)</h2>", 4)
        case .bold: return ("<strong>\(content)</strong>", 8)
        case .italic: return ("<em>\(content)</em>", 4)
        case .bulletedList: return ("<ul>\n  <li>\(content)</li>\n</ul>", 11)
        case .numberedList: return ("<ol>\n  <li>\(content)</li>\n</ol>", 11)
        case .checklist: return ("<label><input type=\"checkbox\"> \(content)</label>", 38)
        case .quote: return ("<blockquote>\(content)</blockquote>", 12)
        case .link: return ("<a href=\"https://\">\(content)</a>", 19)
        case .code: return ("<code>\(content)</code>", 6)
        }
    }

    private func prefixLines(_ chosen: String, prefix: String) -> (String, Int) {
        let source = chosen.isEmpty ? "List item" : chosen
        return (source.split(separator: "\n", omittingEmptySubsequences: false).map { prefix + $0 }.joined(separator: "\n"), prefix.utf16.count)
    }

    private func numberedLines(_ chosen: String) -> (String, Int) {
        let source = chosen.isEmpty ? "List item" : chosen
        let result = source.split(separator: "\n", omittingEmptySubsequences: false).enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
        return (result, 3)
    }

    private func present(error: Error) {
        statusMessage = "Could not complete that action"
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

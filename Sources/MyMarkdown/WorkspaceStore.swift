import AppKit
import Combine
import Foundation

@MainActor
final class WorkspaceStore: ObservableObject {
    @Published var rootURL: URL
    @Published var tree: [FileNode] = []
    @Published var selectedURL: URL? {
        willSet { saveCurrentDocument(at: selectedURL) }
        didSet { loadSelection() }
    }
    @Published var text = ""
    @Published var selection = NSRange(location: 0, length: 0)
    @Published var editorMode: EditorMode = .write
    @Published var searchText = ""
    @Published var statusMessage = "Ready"
    @Published var namingIntent: NamingIntent?
    @Published var nameDraft = ""
    @Published var namingError: String?

    let editorSession = EditorSession()

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
        guard let selectedURL, !isDirectory(selectedURL) else { return nil }
        return DocumentKind(rawValue: selectedURL.pathExtension.lowercased())
    }

    var selectedName: String {
        guard let selectedURL else { return "MyMarkdown" }
        return displayName(for: selectedURL)
    }

    var selectedRelativePath: String {
        guard let selectedURL else { return rootURL.path }
        let rootPath = rootURL.resolvingSymlinksInPath().path
        let selectedPath = selectedURL.resolvingSymlinksInPath().path
        return selectedPath.replacingOccurrences(of: rootPath + "/", with: "")
    }

    var wordCount: Int {
        text.split { $0.isWhitespace || $0.isNewline }.count
    }

    var namingHint: String? {
        guard case .rename(let url) = namingIntent, !isDirectory(url), !url.pathExtension.isEmpty else { return nil }
        return "The .\(url.pathExtension) extension is kept automatically."
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

    func beginCreateDocument(kind: DocumentKind) {
        startNaming(.createDocument(kind), defaultName: "")
    }

    func beginCreateFolder() {
        startNaming(.createFolder, defaultName: "")
    }

    func beginRename(_ url: URL? = nil) {
        saveImmediately()
        if let url { selectedURL = url }
        guard let selectedURL else { return }
        startNaming(.rename(selectedURL), defaultName: displayName(for: selectedURL))
    }

    func cancelNaming() {
        namingIntent = nil
        nameDraft = ""
        namingError = nil
    }

    @discardableResult
    func confirmNaming() -> Bool {
        guard let namingIntent else { return false }
        do {
            switch namingIntent {
            case .createDocument(let kind):
                let baseName = try ItemNameValidator.normalizedBaseName(nameDraft, fileExtension: kind.rawValue)
                let url = destinationFolder().appendingPathComponent(baseName).appendingPathExtension(kind.rawValue)
                guard !fileManager.fileExists(atPath: url.path) else { throw ItemNameError.alreadyExists }
                try initialContent(for: kind, name: baseName).write(to: url, atomically: true, encoding: .utf8)
                finishNaming(with: url, status: "Created \(url.lastPathComponent)")

            case .createFolder:
                let baseName = try ItemNameValidator.normalizedBaseName(nameDraft)
                let url = destinationFolder().appendingPathComponent(baseName, isDirectory: true)
                guard !fileManager.fileExists(atPath: url.path) else { throw ItemNameError.alreadyExists }
                try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
                finishNaming(with: url, status: "Created \(url.lastPathComponent)")

            case .rename(let oldURL):
                let directory = isDirectory(oldURL)
                let extensionToKeep = directory ? nil : oldURL.pathExtension
                let baseName = try ItemNameValidator.normalizedBaseName(nameDraft, fileExtension: extensionToKeep)
                let newURL = LibraryItemOperations.destinationURL(for: oldURL, baseName: baseName, isDirectory: directory)
                let priorSelection = selectedURL
                saveImmediately()
                try LibraryItemOperations.moveItem(at: oldURL, to: newURL, fileManager: fileManager)
                let remappedSelection = LibraryItemOperations.remappedURL(priorSelection, movingFrom: oldURL, to: newURL)
                finishNaming(with: remappedSelection ?? newURL, status: "Renamed to \(newURL.lastPathComponent)")
            }
            return true
        } catch {
            namingError = error.localizedDescription
            return false
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
            isLoading = true
            selectedURL = nil
            isLoading = false
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
        saveCurrentDocument(at: selectedURL)
    }

    private func saveCurrentDocument(at url: URL?) {
        guard let url,
              !isLoading,
              !isDirectory(url),
              DocumentKind(rawValue: url.pathExtension.lowercased()) != nil,
              fileManager.fileExists(atPath: url.path) else { return }
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Saved"
        } catch {
            present(error: error)
        }
    }

    func apply(_ action: FormattingAction) {
        guard let selectedKind else {
            statusMessage = "Open a document before formatting it"
            return
        }
        guard editorMode != .preview else {
            statusMessage = "Switch to Write or Split view to format text"
            return
        }
        editorSession.apply(action, kind: selectedKind)
    }

    private func startNaming(_ intent: NamingIntent, defaultName: String) {
        namingIntent = intent
        nameDraft = defaultName
        namingError = nil
    }

    private func finishNaming(with url: URL, status: String) {
        isLoading = true
        selectedURL = nil
        reloadTree()
        isLoading = false
        selectedURL = url
        namingIntent = nil
        nameDraft = ""
        namingError = nil
        statusMessage = status
    }

    private func loadSelection() {
        guard let url = selectedURL else {
            text = ""
            selection = NSRange(location: 0, length: 0)
            return
        }
        guard !isDirectory(url), DocumentKind(rawValue: url.pathExtension.lowercased()) != nil else {
            text = ""
            selection = NSRange(location: 0, length: 0)
            return
        }
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

    private func initialContent(for kind: DocumentKind, name: String) -> String {
        if kind == .markdown { return "# \(name)\n\n" }
        return "<!doctype html>\n<html lang=\"en\">\n<head>\n  <meta charset=\"utf-8\">\n  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\">\n  <title>\(name)</title>\n</head>\n<body>\n  <h1>\(name)</h1>\n  <p>Start writing here.</p>\n</body>\n</html>\n"
    }

    private func nodes(at url: URL) -> [FileNode] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isHiddenKey]
        let urls = (try? fileManager.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        return urls.compactMap { child in
            let values = try? child.resourceValues(forKeys: Set(keys))
            let directory = values?.isDirectory == true
            guard directory || DocumentKind(rawValue: child.pathExtension.lowercased()) != nil else { return nil }
            return FileNode(url: child, isDirectory: directory, children: directory ? nodes(at: child) : nil)
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
        return isDirectory(selectedURL) ? selectedURL : selectedURL.deletingLastPathComponent()
    }

    private func displayName(for url: URL) -> String {
        isDirectory(url) ? url.lastPathComponent : url.deletingPathExtension().lastPathComponent
    }

    private func isDirectory(_ url: URL) -> Bool {
        var directory: ObjCBool = false
        return fileManager.fileExists(atPath: url.path, isDirectory: &directory) && directory.boolValue
    }

    private func present(error: Error) {
        statusMessage = "Could not complete that action"
        let alert = NSAlert(error: error)
        alert.runModal()
    }
}

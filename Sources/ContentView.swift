import SwiftUI

struct ContentView: View {
    @EnvironmentObject var state: AppState
    @State private var sheet: SheetKind?

    enum SheetKind: Identifiable {
        case newFile
        case newFolder
        case rename(URL)
        var id: String {
            switch self {
            case .newFile: return "newFile"
            case .newFolder: return "newFolder"
            case .rename(let url): return "rename-\(url.path)"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
        } detail: {
            detail
        }
        .navigationTitle(state.currentFile?.lastPathComponent ?? "MarkPad")
        .onChange(of: state.selection) { _, newValue in
            if let url = newValue { state.open(url) }
        }
        .sheet(item: $sheet) { kind in
            NameSheet(kind: kind) { name in
                switch kind {
                case .newFile: return state.createFile(named: name)
                case .newFolder: return state.createFolder(named: name)
                case .rename(let url): return state.rename(url, to: name)
                }
            }
        }
        .alert("Something went wrong",
               isPresented: Binding(
                   get: { state.errorMessage != nil },
                   set: { if !$0 { state.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(state.errorMessage ?? "")
        }
        .onReceive(NotificationCenter.default.publisher(for: .markPadCommand)) { note in
            guard let command = note.object as? MarkPadCommand else { return }
            switch command {
            case .newFile: sheet = .newFile
            case .newFolder: sheet = .newFolder
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $state.selection) {
            OutlineGroup(state.tree, children: \.children) { node in
                Label {
                    Text(node.name)
                } icon: {
                    Image(systemName: node.isDirectory ? "folder"
                          : ["html", "htm"].contains(node.url.pathExtension.lowercased())
                          ? "chevron.left.forwardslash.chevron.right" : "doc.text")
                }
                .tag(node.url)
                .draggable(node.url)
                .dropDestination(for: URL.self) { urls, _ in
                    let dest = node.isDirectory ? node.url : node.url.deletingLastPathComponent()
                    for url in urls { state.move(url, into: dest) }
                    return true
                }
                .contextMenu {
                    Button("Rename…") { sheet = .rename(node.url) }
                    moveToMenu(for: node)
                    Button("Reveal in Finder") { state.revealInFinder(node.url) }
                    Divider()
                    if node.isDirectory {
                        Button("New File Here…") { state.selection = node.url; sheet = .newFile }
                        Button("New Folder Here…") { state.selection = node.url; sheet = .newFolder }
                        Divider()
                    }
                    Button("Move to Trash", role: .destructive) { state.moveToTrash(node.url) }
                }
            }
        }
        .listStyle(.sidebar)
        .onKeyPress(.return) {
            guard let selection = state.selection else { return .ignored }
            sheet = .rename(selection)
            return .handled
        }
        .dropDestination(for: URL.self) { urls, _ in
            for url in urls { state.move(url, into: state.rootURL) }
            return true
        }
        .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        .toolbar {
            ToolbarItemGroup {
                Button { sheet = .newFile } label: {
                    Label("New File", systemImage: "square.and.pencil")
                }
                .help("New file (⌘N)")
                Button { sheet = .newFolder } label: {
                    Label("New Folder", systemImage: "folder.badge.plus")
                }
                .help("New folder (⇧⌘N)")
                Button {
                    if let selection = state.selection { sheet = .rename(selection) }
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .disabled(state.selection == nil)
                .help("Rename selected item")
                Button { state.refreshTree() } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Refresh file list")
            }
        }
    }

    // MARK: - Detail (editor + preview)

    @ViewBuilder
    private var detail: some View {
        if state.currentFile == nil {
            emptyState
        } else {
            VStack(spacing: 0) {
                HSplitView {
                    EditorTextView(
                        text: Binding(
                            get: { state.text },
                            set: { state.textEdited($0) }),
                        controller: state.format,
                        mode: state.mode)
                        .frame(minWidth: 320, maxWidth: .infinity, maxHeight: .infinity)
                    if state.showPreview {
                        PreviewWebView(html: state.previewHTML)
                            .frame(minWidth: 300, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                statusBar
            }
            .toolbar { editorToolbar }
        }
    }

    private func moveToMenu(for node: FileNode) -> some View {
        Menu("Move To") {
            Button("MyMarkdown (top level)") { state.move(node.url, into: state.rootURL) }
                .disabled(node.url.deletingLastPathComponent().path == state.rootURL.path)
            let folders = state.allFolders
            if !folders.isEmpty { Divider() }
            ForEach(folders, id: \.url) { folder in
                Button(folder.title) { state.move(node.url, into: folder.url) }
                    .disabled(folder.url == node.url
                              || folder.url.path == node.url.deletingLastPathComponent().path
                              || folder.url.path.hasPrefix(node.url.path + "/"))
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.richtext")
                .font(.system(size: 52))
                .foregroundStyle(.tertiary)
            Text("Select a file, or press ⌘N to start writing")
                .font(.title3)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ToolbarContentBuilder
    private var editorToolbar: some ToolbarContent {
        ToolbarItemGroup {
            Button { bold() } label: { Label("Bold", systemImage: "bold") }
                .help("Bold (⌘B)")
            Button { italic() } label: { Label("Italic", systemImage: "italic") }
                .help("Italic (⌘I)")
            Button { code() } label: { Label("Code", systemImage: "chevron.left.forwardslash.chevron.right") }
                .help("Inline code")
            Button { link() } label: { Label("Link", systemImage: "link") }
                .help("Insert link (⌘K)")

            if state.mode == .markdown {
                Menu {
                    Button("Heading 1") { state.format.toggleLinePrefix("# ") }
                    Button("Heading 2") { state.format.toggleLinePrefix("## ") }
                    Button("Heading 3") { state.format.toggleLinePrefix("### ") }
                } label: {
                    Label("Heading", systemImage: "number")
                }
                .help("Headings")
                Button { state.format.toggleLinePrefix("- ") } label: {
                    Label("Bullet List", systemImage: "list.bullet")
                }
                .help("Bullet list")
                Button { state.format.toggleLinePrefix("> ") } label: {
                    Label("Quote", systemImage: "text.quote")
                }
                .help("Block quote")
            }
        }

        ToolbarItemGroup {
            Picker("Mode", selection: $state.mode) {
                ForEach(DocMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .help("Switch between Markdown and HTML")
            .onChange(of: state.mode) { _, _ in state.updatePreview() }

            Button {
                state.showPreview.toggle()
            } label: {
                Label("Preview", systemImage: state.showPreview
                      ? "sidebar.trailing" : "rectangle.righthalf.inset.filled")
            }
            .help("Show or hide the live preview")
        }
    }

    private var statusBar: some View {
        HStack {
            Text(state.statusMessage)
            if state.isDirty {
                Circle().fill(.orange).frame(width: 7, height: 7)
                    .help("Unsaved changes (autosaves shortly)")
            }
            Spacer()
            Text("\(wordCount) words")
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .background(.bar)
    }

    private var wordCount: Int {
        state.text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count
    }

    // MARK: - Formatting helpers (mode-aware)

    private func bold() {
        state.mode == .markdown
            ? state.format.wrapSelection("**", "**")
            : state.format.wrapSelection("<strong>", "</strong>")
    }
    private func italic() {
        state.mode == .markdown
            ? state.format.wrapSelection("*", "*")
            : state.format.wrapSelection("<em>", "</em>")
    }
    private func code() {
        state.mode == .markdown
            ? state.format.wrapSelection("`", "`")
            : state.format.wrapSelection("<code>", "</code>")
    }
    private func link() {
        state.mode == .markdown
            ? state.format.wrapSelection("[", "](url)")
            : state.format.wrapSelection("<a href=\"url\">", "</a>")
    }
}

// MARK: - Naming sheet (new file / new folder / rename)

struct NameSheet: View {
    let kind: ContentView.SheetKind
    let onSubmit: (String) -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var validationMessage: String?
    @FocusState private var isNameFocused: Bool

    private var title: String {
        switch kind {
        case .newFile: return "New File"
        case .newFolder: return "New Folder"
        case .rename: return "Rename Item"
        }
    }
    private var prompt: String {
        switch kind {
        case .newFile: return "Name (.md is added automatically)"
        case .newFolder: return "Folder name"
        case .rename: return "New name"
        }
    }

    private var preservedExtension: String? {
        guard case .rename(let url) = kind,
              !((try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory ?? false),
              !url.pathExtension.isEmpty else { return nil }
        return url.pathExtension
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            TextField(prompt, text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .focused($isNameFocused)
                .onSubmit(submit)
            if let preservedExtension {
                Text("The .\(preservedExtension) extension is retained automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let validationMessage {
                Text(validationMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(title) { submit() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .onAppear {
            if case .rename(let url) = kind {
                name = url.lastPathComponent
            }
            isNameFocused = true
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        validationMessage = onSubmit(trimmed)
        if validationMessage == nil { dismiss() }
    }
}

// MARK: - Menu command plumbing

enum MarkPadCommand {
    case newFile
    case newFolder
}

extension Notification.Name {
    static let markPadCommand = Notification.Name("MarkPadCommand")
}

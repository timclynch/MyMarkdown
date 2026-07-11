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
                case .newFile: state.createFile(named: name)
                case .newFolder: state.createFolder(named: name)
                case .rename(let url): state.rename(url, to: name)
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
                .contextMenu {
                    Button("Rename…") { sheet = .rename(node.url) }
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
                        controller: state.format)
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
    let onSubmit: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""

    private var title: String {
        switch kind {
        case .newFile: return "New File"
        case .newFolder: return "New Folder"
        case .rename: return "Rename"
        }
    }
    private var prompt: String {
        switch kind {
        case .newFile: return "Name (.md is added automatically)"
        case .newFolder: return "Folder name"
        case .rename: return "New name"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title).font(.headline)
            TextField(prompt, text: $name)
                .textFieldStyle(.roundedBorder)
                .frame(width: 300)
                .onSubmit(submit)
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
        }
    }

    private func submit() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        onSubmit(trimmed)
        dismiss()
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

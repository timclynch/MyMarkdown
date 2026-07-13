import AppKit
import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        NavigationSplitView {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 210, ideal: 260, max: 380)
        } detail: {
            if workspace.selectedKind != nil {
                DocumentView()
            } else {
                WelcomeView()
            }
        }
        .toolbar { MainToolbar() }
        .onDisappear { workspace.saveImmediately() }
        .sheet(item: $workspace.namingIntent) { _ in
            ItemNameSheet()
        }
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "books.vertical.fill")
                    .foregroundStyle(.tint)
                Text("MyMarkdown")
                    .font(.headline)
                Spacer()
                Menu {
                    Button("New Markdown Note") { workspace.beginCreateDocument(kind: .markdown) }
                    Button("New HTML Document") { workspace.beginCreateDocument(kind: .html) }
                    Divider()
                    Button("New Folder") { workspace.beginCreateFolder() }
                } label: {
                    Image(systemName: "plus")
                }
                .menuStyle(.borderlessButton)
                .help("Create a note or folder")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            List(selection: $workspace.selectedURL) {
                OutlineGroup(workspace.filteredTree, children: \.children) { node in
                    Label {
                        Text(verbatim: node.name)
                            .lineLimit(1)
                    } icon: {
                        Image(systemName: node.icon)
                            .foregroundColor(node.isDirectory ? Color.accentColor : Color.secondary)
                    }
                    .tag(node.url)
                    .contextMenu {
                        Button("Rename…") {
                            workspace.beginRename(node.url)
                        }
                        Button("Show in Finder") {
                            NSWorkspace.shared.activateFileViewerSelecting([node.url])
                        }
                        Divider()
                        Button("Move to Trash", role: .destructive) {
                            workspace.selectedURL = node.url
                            workspace.deleteSelection()
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $workspace.searchText, placement: .sidebar, prompt: "Search notes")
            .onKeyPress(.return) {
                guard workspace.selectedURL != nil else { return .ignored }
                workspace.beginRename()
                return .handled
            }

            Divider()
            HStack(spacing: 10) {
                Button(action: workspace.revealRoot) {
                    Image(systemName: "folder")
                }
                .buttonStyle(.plain)
                .help("Show library in Finder")
                Text(verbatim: workspace.rootURL.lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button(action: workspace.reloadTree) {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.plain)
                .help("Refresh files")
            }
            .padding(10)
        }
    }
}

private struct DocumentView: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        VStack(spacing: 0) {
            DocumentHeader()
            Divider()
            FormattingBar()
            Divider()

            switch workspace.editorMode {
            case .write:
                SourceEditor(
                    text: Binding(get: { workspace.text }, set: { workspace.textDidChange($0) }),
                    selection: $workspace.selection,
                    kind: workspace.selectedKind ?? .markdown,
                    documentID: workspace.selectedURL?.path ?? "",
                    session: workspace.editorSession
                )
            case .preview:
                PreviewView(source: workspace.text, kind: workspace.selectedKind ?? .markdown)
            case .split:
                HSplitView {
                    SourceEditor(
                        text: Binding(get: { workspace.text }, set: { workspace.textDidChange($0) }),
                        selection: $workspace.selection,
                        kind: workspace.selectedKind ?? .markdown,
                        documentID: workspace.selectedURL?.path ?? "",
                        session: workspace.editorSession
                    )
                    .frame(minWidth: 320)
                    PreviewView(source: workspace.text, kind: workspace.selectedKind ?? .markdown)
                        .frame(minWidth: 320)
                }
            }

            Divider()
            HStack {
                Text(verbatim: workspace.statusMessage)
                Spacer()
                Text(verbatim: "\(workspace.wordCount) words")
                Text("•")
                Text(verbatim: workspace.selectedRelativePath)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .frame(height: 27)
        }
    }
}

private struct DocumentHeader: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        HStack {
            Image(systemName: workspace.selectedKind?.icon ?? "doc")
                .foregroundStyle(.tint)
            Text(verbatim: workspace.selectedName)
                .font(.title3.weight(.semibold))
            Text(verbatim: workspace.selectedKind?.displayName ?? "")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(.quaternary, in: Capsule())
            Spacer()
            Picker("View", selection: $workspace.editorMode) {
                ForEach(EditorMode.allCases) { mode in
                    Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(width: 245)
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
    }
}

private struct FormattingBar: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        HStack(spacing: 4) {
            FormatButton(title: "Heading", icon: "textformat.size", action: .heading)
            Divider().frame(height: 18)
            FormatButton(title: "Bold", icon: "bold", action: .bold)
            FormatButton(title: "Italic", icon: "italic", action: .italic)
            FormatButton(title: "Link", icon: "link", action: .link)
            FormatButton(title: "Code", icon: "chevron.left.forwardslash.chevron.right", action: .code)
            Divider().frame(height: 18)
            FormatButton(title: "Bulleted list", icon: "list.bullet", action: .bulletedList)
            FormatButton(title: "Numbered list", icon: "list.number", action: .numberedList)
            FormatButton(title: "Checklist", icon: "checklist", action: .checklist)
            FormatButton(title: "Quote", icon: "text.quote", action: .quote)
            Spacer()
            Text(verbatim: workspace.selectedKind == .markdown ? "Markdown underneath" : "HTML underneath")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 10)
        .frame(height: 38)
        .background(.bar)
    }
}

private struct FormatButton: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    let title: String
    let icon: String
    let action: FormattingAction

    var body: some View {
        Button { workspace.apply(action) } label: {
            Image(systemName: icon)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(title)
    }
}

private struct MainToolbar: ToolbarContent {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button(action: { workspace.beginRename() }) {
                Label("Rename", systemImage: "pencil")
            }
            .help("Rename selected item")
            .disabled(workspace.selectedURL == nil)

            Menu {
                Button("Markdown Note") { workspace.beginCreateDocument(kind: .markdown) }
                Button("HTML Document") { workspace.beginCreateDocument(kind: .html) }
                Button("Folder") { workspace.beginCreateFolder() }
            } label: {
                Label("New", systemImage: "plus")
            }
        }
    }
}

private struct WelcomeView: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "text.book.closed.fill")
                .font(.system(size: 58))
                .foregroundStyle(.tint)
            Text("Your ideas, in files you own.")
                .font(.largeTitle.weight(.semibold))
            Text("Create a Markdown note or HTML document. Everything is saved automatically as a normal file in your Documents folder.")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            HStack {
                Button("New Markdown Note") { workspace.beginCreateDocument(kind: .markdown) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                Button("New HTML Document") { workspace.beginCreateDocument(kind: .html) }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
            }
            Button("Choose a Different Library Folder…") { workspace.chooseRootFolder() }
                .buttonStyle(.link)
        }
        .padding(40)
    }
}

private struct ItemNameSheet: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isNameFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(workspace.namingIntent?.title ?? "Name Item").font(.headline)
            TextField("Name", text: $workspace.nameDraft)
                .textFieldStyle(.roundedBorder)
                .focused($isNameFocused)
                .onSubmit { submit() }
            if let hint = workspace.namingHint {
                Text(hint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let error = workspace.namingError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") {
                    workspace.cancelNaming()
                    dismiss()
                }
                Button(workspace.namingIntent?.actionTitle ?? "Save") { submit() }
                    .buttonStyle(.borderedProminent)
                    .disabled(workspace.nameDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 390)
        .onAppear { isNameFocused = true }
    }

    private func submit() {
        if workspace.confirmNaming() { dismiss() }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var workspace: WorkspaceStore

    var body: some View {
        Form {
            Section("Library") {
                LabeledContent("Current folder") {
                    Text(verbatim: workspace.rootURL.path)
                        .lineLimit(2)
                        .multilineTextAlignment(.trailing)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Button("Choose Folder…") { workspace.chooseRootFolder() }
                    Button("Show in Finder") { workspace.revealRoot() }
                }
            }
            Section {
                Text("MyMarkdown stores ordinary .md and .html files. You can open the same folder from Claude, Codex, Copilot, Finder, or any other editor.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

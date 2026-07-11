import SwiftUI

@main
struct MarkPadApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(state)
                .frame(minWidth: 760, minHeight: 480)
        }
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New File…") {
                    NotificationCenter.default.post(name: .markPadCommand,
                                                    object: MarkPadCommand.newFile)
                }
                .keyboardShortcut("n")
                Button("New Folder…") {
                    NotificationCenter.default.post(name: .markPadCommand,
                                                    object: MarkPadCommand.newFolder)
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }

            CommandGroup(replacing: .saveItem) {
                Button("Save") {
                    state.isDirty = true
                    state.saveCurrent()
                }
                .keyboardShortcut("s")
                .disabled(state.currentFile == nil)
            }

            CommandGroup(after: .saveItem) {
                Divider()
                Button("Import from Apple Notes…") {
                    importFromNotes()
                }
                Button("Reveal in Finder") {
                    state.revealInFinder(nil)
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
            }

            CommandMenu("Format") {
                Button("Bold") {
                    state.mode == .markdown
                        ? state.format.wrapSelection("**", "**")
                        : state.format.wrapSelection("<strong>", "</strong>")
                }
                .keyboardShortcut("b")
                Button("Italic") {
                    state.mode == .markdown
                        ? state.format.wrapSelection("*", "*")
                        : state.format.wrapSelection("<em>", "</em>")
                }
                .keyboardShortcut("i")
                Button("Insert Link") {
                    state.mode == .markdown
                        ? state.format.wrapSelection("[", "](url)")
                        : state.format.wrapSelection("<a href=\"url\">", "</a>")
                }
                .keyboardShortcut("k")
                Divider()
                Button("Heading 1") { state.format.toggleLinePrefix("# ") }
                    .keyboardShortcut("1", modifiers: [.command, .option])
                Button("Heading 2") { state.format.toggleLinePrefix("## ") }
                    .keyboardShortcut("2", modifiers: [.command, .option])
                Button("Heading 3") { state.format.toggleLinePrefix("### ") }
                    .keyboardShortcut("3", modifiers: [.command, .option])
                Divider()
                Button("Bullet List") { state.format.toggleLinePrefix("- ") }
                    .keyboardShortcut("l", modifiers: [.command, .shift])
                Button("Block Quote") { state.format.toggleLinePrefix("> ") }
                Button("Code Block") { state.format.insertSnippet("\n```\ncode\n```\n") }
                Divider()
                Button("Toggle Preview") { state.showPreview.toggle() }
                    .keyboardShortcut("p", modifiers: [.command, .shift])
            }
        }
    }

    private func importFromNotes() {
        state.statusMessage = "Importing from Apple Notes…"
        DispatchQueue.main.async {
            do {
                let result = try NotesImporter.importNotes(into: state.rootURL)
                state.refreshTree()
                state.statusMessage = "Imported \(result.imported) notes"
                    + (result.skipped > 0 ? " (\(result.skipped) skipped)" : "")
            } catch {
                state.errorMessage = "Apple Notes import failed: \(error.localizedDescription)"
                state.statusMessage = "Ready"
            }
        }
    }
}

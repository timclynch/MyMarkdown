import SwiftUI

@main
struct MyMarkdownApp: App {
    @StateObject private var workspace = WorkspaceStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(workspace)
                .frame(minWidth: 920, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .commands {
            AppCommands(workspace: workspace)
        }

        Settings {
            SettingsView()
                .environmentObject(workspace)
                .frame(width: 520, height: 220)
        }
    }
}

struct AppCommands: Commands {
    @ObservedObject var workspace: WorkspaceStore

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("New Markdown Note") { workspace.beginCreateDocument(kind: .markdown) }
                .keyboardShortcut("n", modifiers: [.command])
            Button("New HTML Document") { workspace.beginCreateDocument(kind: .html) }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            Button("New Folder") { workspace.beginCreateFolder() }
                .keyboardShortcut("n", modifiers: [.command, .option])
        }

        CommandMenu("Format") {
            Button("Heading") { workspace.apply(.heading) }
                .keyboardShortcut("1", modifiers: [.command, .option])
            Button("Bold") { workspace.apply(.bold) }
                .keyboardShortcut("b", modifiers: [.command])
            Button("Italic") { workspace.apply(.italic) }
                .keyboardShortcut("i", modifiers: [.command])
            Divider()
            Button("Bulleted List") { workspace.apply(.bulletedList) }
                .keyboardShortcut("8", modifiers: [.command, .shift])
            Button("Checklist") { workspace.apply(.checklist) }
            Button("Link") { workspace.apply(.link) }
                .keyboardShortcut("k", modifiers: [.command])
            Button("Code") { workspace.apply(.code) }
        }
    }
}

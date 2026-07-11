import Foundation

enum DocumentKind: String, CaseIterable, Identifiable {
    case markdown = "md"
    case html = "html"

    var id: String { rawValue }
    var displayName: String { self == .markdown ? "Markdown" : "HTML" }
    var icon: String { self == .markdown ? "text.document" : "chevron.left.forwardslash.chevron.right" }
}

enum EditorMode: String, CaseIterable, Identifiable {
    case write = "Write"
    case preview = "Preview"
    case split = "Split"

    var id: String { rawValue }
    var icon: String {
        switch self {
        case .write: "square.and.pencil"
        case .preview: "eye"
        case .split: "rectangle.split.2x1"
        }
    }
}

enum FormattingAction {
    case heading, bold, italic, bulletedList, numberedList, checklist, quote, link, code
}

struct FileNode: Identifiable, Hashable {
    let url: URL
    let isDirectory: Bool
    var children: [FileNode]?

    var id: String { url.path }
    var name: String { url.deletingPathExtension().lastPathComponent }
    var kind: DocumentKind? { DocumentKind(rawValue: url.pathExtension.lowercased()) }
    var icon: String {
        if isDirectory { return "folder" }
        return kind?.icon ?? "doc"
    }
}

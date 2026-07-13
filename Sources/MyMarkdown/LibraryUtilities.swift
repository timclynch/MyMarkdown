import Foundation

enum ItemNameValidator {
    static func normalizedBaseName(_ rawName: String, fileExtension: String? = nil) throws -> String {
        var name = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
        if let fileExtension, name.lowercased().hasSuffix(".\(fileExtension.lowercased())") {
            name.removeLast(fileExtension.count + 1)
            name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        guard !name.isEmpty else { throw ItemNameError.empty }
        guard name != ".", name != ".." else { throw ItemNameError.reserved }
        guard !name.contains("/"), !name.contains(":"), !name.contains("\0") else { throw ItemNameError.invalidCharacters }
        return name
    }
}

enum ItemNameError: LocalizedError, Equatable {
    case empty
    case reserved
    case invalidCharacters
    case alreadyExists

    var errorDescription: String? {
        switch self {
        case .empty: "Enter a name."
        case .reserved: "That name is reserved by macOS."
        case .invalidCharacters: "Names cannot contain /, :, or null characters."
        case .alreadyExists: "An item with that name already exists in this folder."
        }
    }
}

enum LibraryItemOperations {
    static func destinationURL(for oldURL: URL, baseName: String, isDirectory: Bool) -> URL {
        var result = oldURL.deletingLastPathComponent().appendingPathComponent(baseName, isDirectory: isDirectory)
        if !isDirectory, !oldURL.pathExtension.isEmpty {
            result = result.appendingPathExtension(oldURL.pathExtension)
        }
        return result
    }

    static func moveItem(at oldURL: URL, to newURL: URL, fileManager: FileManager = .default) throws {
        guard oldURL != newURL else { return }
        guard !fileManager.fileExists(atPath: newURL.path) else { throw ItemNameError.alreadyExists }
        try fileManager.moveItem(at: oldURL, to: newURL)
    }

    static func remappedURL(_ selectedURL: URL?, movingFrom oldURL: URL, to newURL: URL) -> URL? {
        guard let selectedURL else { return nil }
        let oldPath = oldURL.standardizedFileURL.path
        let selectedPath = selectedURL.standardizedFileURL.path
        guard selectedPath == oldPath || selectedPath.hasPrefix(oldPath + "/") else { return selectedURL }
        let suffix = String(selectedPath.dropFirst(oldPath.count))
        return URL(fileURLWithPath: newURL.standardizedFileURL.path + suffix, isDirectory: selectedURL.hasDirectoryPath)
    }
}

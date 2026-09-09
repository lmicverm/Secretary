import Foundation

/// Builds and names the on-disk Secretary library tree.
public struct FolderSchema: Sendable {
    public static let inboxFolder = "Inbox"
    public static let dropFolder = "Drop"
    public static let archiveFolder = "Archive"
    /// Archived files older than this are moved to the system Trash.
    public static let archiveRetentionDays = 30
    public static let metaFolder = ".secretary"
    public static let indexFilename = "index.sqlite"
    public static let thumbsFolder = "thumbs"

    public let categories: [DocumentCategory]

    public init(categories: [DocumentCategory] = DefaultTaxonomy.all) {
        self.categories = categories
    }

    public func ensureLibraryStructure(at root: URL, fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: root.appendingPathComponent(Self.inboxFolder), withIntermediateDirectories: true)

        let drop = root.appendingPathComponent(Self.dropFolder)
        try fileManager.createDirectory(at: drop, withIntermediateDirectories: true)
        let readme = drop.appendingPathComponent("README - drop files here.txt")
        if !fileManager.fileExists(atPath: readme.path) {
            let text = """
            Secretary Drop folder
            ====================

            This folder lives inside your Secretary library:
            \(drop.path)

            Put any PDF, photo, or document here (AirDrop, Save As, email attachment save, Finder copy…).

            When you open the Secretary app (or tap “Scan Drop folder”), files here are moved into Inbox
            and wait for classification.

            Tip: bookmark this folder in Finder / Files for one-click dumping.
            To move Drop, change the library folder in Settings → Library.
            """
            try text.write(to: readme, atomically: true, encoding: .utf8)
        }

        let archive = root.appendingPathComponent(Self.archiveFolder)
        try fileManager.createDirectory(at: archive, withIntermediateDirectories: true)
        let archiveReadme = archive.appendingPathComponent("README - archive.txt")
        if !fileManager.fileExists(atPath: archiveReadme.path) {
            let text = """
            Secretary Archive
            =================

            Documents you remove from the app are moved here (not deleted silently).

            After \(Self.archiveRetentionDays) days, Secretary moves them to the system Trash / Bin.
            You can open this folder anytime to restore a file into Inbox manually.
            """
            try text.write(to: archiveReadme, atomically: true, encoding: .utf8)
        }

        let meta = root.appendingPathComponent(Self.metaFolder)
        try fileManager.createDirectory(at: meta, withIntermediateDirectories: true)

        // Thumbs stay local-friendly; still create folder but mark excluded from backup when possible.
        let thumbs = meta.appendingPathComponent(Self.thumbsFolder)
        try fileManager.createDirectory(at: thumbs, withIntermediateDirectories: true)
        var thumbsValues = URLResourceValues()
        thumbsValues.isExcludedFromBackup = true
        var thumbsURL = thumbs
        try? thumbsURL.setResourceValues(thumbsValues)

        for category in categories {
            let url = root.appendingPathComponent(category.relativePath)
            try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        }
    }

    public func categoryURL(root: URL, space: DocumentSpace, category: String, year: Int?) -> URL {
        var url = root.appendingPathComponent(space.rawValue).appendingPathComponent(category)
        if let yearFolder = Self.yearFolderName(year) {
            url = url.appendingPathComponent(yearFolder)
        }
        return url
    }

    /// Only clean four-digit years become folder names (never "2024.0").
    public static func yearFolderName(_ year: Int?) -> String? {
        guard let year, (1990...2100).contains(year) else { return nil }
        return String(format: "%04d", year)
    }

    public static func normalizedYear(_ year: Int?) -> Int? {
        guard let year, (1990...2100).contains(year) else { return nil }
        return year
    }

    /// `YYYY-MM-DD__type__short-title.ext`
    public static func makeFilename(
        date: Date = Date(),
        documentType: String,
        shortTitle: String,
        pathExtension: String
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let day = formatter.string(from: date)
        let type = sanitize(documentType)
        let title = sanitize(shortTitle)
        let ext = pathExtension.hasPrefix(".") ? String(pathExtension.dropFirst()) : pathExtension
        return "\(day)__\(type)__\(title).\(ext.lowercased())"
    }

    public static func sanitize(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let replaced = trimmed
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "-")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_."))
        let filtered = replaced.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" }
        let collapsed = String(filtered)
            .replacingOccurrences(of: "--+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        return collapsed.isEmpty ? "document" : collapsed.lowercased()
    }

    public static func parsePath(_ relativePath: String) -> (space: DocumentSpace?, category: String?, year: Int?, isInbox: Bool) {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard let first = parts.first else {
            return (nil, nil, nil, false)
        }
        if first == inboxFolder {
            return (nil, nil, nil, true)
        }
        if first == archiveFolder || first == dropFolder {
            return (nil, nil, nil, false)
        }
        let space = DocumentSpace(rawValue: first)
        let category = parts.count > 1 ? parts[1] : nil
        var year: Int?
        if parts.count > 2, let y = Int(parts[2]), (1990...2100).contains(y) {
            year = y
        }
        return (space, category, year, false)
    }
}

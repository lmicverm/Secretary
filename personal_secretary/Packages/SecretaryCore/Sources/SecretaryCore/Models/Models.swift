import Foundation

/// Top-level life contexts for documents.
public enum DocumentSpace: String, CaseIterable, Codable, Sendable, Identifiable {
    case personal = "Personal"
    case bv = "BV"

    public var id: String { rawValue }

    public var displayName: String { rawValue }
}

/// A category under a space (folder name on disk).
public struct DocumentCategory: Hashable, Codable, Sendable, Identifiable {
    public var id: String { "\(space.rawValue)/\(name)" }
    public var space: DocumentSpace
    public var name: String

    public init(space: DocumentSpace, name: String) {
        self.space = space
        self.name = name
    }

    public var relativePath: String { "\(space.rawValue)/\(name)" }
}

/// Default taxonomy matching Belgian personal + BV life.
public enum DefaultTaxonomy {
    public static let personalCategories: [String] = [
        "Insurance",
        "Tax",
        "Banking",
        "School",
        "Housing",
        "Identity",
        "Health",
        "Vehicles",
        "Work"
    ]

    public static let bvCategories: [String] = [
        "Governance",
        "Tax",
        "Accounting",
        "Banking",
        "Insurance",
        "SocialSecretariat",
        "Contracts",
        "Invoices"
    ]

    public static var all: [DocumentCategory] {
        personalCategories.map { DocumentCategory(space: .personal, name: $0) }
            + bvCategories.map { DocumentCategory(space: .bv, name: $0) }
    }
}

/// Indexed document metadata. Files on disk are the source of truth.
public struct DocumentRecord: Identifiable, Hashable, Codable, Sendable {
    public var id: String
    public var relativePath: String
    public var filename: String
    /// Original name when the file was first imported (source copy is never modified).
    public var originalFilename: String
    public var space: DocumentSpace?
    public var category: String?
    public var year: Int?
    public var title: String
    public var notes: String
    public var tags: [String]
    public var contentHash: String?
    public var ocrText: String
    public var isFavorite: Bool
    public var expiryDate: Date?
    public var archivedAt: Date?
    public var fileSize: Int64
    public var createdAt: Date
    public var modifiedAt: Date
    public var indexedAt: Date

    public init(
        id: String = UUID().uuidString,
        relativePath: String,
        filename: String,
        originalFilename: String = "",
        space: DocumentSpace? = nil,
        category: String? = nil,
        year: Int? = nil,
        title: String = "",
        notes: String = "",
        tags: [String] = [],
        contentHash: String? = nil,
        ocrText: String = "",
        isFavorite: Bool = false,
        expiryDate: Date? = nil,
        archivedAt: Date? = nil,
        fileSize: Int64 = 0,
        createdAt: Date = Date(),
        modifiedAt: Date = Date(),
        indexedAt: Date = Date()
    ) {
        self.id = id
        self.relativePath = relativePath
        self.filename = filename
        self.originalFilename = originalFilename
        self.space = space
        self.category = category
        self.year = year
        let seedName = originalFilename.isEmpty ? filename : originalFilename
        self.title = title.isEmpty ? DocumentTitleGenerator.titleFromFilename(seedName) : title
        self.notes = notes
        self.tags = tags
        self.contentHash = contentHash
        self.ocrText = ocrText
        self.isFavorite = isFavorite
        self.expiryDate = expiryDate
        self.archivedAt = archivedAt
        self.fileSize = fileSize
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt
        self.indexedAt = indexedAt
    }

    public var isInbox: Bool {
        relativePath.hasPrefix("Inbox/") || relativePath == "Inbox"
    }

    public var isArchived: Bool {
        archivedAt != nil || relativePath.hasPrefix("\(FolderSchema.archiveFolder)/")
    }

    public var displayTitle: String {
        title.isEmpty ? DocumentTitleGenerator.titleFromFilename(originalFilename.isEmpty ? filename : originalFilename) : title
    }

    /// Filename shown under the title (prefer the user's original name).
    public var displayFilename: String {
        if !originalFilename.isEmpty { return originalFilename }
        return filename
    }

    public static func defaultTitle(from filename: String) -> String {
        DocumentTitleGenerator.titleFromFilename(filename)
    }
}

/// Classification target when moving out of Inbox.
public struct ClassificationTarget: Hashable, Sendable {
    public var space: DocumentSpace
    public var category: String
    public var year: Int?
    public var documentType: String
    public var shortTitle: String
    public var notes: String
    public var tags: [String]
    public var expiryDate: Date?

    public init(
        space: DocumentSpace,
        category: String,
        year: Int? = nil,
        documentType: String = "document",
        shortTitle: String,
        notes: String = "",
        tags: [String] = [],
        expiryDate: Date? = nil
    ) {
        self.space = space
        self.category = category
        self.year = year
        self.documentType = documentType
        self.shortTitle = shortTitle
        self.notes = notes
        self.tags = tags
        self.expiryDate = expiryDate
    }
}

/// Search / browse filters.
public struct DocumentFilter: Hashable, Sendable {
    public var query: String
    public var space: DocumentSpace?
    public var category: String?
    public var year: Int?
    public var inboxOnly: Bool
    public var favoritesOnly: Bool
    public var archiveOnly: Bool
    public var expiringWithinDays: Int?

    public init(
        query: String = "",
        space: DocumentSpace? = nil,
        category: String? = nil,
        year: Int? = nil,
        inboxOnly: Bool = false,
        favoritesOnly: Bool = false,
        archiveOnly: Bool = false,
        expiringWithinDays: Int? = nil
    ) {
        self.query = query
        self.space = space
        self.category = category
        self.year = year
        self.inboxOnly = inboxOnly
        self.favoritesOnly = favoritesOnly
        self.archiveOnly = archiveOnly
        self.expiringWithinDays = expiringWithinDays
    }
}

import Foundation

/// A year + document-type section in a category list.
public struct DocumentListSection: Identifiable, Equatable, Sendable {
    public var id: String { "\(yearLabel)|\(typeLabel)" }
    public var year: Int?
    public var documentType: String
    public var documents: [DocumentRecord]

    public init(year: Int?, documentType: String, documents: [DocumentRecord]) {
        self.year = year
        self.documentType = documentType
        self.documents = documents
    }

    public var yearLabel: String {
        year.map(String.init) ?? "No year"
    }

    public var typeLabel: String {
        let raw = documentType.replacingOccurrences(of: "-", with: " ")
        guard let first = raw.first else { return "Document" }
        return String(first).uppercased() + raw.dropFirst()
    }

    public var title: String {
        "\(yearLabel) · \(typeLabel)"
    }
}

/// Groups classified documents by year (newest first), then document type.
public enum DocumentListGrouping {
    public static func shouldGroup(filter: DocumentFilter) -> Bool {
        let query = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
        return filter.category != nil
            && !filter.inboxOnly
            && query.isEmpty
    }

    public static func sections(from documents: [DocumentRecord]) -> [DocumentListSection] {
        var buckets: [String: [DocumentRecord]] = [:]
        var order: [(year: Int?, type: String)] = []

        for document in documents {
            let year = document.year ?? FolderSchema.parsePath(document.relativePath).year
            let type = FolderSchema.documentType(fromFilename: document.filename) ?? "document"
            let key = "\(year.map(String.init) ?? "")|\(type)"
            if buckets[key] == nil {
                order.append((year, type))
            }
            buckets[key, default: []].append(document)
        }

        order.sort { lhs, rhs in
            switch (lhs.year, rhs.year) {
            case let (l?, r?) where l != r:
                return l > r
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            default:
                return lhs.type.localizedCaseInsensitiveCompare(rhs.type) == .orderedAscending
            }
        }

        return order.map { year, type in
            let key = "\(year.map(String.init) ?? "")|\(type)"
            let rows = (buckets[key] ?? []).sorted { lhs, rhs in
                listingDate(lhs) > listingDate(rhs)
            }
            return DocumentListSection(year: year, documentType: type, documents: rows)
        }
    }

    public static func listingDate(_ document: DocumentRecord) -> Date {
        FolderSchema.documentDate(fromFilename: document.filename)
            ?? document.modifiedAt
    }
}

import Foundation
import UniformTypeIdentifiers

/// Main façade: folder tree + index. Files are source of truth.
public final class DocumentLibrary: @unchecked Sendable {
    public let rootURL: URL
    public let schema: FolderSchema
    private let index: DocumentIndex
    private let learningStore: ClassificationLearningStore
    private let ignoredPaths: IgnoredPathsStore
    private let fileManager: FileManager
    private let queue = DispatchQueue(label: "be.secretary.DocumentLibrary", qos: .userInitiated)

    public init(
        rootURL: URL = LibraryLocation.resolveRoot(),
        schema: FolderSchema = FolderSchema(),
        fileManager: FileManager = .default
    ) throws {
        self.rootURL = rootURL
        self.schema = schema
        self.fileManager = fileManager
        try schema.ensureLibraryStructure(at: rootURL, fileManager: fileManager)
        let dbURL = rootURL
            .appendingPathComponent(FolderSchema.metaFolder)
            .appendingPathComponent(FolderSchema.indexFilename)
        self.index = try DocumentIndex(databaseURL: dbURL)
        self.learningStore = ClassificationLearningStore(libraryRoot: rootURL)
        self.ignoredPaths = IgnoredPathsStore(libraryRoot: rootURL)
    }

    public var indexDatabaseURL: URL {
        rootURL.appendingPathComponent(FolderSchema.metaFolder).appendingPathComponent(FolderSchema.indexFilename)
    }

    public var inboxURL: URL {
        rootURL.appendingPathComponent(FolderSchema.inboxFolder)
    }

    public var dropURL: URL {
        rootURL.appendingPathComponent(FolderSchema.dropFolder)
    }

    // MARK: - Import

    /// Move loose files from Drop/ into Inbox/ for classification.
    @discardableResult
    public func ingestDropFolder() throws -> [DocumentRecord] {
        try queue.sync {
            try schema.ensureLibraryStructure(at: rootURL, fileManager: fileManager)
            let contents = try fileManager.contentsOfDirectory(
                at: dropURL,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
                options: [.skipsHiddenFiles]
            )
            var imported: [DocumentRecord] = []
            for url in contents {
                let name = url.lastPathComponent
                if name.hasPrefix("README") { continue }
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }

                let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
                let filename = FolderSchema.makeFilename(
                    documentType: "drop",
                    shortTitle: url.deletingPathExtension().lastPathComponent,
                    pathExtension: ext
                )
                let dest = uniqueURL(in: inboxURL, filename: filename)
                try CloudFileCoordinator.coordinatedWrite(to: dest, options: .forReplacing) { newURL in
                    if fileManager.fileExists(atPath: newURL.path) {
                        try fileManager.removeItem(at: newURL)
                    }
                    try fileManager.moveItem(at: url, to: newURL)
                }
                imported.append(try indexFile(at: dest, preserveMetadata: nil))
            }
            return imported
        }
    }

    @discardableResult
    public func importFile(from sourceURL: URL, preferredName: String? = nil) throws -> DocumentRecord {
        try queue.sync {
            let accessing = sourceURL.startAccessingSecurityScopedResource()
            defer { if accessing { sourceURL.stopAccessingSecurityScopedResource() } }
            if !accessing {
                NSLog("Secretary: importFile has no security-scoped access for \(sourceURL.lastPathComponent)")
            }

            let ext = sourceURL.pathExtension.isEmpty ? "pdf" : sourceURL.pathExtension
            let base = preferredName ?? sourceURL.deletingPathExtension().lastPathComponent
            let filename = FolderSchema.makeFilename(
                documentType: "import",
                shortTitle: base,
                pathExtension: ext
            )
            let dest = uniqueURL(in: inboxURL, filename: filename)

            try CloudFileCoordinator.coordinatedWrite(to: dest, options: .forReplacing) { newURL in
                if fileManager.fileExists(atPath: newURL.path) {
                    try fileManager.removeItem(at: newURL)
                }
                try fileManager.copyItem(at: sourceURL, to: newURL)
            }

            return try indexFile(at: dest, preserveMetadata: nil)
        }
    }

    @discardableResult
    public func importData(_ data: Data, filenameHint: String, pathExtension: String) throws -> DocumentRecord {
        try queue.sync {
            let filename = FolderSchema.makeFilename(
                documentType: "scan",
                shortTitle: filenameHint,
                pathExtension: pathExtension
            )
            let dest = uniqueURL(in: inboxURL, filename: filename)
            try CloudFileCoordinator.coordinatedWrite(to: dest, options: .forReplacing) { newURL in
                try data.write(to: newURL, options: .atomic)
            }
            return try indexFile(at: dest, preserveMetadata: nil)
        }
    }

    // MARK: - Classify

    @discardableResult
    public func classify(documentID: String, as target: ClassificationTarget) throws -> DocumentRecord {
        try queue.sync {
            guard var record = try index.fetch(id: documentID) else {
                throw LibraryError.documentNotFound
            }
            let source = rootURL.appendingPathComponent(record.relativePath)
            guard fileManager.fileExists(atPath: source.path) else {
                throw LibraryError.fileMissing(record.relativePath)
            }

            let folder = schema.categoryURL(
                root: rootURL,
                space: target.space,
                category: target.category,
                year: FolderSchema.normalizedYear(target.year)
            )
            try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)

            let ext = (record.filename as NSString).pathExtension
            let fields = DocumentUnderstanding.extract(
                from: record,
                preferredTitle: target.shortTitle,
                preferredType: target.documentType,
                preferredTags: target.tags
            )
            let cleanTitle = fields.title
            let cleanType = fields.documentType
            let fileDate = target.documentDate
                ?? fields.documentDate
                ?? FolderSchema.documentDate(fromFilename: record.filename)
                ?? Date()
            let newName = FolderSchema.makeFilename(
                date: fileDate,
                documentType: cleanType,
                shortTitle: cleanTitle,
                pathExtension: ext
            )
            let dest = uniqueURL(in: folder, filename: newName)

            try CloudFileCoordinator.coordinatedWrite(to: dest, options: .forReplacing) { newURL in
                try fileManager.moveItem(at: source, to: newURL)
            }

            let relative = relativePath(for: dest)
            let parsed = FolderSchema.parsePath(relative)
            record.relativePath = relative
            record.filename = dest.lastPathComponent
            record.space = parsed.space
            record.category = parsed.category
            record.year = FolderSchema.normalizedYear(parsed.year ?? target.year)
            record.title = cleanTitle
            record.notes = target.notes
            if !target.tags.isEmpty {
                record.tags = target.tags
            } else if record.tags.isEmpty {
                record.tags = fields.tags.isEmpty
                    ? ClassificationSuggester.suggestedTags(
                        for: record,
                        space: target.space,
                        category: target.category,
                        year: FolderSchema.normalizedYear(parsed.year ?? target.year),
                        documentType: cleanType
                    )
                    : fields.tags
            }
            record.expiryDate = target.expiryDate ?? record.expiryDate ?? fields.dueDate
            if fields.looksLikeInvoice, record.paymentStatus == .notApplicable {
                record.paymentStatus = .unpaid
            }
            record.tags = record.paymentStatus.syncedTags(record.tags)
            record.modifiedAt = Date()
            record.indexedAt = Date()
            try index.upsert(record)
            learningStore.learn(from: record, target: target)
            return record
        }
    }

    // MARK: - Remove from app (never deletes on-disk files)

    /// Removes the document from the app index only. The file on disk is left untouched.
    public func removeFromLibrary(documentID: String) throws {
        try queue.sync {
            guard let record = try index.fetch(id: documentID) else {
                throw LibraryError.documentNotFound
            }
            ignoredPaths.ignore(record.relativePath)
            try index.delete(id: record.id)
            SpotlightIndexer.remove(ids: [record.id])
            ExpiryReminderService.cancel(documentID: record.id)
        }
    }

    // MARK: - Suggestions

    public func suggestions(for document: DocumentRecord, limit: Int = 5) throws -> [ClassificationSuggestion] {
        let catalog = try index.fetchAll()
        return ClassificationSuggester.suggestions(
            for: document,
            catalog: catalog,
            learning: learningStore,
            limit: limit
        )
    }

    // MARK: - Update metadata

    public func updateMetadata(
        documentID: String,
        title: String? = nil,
        notes: String? = nil,
        tags: [String]? = nil,
        isFavorite: Bool? = nil,
        expiryDate: Date?? = nil,
        ocrText: String? = nil,
        paymentStatus: PaymentStatus? = nil,
        paidAt: Date?? = nil
    ) throws -> DocumentRecord {
        try queue.sync {
            guard var record = try index.fetch(id: documentID) else {
                throw LibraryError.documentNotFound
            }
            if let title { record.title = title }
            if let notes { record.notes = notes }
            if let isFavorite {
                record.isFavorite = isFavorite
                if isFavorite {
                    let url = rootURL.appendingPathComponent(record.relativePath)
                    try? CloudFileCoordinator.pinForOffline(url)
                }
            }
            if let expiryDate { record.expiryDate = expiryDate }
            if let ocrText { record.ocrText = ocrText }
            if let paymentStatus { record.paymentStatus = paymentStatus }
            if let paidAt { record.paidAt = paidAt }
            if paymentStatus != nil || (tags != nil && (tags?.contains(where: { ["paid", "unpaid"].contains($0.lowercased()) }) == true)) {
                record.tags = record.paymentStatus.syncedTags(record.tags)
            }
            if let tags {
                if tags.isEmpty, record.tags.isEmpty {
                    record.tags = ClassificationSuggester.suggestedTags(for: record)
                } else {
                    record.tags = tags
                }
            } else if record.tags.isEmpty {
                record.tags = ClassificationSuggester.suggestedTags(for: record)
            }
            record.modifiedAt = Date()
            record.indexedAt = Date()
            try index.upsert(record)
            return record
        }
    }

    // MARK: - Query

    public func search(_ filter: DocumentFilter = DocumentFilter()) throws -> [DocumentRecord] {
        try index.search(filter)
    }

    public func document(id: String) throws -> DocumentRecord? {
        try index.fetch(id: id)
    }

    public func fileURL(for record: DocumentRecord) -> URL {
        rootURL.appendingPathComponent(record.relativePath)
    }

    public func duplicates(of record: DocumentRecord) throws -> [DocumentRecord] {
        guard let hash = record.contentHash else { return [] }
        return try index.findByHash(hash, excludingID: record.id)
    }

    public func ensureDownloaded(for record: DocumentRecord) throws -> Bool {
        try CloudFileCoordinator.ensureDownloaded(fileURL(for: record))
    }

    // MARK: - Rebuild

    public func rebuildIndex(ocrProvider: ((URL) -> String)? = nil) throws -> Int {
        try queue.sync {
            try index.clearAll()
            var count = 0
            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey, .creationDateKey],
                options: [.skipsHiddenFiles]
            )
            while let url = enumerator?.nextObject() as? URL {
                if url.path.contains("/\(FolderSchema.metaFolder)/") { continue }
                if url.path.contains("/\(FolderSchema.dropFolder)/") { continue }
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                let relative = relativePath(for: url)
                if ignoredPaths.contains(relative) { continue }
                let ocr = ocrProvider?(url) ?? ""
                _ = try indexFile(at: url, preserveMetadata: nil, ocrText: ocr)
                count += 1
            }
            return count
        }
    }

    public func refreshFromDisk() throws {
        try queue.sync {
            let existing = Dictionary(uniqueKeysWithValues: try index.fetchAll().map { ($0.relativePath, $0) })
            var seen = Set<String>()
            let enumerator = fileManager.enumerator(
                at: rootURL,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            while let url = enumerator?.nextObject() as? URL {
                if url.path.contains("/\(FolderSchema.metaFolder)/") { continue }
                if url.path.contains("/\(FolderSchema.dropFolder)/") { continue }
                var isDir: ObjCBool = false
                guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                let relative = relativePath(for: url)
                if ignoredPaths.contains(relative) { continue }
                seen.insert(relative)
                _ = try indexFile(at: url, preserveMetadata: existing[relative])
            }
            for (path, record) in existing where !seen.contains(path) {
                try index.delete(id: record.id)
            }
        }
    }

    public func addCategory(_ category: DocumentCategory) throws {
        let url = rootURL.appendingPathComponent(category.relativePath)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }

    // MARK: - Internals

    private func indexFile(at url: URL, preserveMetadata: DocumentRecord?, ocrText: String = "") throws -> DocumentRecord {
        let relative = relativePath(for: url)
        let parsed = FolderSchema.parsePath(relative)
        let values = try url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey])
        let hash = try? ContentHasher.sha256(of: url)

        var record = preserveMetadata ?? DocumentRecord(
            relativePath: relative,
            filename: url.lastPathComponent
        )
        record.relativePath = relative
        record.filename = url.lastPathComponent
        record.space = parsed.space
        record.category = parsed.category
        record.year = parsed.year
        if record.title.isEmpty {
            record.title = DocumentRecord.defaultTitle(from: url.lastPathComponent)
        }
        if !ocrText.isEmpty {
            record.ocrText = ocrText
        }
        record.contentHash = hash
        record.fileSize = Int64(values.fileSize ?? 0)
        record.createdAt = values.creationDate ?? record.createdAt
        record.modifiedAt = values.contentModificationDate ?? Date()
        record.indexedAt = Date()
        try index.upsert(record)
        return record
    }

    private func relativePath(for url: URL) -> String {
        let rootPath = rootURL.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        if path.hasPrefix(rootPath) {
            let sliced = String(path.dropFirst(rootPath.count))
            return sliced.hasPrefix("/") ? String(sliced.dropFirst()) : sliced
        }
        return url.lastPathComponent
    }

    private func uniqueURL(in directory: URL, filename: String) -> URL {
        var candidate = directory.appendingPathComponent(filename)
        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var i = 2
        repeat {
            let name = ext.isEmpty ? "\(base)-\(i)" : "\(base)-\(i).\(ext)"
            candidate = directory.appendingPathComponent(name)
            i += 1
        } while fileManager.fileExists(atPath: candidate.path)
        return candidate
    }

    public enum LibraryError: Error, LocalizedError {
        case documentNotFound
        case fileMissing(String)

        public var errorDescription: String? {
            switch self {
            case .documentNotFound: return "Document not found in index."
            case .fileMissing(let p): return "File missing on disk: \(p)"
            }
        }
    }
}

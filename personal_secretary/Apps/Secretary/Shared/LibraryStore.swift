import Foundation
import SecretaryCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

@MainActor
public final class LibraryStore: ObservableObject {
    @Published public private(set) var documents: [DocumentRecord] = []
    @Published public private(set) var inboxCount: Int = 0
    @Published public private(set) var personalCategories: [String] = DefaultTaxonomy.personalCategories
    @Published public private(set) var bvCategories: [String] = DefaultTaxonomy.bvCategories
    @Published public var filter = DocumentFilter()
    @Published public var errorMessage: String?
    @Published public var isBusy = false
    @Published public var statusMessage: String?
    @Published public private(set) var rootPath: String = ""
    @Published public private(set) var usingiCloud = false
    @Published public private(set) var usingCustomRoot = false
    @Published public var pendingSettingsTab: String?
    @Published public private(set) var mailboxConfigured = false
    @Published public private(set) var mailboxEmail: String?

    public private(set) var library: DocumentLibrary?
    private var accessedRootURL: URL?

    public func document(id: String) -> DocumentRecord? {
        try? library?.document(id: id)
    }

    public init() {}

    public func bootstrap() {
        do {
            if let old = accessedRootURL {
                LibraryLocation.stopAccessing(old)
                accessedRootURL = nil
            }

            let root: URL
            if let custom = LibraryLocation.beginAccessingCustomRoot() {
                accessedRootURL = custom
                root = custom
            } else {
                root = LibraryLocation.resolveRoot()
            }

            let lib = try DocumentLibrary(rootURL: root)
            library = lib
            rootPath = lib.rootURL.path
            usingiCloud = LibraryLocation.isUsingiCloud
            usingCustomRoot = LibraryLocation.isUsingCustomRoot
            try lib.refreshFromDisk()
            refreshMailboxStatus()
            reload()
            if usingCustomRoot {
                statusMessage = "Library: \(rootPath)"
            } else {
                statusMessage = usingiCloud ? "Using iCloud Drive" : "Using local library (iCloud unavailable)"
            }
            Task {
                await self.scanDropFolder()
                if MailboxSettings.isConfigured {
                    await self.checkMailbox()
                }
                await self.indexPendingDocuments()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func chooseLibraryRoot() {
        #if os(macOS)
        // Called from the Library command menu; wait until menu tracking ends.
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.canChooseFiles = false
            panel.canChooseDirectories = true
            panel.allowsMultipleSelection = false
            panel.canCreateDirectories = true
            panel.prompt = "Use Folder"
            panel.message = "Choose where Secretary stores your documents. Existing files in this folder can be indexed."
            guard panel.runModal() == .OK, let url = panel.url else { return }
            do {
                try LibraryLocation.setCustomRoot(url)
                self.bootstrap()
                self.statusMessage = "Library folder updated"
            } catch {
                self.errorMessage = error.localizedDescription
            }
        }
        #endif
    }

    public func resetLibraryRootToDefault() {
        if let old = accessedRootURL {
            LibraryLocation.stopAccessing(old)
            accessedRootURL = nil
        }
        LibraryLocation.clearCustomRoot()
        bootstrap()
        statusMessage = "Using default library location"
    }

    public func removeFromLibrary(_ document: DocumentRecord) {
        guard let library else { return }
        do {
            try library.removeFromLibrary(documentID: document.id)
            reload()
            statusMessage = "Removed from app (file kept on disk)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func scanDropFolder() async {
        guard let library else { return }
        do {
            // ingestDropFolder uses NSFileCoordinator on a GCD queue. Do not
            // queue.sync that from MainActor — same iCloud deadlock as Import.
            let imported = try await Task.detached(priority: .userInitiated) {
                try library.ingestDropFolder()
            }.value
            guard !imported.isEmpty else { return }
            for record in imported {
                Task { await self.runOCRAndIndex(documentID: record.id) }
            }
            reload()
            statusMessage = "Moved \(imported.count) file(s) from Drop → Inbox"
        } catch {
            errorMessage = error.localizedDescription
            NSLog("Secretary: Drop folder ingest failed: \(error.localizedDescription)")
        }
    }

    public func revealDropFolder() {
        guard let library else { return }
        #if os(macOS)
        NSWorkspace.shared.open(library.dropURL)
        #endif
    }

    @Published public private(set) var lastMailIngestResult: MailIngestResult?
    
    public func refreshMailboxStatus() {
        mailboxConfigured = MailboxSettings.isConfigured
        mailboxEmail = MailboxSettings.inboxEmail
    }

    public func openMailboxSettings() {
        pendingSettingsTab = "mailbox"
    }

    public func checkMailbox() async {
        guard let library else { return }
        guard MailboxSettings.isConfigured else {
            statusMessage = "Configure AgentMail in Settings to receive documents by email"
            return
        }
        isBusy = true
        defer { isBusy = false }
        do {
            let result = try await MailIngestService().ingestNewAttachments(into: library)
            lastMailIngestResult = result
            if result.imported > 0 {
                let pending = try library.search(DocumentFilter(inboxOnly: true))
                for record in pending.prefix(result.imported) {
                    Task { await self.runOCRAndIndex(documentID: record.id) }
                }
                reload()
            }
            statusMessage = result.summary
            if result.hasErrors {
                errorMessage = result.errors.joined(separator: "\n")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func setupMailbox(apiKey: String, username: String) async {
        do {
            MailboxSettings.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
            let client = AgentMailClient(apiKey: MailboxSettings.apiKey!)
            // Reuse existing inbox if listed
            let existing = try await client.listInboxes()
            if let match = existing.first(where: { ($0.email ?? "").contains(username) }) ?? existing.first {
                MailboxSettings.inboxId = match.inboxId
                MailboxSettings.inboxEmail = match.email
                statusMessage = "Linked mailbox \(match.email ?? match.inboxId)"
                refreshMailboxStatus()
                return
            }
            let created = try await client.createInbox(username: username, clientId: "secretary-v1")
            MailboxSettings.inboxId = created.inboxId
            MailboxSettings.inboxEmail = created.email
            statusMessage = "Created mailbox \(created.email ?? created.inboxId)"
            refreshMailboxStatus()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Extract text for any documents that still have empty OCR content.
    public func indexPendingDocuments() async {
        guard let library else { return }
        let pending: [DocumentRecord]
        do {
            pending = try library.search(DocumentFilter()).filter { $0.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        } catch {
            return
        }
        guard !pending.isEmpty else { return }
        await MainActor.run {
            self.statusMessage = "Indexing \(pending.count) document(s)…"
        }
        for record in pending {
            await runOCRAndIndex(documentID: record.id)
        }
        await MainActor.run {
            self.statusMessage = "Search index ready"
        }
    }

    public func ensureIndexed(documentID: String) async {
        guard let library else { return }
        guard let record = try? library.document(id: documentID) else { return }
        if record.ocrText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            await runOCRAndIndex(documentID: documentID)
        }
    }

    public func reload() {
        guard let library else { return }
        do {
            documents = try library.search(filter)
            inboxCount = try library.search(DocumentFilter(inboxOnly: true)).count
            refreshCategoryLists()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func categories(for space: DocumentSpace) -> [String] {
        space == .personal ? personalCategories : bvCategories
    }

    public func ensureCategory(space: DocumentSpace, name: String) {
        let cleaned = ClassificationSuggester.sanitizeCategoryName(name)
        guard !cleaned.isEmpty, let library else { return }
        do {
            try library.addCategory(DocumentCategory(space: space, name: cleaned))
            refreshCategoryLists()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func refreshCategoryLists() {
        guard let library else { return }
        let all = (try? library.search(DocumentFilter())) ?? []
        var personal = Set(DefaultTaxonomy.personalCategories)
        var bv = Set(DefaultTaxonomy.bvCategories)
        for record in all where !record.isArchived {
            guard let category = record.category, !category.isEmpty else { continue }
            switch record.space {
            case .personal: personal.insert(category)
            case .bv: bv.insert(category)
            case .none: break
            }
        }
        // Also include empty folders created on disk via schema / addCategory
        for category in library.schema.categories {
            switch category.space {
            case .personal: personal.insert(category.name)
            case .bv: bv.insert(category.name)
            }
        }
        personalCategories = personal.sorted()
        bvCategories = bv.sorted()
    }

    public func applyFilter(_ newFilter: DocumentFilter) {
        filter = newFilter
        reload()
    }

    public func importURLs(_ urls: [URL]) {
        guard let library else { return }
        isBusy = true
        Task {
            var count = 0
            var lastError: String?
            for url in urls {
                // Pin security-scoped fileImporter / open-panel URLs before hopping off MainActor.
                // importFile uses NSFileCoordinator on a GCD queue; doing that via queue.sync
                // from the main thread deadlocks when iCloud presenters need the main run loop
                // (debugger stop lands in __pthread_kill / abort).
                let accessing = url.startAccessingSecurityScopedResource()
                defer {
                    if accessing { url.stopAccessingSecurityScopedResource() }
                }
                if !accessing {
                    NSLog("Secretary: startAccessingSecurityScopedResource returned false for \(url.lastPathComponent); importing if readable")
                }
                do {
                    let preferredName = url.deletingPathExtension().lastPathComponent
                    let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
                    let record = try await Task.detached(priority: .userInitiated) {
                        try copyThenImport(url, preferredName: preferredName, pathExtension: ext, into: library)
                    }.value
                    Task { await self.runOCRAndIndex(documentID: record.id) }
                    count += 1
                } catch {
                    lastError = error.localizedDescription
                    NSLog("Secretary: import failed for \(url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            self.reload()
            self.isBusy = false
            if count > 0 {
                self.statusMessage = "Imported \(count) file(s) to Inbox"
            }
            if let lastError {
                self.errorMessage = lastError
            }
        }
    }

    public func importFolder(_ folder: URL) {
        guard let library else { return }
        isBusy = true
        let accessing = folder.startAccessingSecurityScopedResource()
        if !accessing {
            NSLog("Secretary: startAccessingSecurityScopedResource returned false for folder \(folder.lastPathComponent)")
        }
        Task {
            defer {
                if accessing { folder.stopAccessingSecurityScopedResource() }
            }
            do {
                let importedIDs = try await Task.detached(priority: .userInitiated) {
                    let enumerator = FileManager.default.enumerator(
                        at: folder,
                        includingPropertiesForKeys: [.isRegularFileKey],
                        options: [.skipsHiddenFiles]
                    )
                    var ids: [String] = []
                    while let url = enumerator?.nextObject() as? URL {
                        var isDir: ObjCBool = false
                        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue }
                        let record = try library.importFile(from: url)
                        ids.append(record.id)
                    }
                    return ids
                }.value
                for id in importedIDs {
                    Task { await self.runOCRAndIndex(documentID: id) }
                }
                self.reload()
                self.statusMessage = "Imported \(importedIDs.count) file(s) from folder"
            } catch {
                self.errorMessage = error.localizedDescription
                NSLog("Secretary: folder import failed: \(error.localizedDescription)")
            }
            self.isBusy = false
        }
    }

    public func importData(_ data: Data, hint: String, pathExtension: String) {
        guard let library else { return }
        isBusy = true
        Task {
            do {
                let record = try await Task.detached(priority: .userInitiated) {
                    try library.importData(data, filenameHint: hint, pathExtension: pathExtension)
                }.value
                Task { await self.runOCRAndIndex(documentID: record.id) }
                self.reload()
                self.statusMessage = "Added scan to Inbox"
            } catch {
                self.errorMessage = error.localizedDescription
                NSLog("Secretary: importData failed: \(error.localizedDescription)")
            }
            self.isBusy = false
        }
    }

    public func classify(document: DocumentRecord, as target: ClassificationTarget) {
        guard let library else { return }
        do {
            let updated = try library.classify(documentID: document.id, as: target)
            SpotlightIndexer.index(updated, fileURL: library.fileURL(for: updated))
            if updated.expiryDate != nil {
                ExpiryReminderService.schedule(for: updated)
            }
            reload()
            statusMessage = "Classified as \(target.space.rawValue)/\(target.category)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func suggestions(for document: DocumentRecord) -> [ClassificationSuggestion] {
        (try? library?.suggestions(for: document)) ?? []
    }

    public func toggleFavorite(_ document: DocumentRecord) {
        guard let library else { return }
        do {
            let updated = try library.updateMetadata(documentID: document.id, isFavorite: !document.isFavorite)
            SpotlightIndexer.index(updated, fileURL: library.fileURL(for: updated))
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func saveMetadata(
        _ document: DocumentRecord,
        title: String,
        notes: String,
        tags: [String],
        expiry: Date?,
        paymentStatus: PaymentStatus? = nil,
        paidAt: Date? = nil
    ) {
        guard let library else { return }
        do {
            var status = paymentStatus
            var paid = paidAt
            if let status {
                if status == .paid, paid == nil { paid = Date() }
                if status != .paid { paid = nil }
            }
            let updated = try library.updateMetadata(
                documentID: document.id,
                title: title,
                notes: notes,
                tags: status?.syncedTags(tags) ?? tags,
                expiryDate: .some(expiry),
                paymentStatus: status,
                paidAt: status == nil ? nil : .some(paid)
            )
            SpotlightIndexer.index(updated, fileURL: library.fileURL(for: updated))
            ExpiryReminderService.schedule(for: updated)
            reload()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func duplicates(of document: DocumentRecord) -> [DocumentRecord] {
        (try? library?.duplicates(of: document)) ?? []
    }

    public func fileURL(for document: DocumentRecord) -> URL? {
        library?.fileURL(for: document)
    }

    public func ensureDownloaded(_ document: DocumentRecord) async {
        guard let library else { return }
        do {
            let ready = try library.ensureDownloaded(for: document)
            if !ready {
                statusMessage = "Downloading from iCloud…"
                // Poll briefly for local availability
                let url = library.fileURL(for: document)
                for _ in 0..<20 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                    let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey])
                    if values?.isUbiquitousItem != true || values?.ubiquitousItemDownloadingStatus == .current {
                        statusMessage = "Ready"
                        return
                    }
                }
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func rebuildIndex() {
        guard let library else { return }
        isBusy = true
        statusMessage = "Rebuilding index…"
        Task {
            do {
                let count = try await Task.detached(priority: .userInitiated) {
                    try library.rebuildIndex { url in
                        TextExtractionService.extractText(from: url)
                    }
                }.value
                let docs = try library.search(DocumentFilter())
                SpotlightIndexer.removeAll()
                for doc in docs {
                    SpotlightIndexer.index(doc, fileURL: library.fileURL(for: doc))
                }
                ExpiryReminderService.rescheduleAll(from: docs)
                self.reload()
                self.isBusy = false
                self.statusMessage = "Rebuilt index for \(count) documents"
            } catch {
                self.isBusy = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    public func addCategory(space: DocumentSpace, name: String) {
        guard let library else { return }
        do {
            try library.addCategory(DocumentCategory(space: space, name: name))
            refreshCategoryLists()
            statusMessage = "Added category \(space.rawValue)/\(name)"
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    public func requestNotificationPermission() {
        Task {
            _ = await ExpiryReminderService.requestAuthorization()
        }
    }

    private func runOCRAndIndex(documentID: String) async {
        guard let library else { return }
        do {
            guard let record = try library.document(id: documentID) else { return }
            _ = try library.ensureDownloaded(for: record)
            let url = library.fileURL(for: record)
            let text = await Task.detached(priority: .utility) {
                TextExtractionService.extractText(from: url)
            }.value
            var updated = try library.updateMetadata(documentID: documentID, ocrText: text)
            let fields = await DocumentUnderstanding.extractAsync(from: updated)
            if shouldApplyUnderstanding(fields, to: updated) {
                updated = try library.updateMetadata(
                    documentID: documentID,
                    title: fields.title,
                    tags: updated.tags.isEmpty ? fields.tags : nil
                )
            }
            SpotlightIndexer.index(updated, fileURL: url)
            self.reload()
        } catch {
            NSLog("Secretary: OCR/index failed for \(documentID): \(error.localizedDescription)")
            self.errorMessage = error.localizedDescription
        }
    }

    /// Apply on-device understanding after OCR when the stored title is still a filename stub.
    private func shouldApplyUnderstanding(_ fields: StructuredDocumentFields, to record: DocumentRecord) -> Bool {
        DocumentTitleGenerator.looksGeneric(
            record.title,
            filename: record.filename,
            originalFilename: record.originalFilename
        ) || fields.source == .foundationModels && record.title != fields.title
    }
}

/// Copy a picker/drop URL into a sandbox temp file, then into Inbox.
/// Must not run on the main actor: DocumentLibrary.importFile uses NSFileCoordinator
/// via DispatchQueue.sync, which deadlocks if the main run loop is blocked.
private func copyThenImport(
    _ url: URL,
    preferredName: String,
    pathExtension: String,
    into library: DocumentLibrary
) throws -> DocumentRecord {
    let temp = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
        .appendingPathExtension(pathExtension)
    do {
        try FileManager.default.copyItem(at: url, to: temp)
    } catch {
        NSLog("Secretary: temp copy failed (\(error.localizedDescription)); importing source URL")
        return try library.importFile(from: url, preferredName: preferredName)
    }
    defer { try? FileManager.default.removeItem(at: temp) }
    return try library.importFile(from: temp, preferredName: preferredName)
}

public enum SecretaryUTTypes {
    public static let importTypes: [UTType] = [.pdf, .image, .png, .jpeg, .heic, .plainText, .data]
}

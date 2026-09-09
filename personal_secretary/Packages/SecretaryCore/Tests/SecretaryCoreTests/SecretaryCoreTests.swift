import Foundation
import XCTest
@testable import SecretaryCore

final class SecretaryCoreTests: XCTestCase {
    func testFilenameSanitization() {
        let name = FolderSchema.makeFilename(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            documentType: "Insurance Policy",
            shortTitle: "KBC Home",
            pathExtension: "pdf"
        )
        XCTAssertTrue(name.hasSuffix(".pdf"))
        XCTAssertTrue(name.contains("__insurance-policy__"))
        XCTAssertTrue(name.contains("kbc-home"))
    }

    func testDefaultTaxonomy() {
        XCTAssertFalse(DefaultTaxonomy.all.isEmpty)
        XCTAssertTrue(DefaultTaxonomy.all.contains { $0.space == .bv && $0.name == "Governance" })
        XCTAssertTrue(DefaultTaxonomy.all.contains { $0.space == .personal && $0.name == "Tax" })
    }

    func testLibraryImportClassifyAndSearch() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryTest-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let source = root.appendingPathComponent("sample.txt")
        try "Hello secretary tax document".write(to: source, atomically: true, encoding: .utf8)

        let imported = try library.importFile(from: source, preferredName: "tax-note")
        XCTAssertTrue(imported.isInbox)

        let classified = try library.classify(
            documentID: imported.id,
            as: ClassificationTarget(
                space: .personal,
                category: "Tax",
                year: 2024,
                documentType: "note",
                shortTitle: "tax-note",
                notes: "aanslagbiljet"
            )
        )
        XCTAssertEqual(classified.space, .personal)
        XCTAssertEqual(classified.category, "Tax")
        XCTAssertEqual(classified.year, 2024)
        XCTAssertTrue(classified.relativePath.contains("Personal/Tax/2024/"))

        let results = try library.search(DocumentFilter(query: "aanslagbiljet"))
        XCTAssertEqual(results.count, 1)

        let byCategory = try library.search(DocumentFilter(space: .personal, category: "Tax"))
        XCTAssertEqual(byCategory.count, 1)
    }

    func testDuplicateHashDetection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryDup-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let payload = Data("identical-bytes".utf8)
        let a = root.appendingPathComponent("a.bin")
        let b = root.appendingPathComponent("b.bin")
        try payload.write(to: a)
        try payload.write(to: b)

        let first = try library.importFile(from: a)
        let second = try library.importFile(from: b)
        let dups = try library.duplicates(of: first)
        XCTAssertTrue(dups.contains { $0.id == second.id })
    }

    func testNewCategorySuggestionFromUtilitiesKeywords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryCat-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let source = root.appendingPathComponent("bill.txt")
        try "Fluvius elektriciteit factuur gas verbruik".write(to: source, atomically: true, encoding: .utf8)
        let imported = try library.importFile(from: source, preferredName: "fluvius-bill")
        let updated = try library.updateMetadata(documentID: imported.id, ocrText: "Fluvius elektriciteit factuur gas verbruik")
        let suggestions = try library.suggestions(for: updated)
        XCTAssertTrue(
            suggestions.contains { $0.category == "Utilities" && $0.isNewCategory },
            "Expected a new Utilities category suggestion, got \(suggestions.map(\.category))"
        )
        XCTAssertTrue(
            suggestions.contains { $0.category == "Utilities" && !$0.tags.isEmpty },
            "Expected tag suggestions on classify, got \(suggestions.map(\.tags))"
        )
    }

    func testRepeatedImportsAfterRefreshFromDisk() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryImport-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        try library.refreshFromDisk()

        for i in 0..<3 {
            let source = root.appendingPathComponent("file-\(i).txt")
            try "content \(i) tax document".write(to: source, atomically: true, encoding: .utf8)
            let imported = try library.importFile(from: source, preferredName: "file-\(i)")
            XCTAssertTrue(imported.isInbox)
            XCTAssertFalse(imported.id.isEmpty)
        }

        let inbox = try library.search(DocumentFilter(inboxOnly: true))
        XCTAssertEqual(inbox.count, 3)
    }

    func testImportDataWritesInboxRecord() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryScan-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let record = try library.importData(Data("scan-bytes".utf8), filenameHint: "letter-scan", pathExtension: "txt")
        XCTAssertTrue(record.isInbox)
        XCTAssertTrue(FileManager.default.fileExists(atPath: library.fileURL(for: record).path))
    }

    func testResolveRootFallsBackWithoutiCloudContainer() {
        LibraryLocation.clearCustomRoot()
        // Without a ubiquity container (Personal Team / missing entitlement), resolveRoot
        // must still return a usable Application Support path.
        let noCloud = NoUbiquityFileManager()
        let root = LibraryLocation.resolveRoot(fileManager: noCloud)
        let expected = noCloud.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(LibraryLocation.folderName, isDirectory: true)
        XCTAssertEqual(root.path, expected.path)
        XCTAssertFalse(root.path.contains("Mobile Documents"))
    }

    func testSuggestedTagsFromBelgianInvoiceCues() {
        let record = DocumentRecord(
            relativePath: "Inbox/factuur.pdf",
            filename: "2024-03-15__invoice__acme-nv.pdf",
            originalFilename: "Factuur ACME.pdf",
            ocrText: """
            ACME NV
            Factuur
            BTW BE 0123.456.789
            RSVZ bijdrage 2024
            """
        )
        let tags = ClassificationSuggester.suggestedTags(for: record, space: .bv, category: "Invoices", year: 2024)
        let lowered = tags.map { $0.lowercased() }
        XCTAssertTrue(lowered.contains("factuur"), "Expected Factuur tag, got \(tags)")
        XCTAssertTrue(lowered.contains("btw"), "Expected BTW tag, got \(tags)")
        XCTAssertTrue(lowered.contains("rsvz"), "Expected RSVZ tag, got \(tags)")
        XCTAssertTrue(tags.contains("2024"), "Expected year tag, got \(tags)")
        XCTAssertTrue(lowered.contains("invoices") || lowered.contains("invoice"), "Expected invoice category/type, got \(tags)")
    }

    func testSuggestedTagsPrefillOnOCRUpdateWhenEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryTags-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let source = root.appendingPathComponent("invoice.txt")
        try "placeholder".write(to: source, atomically: true, encoding: .utf8)
        let imported = try library.importFile(from: source, preferredName: "acme-factuur")
        XCTAssertTrue(imported.tags.isEmpty)

        let updated = try library.updateMetadata(
            documentID: imported.id,
            ocrText: "ACME NV\nFactuur\nBTW BE 0123.456.789"
        )
        XCTAssertFalse(updated.tags.isEmpty, "OCR update should prefill tags when empty")
        let lowered = updated.tags.map { $0.lowercased() }
        XCTAssertTrue(lowered.contains("factuur") || lowered.contains("btw"), "Expected Belgian cues, got \(updated.tags)")
    }

    func testUpdateMetadataDoesNotOverwriteExistingTags() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryTagsKeep-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let source = root.appendingPathComponent("keep.txt")
        try "keep".write(to: source, atomically: true, encoding: .utf8)
        let imported = try library.importFile(from: source, preferredName: "keep")
        _ = try library.updateMetadata(documentID: imported.id, tags: ["keep-me"])

        let updated = try library.updateMetadata(
            documentID: imported.id,
            ocrText: "Factuur BTW RSVZ 2024"
        )
        XCTAssertEqual(updated.tags, ["keep-me"])
    }

    func testClassifyFillsEmptyTags() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryTagsClassify-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let source = root.appendingPathComponent("tax.txt")
        try "aanslagbiljet personenbelasting 2023".write(to: source, atomically: true, encoding: .utf8)
        let imported = try library.importFile(from: source, preferredName: "aanslag")
        // Seed OCR without going through updateMetadata's empty-tag prefill.
        _ = try library.updateMetadata(documentID: imported.id, tags: ["__clear_placeholder__"], ocrText: "aanslagbiljet personenbelasting 2023")
        // Explicit non-empty then classify with empty target tags should keep existing tags.
        let kept = try library.classify(
            documentID: imported.id,
            as: ClassificationTarget(
                space: .personal,
                category: "Tax",
                year: 2023,
                documentType: "tax",
                shortTitle: "aanslag-keep",
                tags: []
            )
        )
        XCTAssertEqual(kept.tags, ["__clear_placeholder__"])

        let inbox2 = root.appendingPathComponent("tax2.txt")
        try "aanslagbiljet personenbelasting 2023".write(to: inbox2, atomically: true, encoding: .utf8)
        let imported2 = try library.importFile(from: inbox2, preferredName: "aanslag-empty")
        // Write OCR onto a still-empty tag list (placeholder then user-clear is not possible;
        // use updateMetadata(ocrText:) with tags omitted after a fresh import).
        let withOCR = try library.updateMetadata(documentID: imported2.id, ocrText: "aanslagbiljet personenbelasting 2023")
        XCTAssertFalse(withOCR.tags.isEmpty, "OCR path should already prefill")

        let inbox3 = root.appendingPathComponent("tax3.txt")
        try "hello".write(to: inbox3, atomically: true, encoding: .utf8)
        let imported3 = try library.importFile(from: inbox3, preferredName: "plain")
        XCTAssertTrue(imported3.tags.isEmpty)
        let classified = try library.classify(
            documentID: imported3.id,
            as: ClassificationTarget(
                space: .personal,
                category: "Tax",
                year: 2023,
                documentType: "tax",
                shortTitle: "plain-tax",
                notes: "aanslagbiljet personenbelasting",
                tags: []
            )
        )
        XCTAssertFalse(classified.tags.isEmpty, "Classify should prefill tags when both target and record are empty")
        let lowered = classified.tags.map { $0.lowercased() }
        XCTAssertTrue(
            classified.tags.contains("2023") || lowered.contains("tax") || lowered.contains("belasting"),
            "Expected useful tags, got \(classified.tags)"
        )
    }

    func testSanitizerRejectsCyrillicAndJunk() {
        XCTAssertFalse(SuggestionSanitizer.isAcceptableLabel("Підетидегіке"))
        XCTAssertFalse(SuggestionSanitizer.isAcceptableCategory("Підетидегіке"))
        XCTAssertFalse(SuggestionSanitizer.isAcceptableLabel("PfO6D4aa"))
        XCTAssertFalse(SuggestionSanitizer.isAcceptablePhrase("ALL CUL"))
        XCTAssertFalse(SuggestionSanitizer.isAcceptableDocumentType("import"))
        XCTAssertTrue(SuggestionSanitizer.isAcceptablePhrase("Aanvraag tot identificatie"))
        XCTAssertTrue(SuggestionSanitizer.isAcceptableCategory("Tax"))
        XCTAssertTrue(SuggestionSanitizer.isAcceptableLabel("Factuur"))
        XCTAssertEqual(ClassificationSuggester.sanitizeCategoryName("Підетидегіке"), "Misc")
    }

    func testSuggestionsRejectCyrillicAndReferenceCodes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretarySanitize-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let source = root.appendingPathComponent("junk.txt")
        try "Підетидегіке\nPfO6D4aa\nALL CUL\nBTW factuur 2025".write(to: source, atomically: true, encoding: .utf8)
        let imported = try library.importFile(from: source, preferredName: "aanvraag-tot-identificatie-voor-btw")
        let updated = try library.updateMetadata(
            documentID: imported.id,
            ocrText: "Підетидегіке\nPfO6D4aa\nALL CUL\nBTW factuur 2025"
        )
        let suggestions = try library.suggestions(for: updated)
        XCTAssertFalse(
            suggestions.contains { SuggestionSanitizer.isMostlyLatin($0.category) == false },
            "Cyrillic leaked into categories: \(suggestions.map(\.category))"
        )
        XCTAssertFalse(
            suggestions.contains { $0.shortTitle.contains("PfO") || $0.shortTitle.contains("ALL CUL") || $0.documentType.contains("PfO") },
            "Junk title/type leaked: \(suggestions.map { "\($0.shortTitle)/\($0.documentType)" })"
        )
        XCTAssertTrue(
            suggestions.contains { $0.category == "Invoices" || $0.category == "Tax" },
            "Expected a taxonomy suggestion, got \(suggestions.map(\.destinationLabel))"
        )
    }

    func testClassifyFilenameUsesCleanedTitleNotImportStub() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryName-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let source = root.appendingPathComponent("aanvraag-tot-identificatie-voor-btw.txt")
        try "BTW factuur".write(to: source, atomically: true, encoding: .utf8)
        let imported = try library.importFile(from: source, preferredName: "aanvraag-tot-identificatie-voor-btw")
        XCTAssertTrue(imported.filename.contains("__import__"))

        let classified = try library.classify(
            documentID: imported.id,
            as: ClassificationTarget(
                space: .bv,
                category: "Tax",
                year: 2025,
                documentType: "import",
                shortTitle: "PfO6D4aa",
                notes: "BTW factuur FOD Financiën"
            )
        )
        XCTAssertFalse(classified.filename.contains("__import__"), "Inbox type leaked into filed name: \(classified.filename)")
        XCTAssertFalse(classified.filename.lowercased().contains("pfo6"), "Reference code used as filename: \(classified.filename)")
        XCTAssertEqual(classified.title.lowercased().contains("pfo6"), false)
        XCTAssertTrue(
            classified.filename.contains("aanvraag-tot-identificatie")
                || classified.title.localizedCaseInsensitiveContains("Aanvraag"),
            "Expected filename/title from the original name, got title=\(classified.title) file=\(classified.filename)"
        )
        XCTAssertTrue(classified.filename.contains("__document__") || classified.filename.contains("__tax__"))
        XCTAssertFalse(classified.tags.isEmpty, "Classify should still autofill tags, got \(classified.tags)")
    }

    func testParsePath() {
        let inbox = FolderSchema.parsePath("Inbox/foo.pdf")
        XCTAssertTrue(inbox.isInbox)

        let tax = FolderSchema.parsePath("Personal/Tax/2023/file.pdf")
        XCTAssertEqual(tax.space, .personal)
        XCTAssertEqual(tax.category, "Tax")
        XCTAssertEqual(tax.year, 2023)
    }

    func testDetailSplitUsesMinimaAndPersistedWidth() {
        XCTAssertEqual(DetailSplitLayout.metaMinWidth, 280)
        XCTAssertEqual(DetailSplitLayout.previewMinWidth, 360)
        XCTAssertEqual(DetailSplitLayout.minimumSplitWidth, 648)
        XCTAssertTrue(DetailSplitLayout.canSplit(detailWidth: 900))
        XCTAssertFalse(DetailSplitLayout.canSplit(detailWidth: 640))

        XCTAssertEqual(DetailSplitLayout.clampedMetaWidth(200, detailWidth: 900), 280)
        XCTAssertEqual(DetailSplitLayout.clampedMetaWidth(800, detailWidth: 900), 532)
        XCTAssertEqual(DetailSplitLayout.clampedMetaWidth(340, detailWidth: 900), 340)
        XCTAssertEqual(DetailSplitLayout.clampedMetaWidth(400, detailWidth: 500), 500)
    }

    func testCategoryListGroupsByYearThenType() {
        let invoice2025 = DocumentRecord(
            relativePath: "BV/Invoices/2025/2025-03-01__invoice__kbc.pdf",
            filename: "2025-03-01__invoice__kbc.pdf",
            space: .bv,
            category: "Invoices",
            year: 2025,
            title: "KBC",
            modifiedAt: Date(timeIntervalSince1970: 100)
        )
        let policy2025 = DocumentRecord(
            relativePath: "BV/Invoices/2025/2025-01-01__policy__home.pdf",
            filename: "2025-01-01__policy__home.pdf",
            space: .bv,
            category: "Invoices",
            year: 2025,
            title: "Home",
            modifiedAt: Date(timeIntervalSince1970: 50)
        )
        let invoice2024 = DocumentRecord(
            relativePath: "BV/Invoices/2024/2024-06-01__invoice__engie.pdf",
            filename: "2024-06-01__invoice__engie.pdf",
            space: .bv,
            category: "Invoices",
            year: 2024,
            title: "Engie",
            modifiedAt: Date(timeIntervalSince1970: 10)
        )
        let sections = DocumentListGrouping.sections(from: [invoice2024, policy2025, invoice2025])
        XCTAssertEqual(sections.map(\.title), ["2025 · Invoice", "2025 · Policy", "2024 · Invoice"])
        XCTAssertEqual(sections[0].documents.map(\.title), ["KBC"])
        XCTAssertTrue(DocumentListGrouping.shouldGroup(filter: DocumentFilter(space: .bv, category: "Invoices")))
        XCTAssertFalse(DocumentListGrouping.shouldGroup(filter: DocumentFilter(inboxOnly: true)))
        XCTAssertFalse(DocumentListGrouping.shouldGroup(filter: DocumentFilter(query: "kbc")))
    }

    func testCategoryFilterFindsYearSubfolderFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryYear-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let folder = root.appendingPathComponent("Personal/Tax/2023")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = folder.appendingPathComponent("2023-05-01__tax__aanslag.txt")
        try "aanslagbiljet 2023".write(to: file, atomically: true, encoding: .utf8)
        try library.refreshFromDisk()

        let results = try library.search(DocumentFilter(space: .personal, category: "Tax"))
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.year, 2023)
        XCTAssertEqual(results.first?.category, "Tax")
        XCTAssertTrue(results.first?.relativePath.contains("Personal/Tax/2023/") == true)

        let sections = DocumentListGrouping.sections(from: results)
        XCTAssertEqual(sections.map(\.title), ["2023 · Tax"])
    }

    func testUnderstandingExtractsInvoiceFieldsAndRejectsJunkTitle() {
        let document = DocumentRecord(
            relativePath: "Inbox/2024-01-01__import__pfo6d4aa.txt",
            filename: "2024-01-01__import__pfo6d4aa.txt",
            originalFilename: "PfO6D4aa.pdf",
            title: "PfO6D4aa",
            ocrText: """
            KBC Bank
            Factuur
            Factuurdatum: 15/03/2024
            Vervaldatum: 14/04/2024
            Totaal te betalen: 1.234,56
            """
        )
        let fields = DocumentUnderstanding.extract(
            from: document,
            preferredTitle: "PfO6D4aa",
            preferredType: "import"
        )
        XCTAssertEqual(fields.source, .heuristic)
        XCTAssertEqual(fields.documentType, "invoice")
        XCTAssertTrue(fields.looksLikeInvoice)
        XCTAssertFalse(fields.title.lowercased().contains("pfo6"))
        XCTAssertEqual(fields.amount, Decimal(string: "1234.56"))
        XCTAssertNotNil(fields.documentDate)
        XCTAssertNotNil(fields.dueDate)
        XCTAssertEqual(FolderSchema.sanitize(fields.title), FolderSchema.sanitize(fields.title))
    }

    func testClassifyFilenameMatchesCleanedTitleSlug() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryFile-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let source = root.appendingPathComponent("junk.txt")
        try """
        KBC Bank
        Factuur
        Factuurdatum: 15/03/2024
        Totaal: 89,00
        """.write(to: source, atomically: true, encoding: .utf8)
        let imported = try library.importFile(from: source, preferredName: "PfO6D4aa")
        let withOCR = try library.updateMetadata(
            documentID: imported.id,
            ocrText: "KBC Bank\nFactuur\nFactuurdatum: 15/03/2024\nTotaal: 89,00"
        )
        let classified = try library.classify(
            documentID: withOCR.id,
            as: ClassificationTarget(
                space: .bv,
                category: "Invoices",
                year: 2024,
                documentType: "import",
                shortTitle: "PfO6D4aa"
            )
        )
        XCTAssertEqual(classified.title, DocumentUnderstanding.extract(from: withOCR, preferredTitle: "PfO6D4aa", preferredType: "import").title)
        let stem = (classified.filename as NSString).deletingPathExtension
        let parts = stem.split(separator: "__").map(String.init)
        XCTAssertEqual(parts.count, 3, "Expected YYYY-MM-DD__type__slug, got \(classified.filename)")
        XCTAssertEqual(parts[1], "invoice")
        XCTAssertEqual(parts[2], FolderSchema.sanitize(classified.title))
        XCTAssertTrue(classified.filename.hasPrefix("2024-03-15__") || classified.filename.hasPrefix("2024-"))
        XCTAssertEqual(classified.paymentStatus, .unpaid)
        XCTAssertTrue(classified.tags.contains { $0.lowercased() == "unpaid" })

        let paid = try library.updateMetadata(
            documentID: classified.id,
            paymentStatus: .paid,
            paidAt: .some(Date(timeIntervalSince1970: 1_700_000_000))
        )
        XCTAssertEqual(paid.paymentStatus, .paid)
        XCTAssertNotNil(paid.paidAt)
        XCTAssertTrue(paid.tags.contains { $0.lowercased() == "paid" })
        XCTAssertFalse(paid.tags.contains { $0.lowercased() == "unpaid" })
    }
}

/// FileManager that never reports an iCloud ubiquity container (Personal Team / no entitlement).
private final class NoUbiquityFileManager: FileManager {
    override func url(forUbiquityContainerIdentifier identifier: String?) -> URL? {
        nil
    }
}

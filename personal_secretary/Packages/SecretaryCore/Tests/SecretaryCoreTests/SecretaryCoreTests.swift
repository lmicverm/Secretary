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

    func testDocumentPreviewPolicyAvoidsLivePDFViewOnIOSAppOnMac() {
        XCTAssertEqual(
            DocumentPreviewPolicy.kind(pathExtension: "pdf", isReadable: true, isIOSAppOnMac: false),
            .livePDFView
        )
        XCTAssertEqual(
            DocumentPreviewPolicy.kind(pathExtension: "PDF", isReadable: true, isIOSAppOnMac: true),
            .softwarePDFPage
        )
        XCTAssertEqual(
            DocumentPreviewPolicy.kind(pathExtension: "png", isReadable: true, isIOSAppOnMac: true),
            .rasterImage
        )
        XCTAssertEqual(
            DocumentPreviewPolicy.kind(pathExtension: "pdf", isReadable: false, isIOSAppOnMac: false),
            .missingFile
        )
        XCTAssertEqual(
            DocumentPreviewPolicy.kind(pathExtension: "docx", isReadable: true, isIOSAppOnMac: false),
            .unsupported
        )
    }

    func testDocumentPreviewPolicyReadableFile() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("SecretaryPreview-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let missing = dir.appendingPathComponent("gone.pdf")
        XCTAssertFalse(DocumentPreviewPolicy.isReadableFile(at: missing))

        let file = dir.appendingPathComponent("page.pdf")
        try Data("%PDF-1.4\n").write(to: file)
        XCTAssertTrue(DocumentPreviewPolicy.isReadableFile(at: file))
        XCTAssertFalse(DocumentPreviewPolicy.isReadableFile(at: dir))
    }

    func testParsePath() {
        let inbox = FolderSchema.parsePath("Inbox/foo.pdf")
        XCTAssertTrue(inbox.isInbox)

        let tax = FolderSchema.parsePath("Personal/Tax/2023/file.pdf")
        XCTAssertEqual(tax.space, .personal)
        XCTAssertEqual(tax.category, "Tax")
        XCTAssertEqual(tax.year, 2023)
    }
}

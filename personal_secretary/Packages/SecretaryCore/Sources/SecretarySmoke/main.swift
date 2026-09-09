import Foundation
import SecretaryCore

@main
struct SecretarySmoke {
    static func main() throws {
        var failures = 0

        func check(_ name: String, _ ok: Bool) {
            if ok {
                print("PASS \(name)")
            } else {
                print("FAIL \(name)")
                failures += 1
            }
        }

        let name = FolderSchema.makeFilename(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            documentType: "Insurance Policy",
            shortTitle: "KBC Home",
            pathExtension: "pdf"
        )
        check("filename contains type", name.contains("__insurance-policy__"))
        check("filename contains title", name.contains("kbc-home"))
        check("taxonomy not empty", !DefaultTaxonomy.all.isEmpty)

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("SecretarySmoke-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let library = try DocumentLibrary(rootURL: root)
        let source = root.appendingPathComponent("sample.txt")
        try "Hello secretary tax document".write(to: source, atomically: true, encoding: .utf8)

        let imported = try library.importFile(from: source, preferredName: "tax-note")
        check("import lands in inbox", imported.isInbox)

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
        check("classified space", classified.space == .personal)
        check("classified category", classified.category == "Tax")
        check("path has year", classified.relativePath.contains("Personal/Tax/2024/"))

        let results = try library.search(DocumentFilter(query: "aanslagbiljet"))
        check("search notes", results.count == 1)

        let payload = Data("identical-bytes".utf8)
        let a = root.appendingPathComponent("a.bin")
        let b = root.appendingPathComponent("b.bin")
        try payload.write(to: a)
        try payload.write(to: b)
        let first = try library.importFile(from: a)
        let second = try library.importFile(from: b)
        let dups = try library.duplicates(of: first)
        check("duplicate hash", dups.contains { $0.id == second.id })

        let inbox = FolderSchema.parsePath("Inbox/foo.pdf")
        check("parse inbox", inbox.isInbox)

        // Suggestion + learning
        let taxSource = root.appendingPathComponent("tax2.txt")
        try "aanslagbiljet personenbelasting 2023".write(to: taxSource, atomically: true, encoding: .utf8)
        let taxInbox = try library.importFile(from: taxSource, preferredName: "aanslag")
        let suggestions = try library.suggestions(for: taxInbox)
        check("tax suggestion exists", suggestions.contains { $0.space == .personal && $0.category == "Tax" })
        check("tax suggestion has tags", suggestions.contains { $0.category == "Tax" && !$0.tags.isEmpty })

        let ocrInbox = try library.importFile(from: taxSource, preferredName: "aanslag-ocr")
        let ocrUpdated = try library.updateMetadata(
            documentID: ocrInbox.id,
            ocrText: "aanslagbiljet personenbelasting 2023"
        )
        check("ocr prefills empty tags", !ocrUpdated.tags.isEmpty)

        check("reject cyrillic category", !SuggestionSanitizer.isAcceptableCategory("Підетидегіке"))
        check("reject reference code", !SuggestionSanitizer.isAcceptableLabel("PfO6D4aa"))
        check("reject ALL CUL", !SuggestionSanitizer.isAcceptablePhrase("ALL CUL"))
        check("accept dutch title", SuggestionSanitizer.isAcceptablePhrase("Aanvraag tot identificatie"))

        let named = try library.classify(
            documentID: ocrUpdated.id,
            as: ClassificationTarget(
                space: .personal,
                category: "Tax",
                year: 2023,
                documentType: "import",
                shortTitle: "PfO6D4aa"
            )
        )
        check("filed name drops import", !named.filename.contains("__import__"))
        check("filed name not reference code", !named.filename.lowercased().contains("pfo6"))

        if failures > 0 {
            fputs("\(failures) failure(s)\n", stderr)
            exit(1)
        }
        print("All smoke checks passed.")
    }
}

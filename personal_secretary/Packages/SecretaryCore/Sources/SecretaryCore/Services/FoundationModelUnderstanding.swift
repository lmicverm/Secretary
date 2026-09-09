#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// On-device Apple Intelligence extraction. Compiled only when the SDK ships `FoundationModels`.
/// Personal Team / Xcode 15 never see this type (`canImport` is false).
enum FoundationModelUnderstanding {
    static func extract(
        from document: DocumentRecord,
        fallback: StructuredDocumentFields
    ) async -> StructuredDocumentFields? {
        let snippet = [
            document.originalFilename,
            document.filename,
            document.title,
            document.ocrText
        ]
        .joined(separator: "\n")
        .prefix(3_500)

        let prompt = """
        Extract metadata from this personal/business document. Reply with JSON only, no markdown:
        {"title":"short human title","documentType":"invoice|tax|policy|statement|contract|document","tags":["tag"],"amount":null,"documentDate":"YYYY-MM-DD or null","dueDate":"YYYY-MM-DD or null","correspondent":"issuer or null"}
        Rules: title must be readable (never OCR junk, reference codes, or import/scan). Prefer Dutch or English words already in the text. No cloud services.
        Text:
        \(snippet)
        """

        let raw: String
        do {
            raw = try await respondOnDevice(prompt: prompt)
        } catch {
            return nil
        }

        guard let parsed = parseJSON(raw) else { return nil }
        return merge(parsed, fallback: fallback, document: document)
    }

    /// `LanguageModelSession.respond(to:)` is the on-device Foundation Models entry point.
    private static func respondOnDevice(prompt: String) async throws -> String {
        let session = LanguageModelSession()
        let response = try await session.respond(to: prompt)
        return response.content
    }

    private struct Payload: Decodable {
        var title: String?
        var documentType: String?
        var tags: [String]?
        var amount: LooseDecimal?
        var documentDate: String?
        var dueDate: String?
        var correspondent: String?
    }

    private struct LooseDecimal: Decodable {
        var value: Decimal?
        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                value = nil
            } else if let number = try? container.decode(Double.self) {
                value = Decimal(number)
            } else if let string = try? container.decode(String.self) {
                value = DocumentUnderstanding.decimal(from: string)
            } else {
                value = nil
            }
        }
    }

    private static func parseJSON(_ raw: String) -> Payload? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let json: String
        if let start = trimmed.firstIndex(of: "{"), let end = trimmed.lastIndex(of: "}") {
            json = String(trimmed[start...end])
        } else {
            json = trimmed
        }
        return try? JSONDecoder().decode(Payload.self, from: Data(json.utf8))
    }

    private static func merge(
        _ payload: Payload,
        fallback: StructuredDocumentFields,
        document: DocumentRecord
    ) -> StructuredDocumentFields {
        let title: String
        if let raw = payload.title?.trimmingCharacters(in: .whitespacesAndNewlines),
           SuggestionSanitizer.isAcceptablePhrase(raw) {
            title = ClassificationSuggester.cleanedDisplayTitle(raw, document: document)
        } else {
            title = fallback.title
        }
        let type = ClassificationSuggester.cleanedDocumentType(
            payload.documentType ?? fallback.documentType,
            fallback: fallback.documentType
        )
        let tags = (payload.tags ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && SuggestionSanitizer.isAcceptableLabel($0) }
        let correspondent = payload.correspondent.flatMap { name -> String? in
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            return SuggestionSanitizer.isAcceptablePhrase(trimmed) ? trimmed : nil
        }
        return StructuredDocumentFields(
            title: title,
            documentType: type,
            tags: tags.isEmpty ? fallback.tags : Array(tags.prefix(8)),
            amount: payload.amount?.value ?? fallback.amount,
            documentDate: payload.documentDate.flatMap(DocumentUnderstanding.parseFlexibleDate) ?? fallback.documentDate,
            dueDate: payload.dueDate.flatMap(DocumentUnderstanding.parseFlexibleDate) ?? fallback.dueDate,
            correspondent: correspondent ?? fallback.correspondent,
            looksLikeInvoice: fallback.looksLikeInvoice || DocumentUnderstanding.looksLikeInvoice(
                text: title,
                documentType: type,
                tags: tags,
                category: document.category
            ),
            source: .foundationModels
        )
    }
}
#endif

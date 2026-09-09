import Foundation
#if canImport(NaturalLanguage)
import NaturalLanguage
#endif
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Structured fields inferred from filename + OCR (and optionally Apple Foundation Models).
public struct StructuredDocumentFields: Equatable, Sendable {
    public var title: String
    public var documentType: String
    public var tags: [String]
    public var amount: Decimal?
    public var documentDate: Date?
    public var dueDate: Date?
    public var correspondent: String?
    public var looksLikeInvoice: Bool
    public var source: Source

    public enum Source: String, Sendable {
        /// Pattern + NaturalLanguage extraction. This is what Personal Team / macOS 14 builds use.
        case heuristic
        /// Apple Foundation Models (Apple Intelligence). Only when the OS/SDK actually ships it.
        case foundationModels
    }

    public init(
        title: String,
        documentType: String,
        tags: [String] = [],
        amount: Decimal? = nil,
        documentDate: Date? = nil,
        dueDate: Date? = nil,
        correspondent: String? = nil,
        looksLikeInvoice: Bool = false,
        source: Source = .heuristic
    ) {
        self.title = title
        self.documentType = documentType
        self.tags = tags
        self.amount = amount
        self.documentDate = documentDate
        self.dueDate = dueDate
        self.correspondent = correspondent
        self.looksLikeInvoice = looksLikeInvoice
        self.source = source
    }

    public var summaryLine: String? {
        var parts: [String] = []
        if let correspondent, !correspondent.isEmpty { parts.append(correspondent) }
        if let amount { parts.append(DocumentUnderstanding.formatAmount(amount)) }
        if let documentDate { parts.append(DocumentUnderstanding.displayDate(documentDate)) }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// On-device document understanding. Heuristic path is the supported default.
///
/// Foundation Models (Apple Intelligence) require a newer OS than this app’s
/// deployment target (macOS 14 / iOS 17). When `canImport(FoundationModels)`
/// and the OS is new enough, `extractAsync` may try that API; otherwise we
/// always fall back to the heuristic extractor below.
public enum DocumentUnderstanding {
    /// `true` only when the Foundation Models module is present in the SDK.
    /// The current deployment target is macOS 14 / iOS 17, so this is false in shipping builds.
    public static var foundationModelsAvailable: Bool {
        #if canImport(FoundationModels)
        true
        #else
        false
        #endif
    }

    public static func looksLikeInvoice(
        text: String,
        documentType: String? = nil,
        tags: [String] = [],
        category: String? = nil
    ) -> Bool {
        let type = (documentType ?? "").lowercased()
        if type.contains("invoice") || type.contains("factuur") || type == "bill" { return true }
        if tags.contains(where: { ["factuur", "invoice", "unpaid", "paid"].contains($0.lowercased()) }) {
            return true
        }
        if category?.localizedCaseInsensitiveContains("invoice") == true { return true }
        let hay = text.lowercased()
        return hay.contains("factuur") || hay.contains("invoice") || hay.contains("creditnota")
    }

    /// Sync extractor used by classify / filename. Never requires a network or Apple Intelligence.
    public static func extract(
        from document: DocumentRecord,
        preferredTitle: String? = nil,
        preferredType: String? = nil,
        preferredTags: [String]? = nil
    ) -> StructuredDocumentFields {
        let blob = [
            document.originalFilename,
            document.filename,
            document.title,
            document.notes,
            document.ocrText
        ].joined(separator: "\n")

        let inferredType = FolderSchema.documentType(fromFilename: document.filename)
        let type = ClassificationSuggester.cleanedDocumentType(
            preferredType ?? inferredType ?? inferType(from: blob),
            fallback: inferType(from: blob)
        )

        let correspondent = extractCorrespondent(from: document.ocrText)
            ?? DocumentTitleGenerator.correspondentHint(from: document.ocrText)

        let preferred = preferredTitle?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let cleanedPreferred = preferred.isEmpty
            ? nil
            : ClassificationSuggester.cleanedDisplayTitle(preferred, document: document)

        let generated = ClassificationSuggester.suggestedTitle(for: document)
        var title = cleanedPreferred ?? generated
        if title == "Document" || DocumentTitleGenerator.looksGeneric(title, filename: document.filename, originalFilename: document.originalFilename) {
            if let correspondent, let composed = composedTitle(type: type, correspondent: correspondent) {
                title = composed
            }
        }
        title = ClassificationSuggester.cleanedDisplayTitle(title, document: document)

        let invoice = looksLikeInvoice(
            text: blob,
            documentType: type,
            tags: preferredTags ?? document.tags,
            category: document.category
        )

        var tags = preferredTags ?? ClassificationSuggester.suggestedTags(
            for: document,
            documentType: type
        )
        if let correspondent, SuggestionSanitizer.isAcceptableLabel(correspondent), tags.count < 8 {
            if !tags.contains(where: { $0.compare(correspondent, options: .caseInsensitive) == .orderedSame }) {
                tags.insert(correspondent, at: 0)
            }
        }

        return StructuredDocumentFields(
            title: title,
            documentType: invoice && type == "document" ? "invoice" : type,
            tags: tags,
            amount: parseAmount(from: blob),
            documentDate: parseDocumentDate(from: blob) ?? FolderSchema.documentDate(fromFilename: document.filename),
            dueDate: parseDueDate(from: blob),
            correspondent: correspondent,
            looksLikeInvoice: invoice,
            source: .heuristic
        )
    }

    /// Tries Foundation Models when the OS/SDK has them; always falls back to ``extract(from:)``.
    public static func extractAsync(
        from document: DocumentRecord,
        preferredTitle: String? = nil,
        preferredType: String? = nil,
        preferredTags: [String]? = nil
    ) async -> StructuredDocumentFields {
        let fallback = extract(
            from: document,
            preferredTitle: preferredTitle,
            preferredType: preferredType,
            preferredTags: preferredTags
        )
        #if canImport(FoundationModels)
        if let enriched = await extractWithFoundationModels(from: document, fallback: fallback) {
            return enriched
        }
        #endif
        return fallback
    }

    public static func formatAmount(_ amount: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "EUR"
        formatter.locale = Locale(identifier: "nl_BE")
        return formatter.string(from: amount as NSDecimalNumber) ?? "€\(amount)"
    }

    public static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "nl_BE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    // MARK: - Heuristics

    static func inferType(from text: String) -> String {
        let lower = text.lowercased()
        let pairs: [(String, [String])] = [
            ("invoice", ["factuur", "invoice", "creditnota"]),
            ("tax", ["aanslagbiljet", "personenbelasting", "btw-aangifte"]),
            ("policy", ["verzekeringspolis", "polis", "insurance policy"]),
            ("statement", ["bankafschrift", "account statement", "rekeninguittreksel"]),
            ("payroll", ["loonfiche", "loonbrief", "payslip"]),
            ("contract", ["overeenkomst", "huurcontract", "agreement"]),
            ("id", ["identiteitskaart", "rijbewijs", "paspoort"]),
        ]
        for (type, needles) in pairs where needles.contains(where: { lower.contains($0) }) {
            return type
        }
        return "document"
    }

    static func composedTitle(type: String, correspondent: String) -> String? {
        let pretty = type.replacingOccurrences(of: "-", with: " ").capitalized
        let label = correspondent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard SuggestionSanitizer.isAcceptablePhrase(label) else { return nil }
        if type == "document" { return String(label.prefix(72)) }
        return String("\(pretty) — \(label)".prefix(72))
    }

    static func extractCorrespondent(from ocrText: String) -> String? {
        #if canImport(NaturalLanguage)
        let snippet = String(ocrText.prefix(2_000))
        guard !snippet.isEmpty else { return DocumentTitleGenerator.correspondentHint(from: ocrText) }
        let tagger = NLTagger(tagSchemes: [.nameType])
        tagger.string = snippet
        var best: String?
        tagger.enumerateTags(
            in: snippet.startIndex..<snippet.endIndex,
            unit: .word,
            scheme: .nameType,
            options: [.omitPunctuation, .omitWhitespace, .joinNames]
        ) { tag, range in
            guard tag == .organizationName || tag == .personalName else { return true }
            let name = String(snippet[range]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard SuggestionSanitizer.isAcceptablePhrase(name), name.count >= 3, name.count <= 48 else {
                return true
            }
            best = name
            return false
        }
        if let best { return best }
        #endif
        return DocumentTitleGenerator.correspondentHint(from: ocrText)
    }

    static func parseAmount(from text: String) -> Decimal? {
        let pattern = #"(?i)(?:totaal\s*(?:te\s*betalen)?|te\s*betalen|bedrag|amount|total|eur|€)\s*[:=]?\s*€?\s*([0-9]{1,3}(?:\.[0-9]{3})*,[0-9]{2}|[0-9]+[.,][0-9]{2})"#
        guard let raw = firstCapture(pattern, in: text) else { return nil }
        return decimal(from: raw)
    }

    static func parseDueDate(from text: String) -> Date? {
        let pattern = #"(?i)(?:vervaldatum|vervalt(?:\s*op)?|due(?:\s*date)?|te\s*betalen\s*voor|uiterste\s*datum)\s*[:=]?\s*([0-9]{1,2}[-/.][0-9]{1,2}[-/.][0-9]{2,4}|[0-9]{4}[-/.][0-9]{1,2}[-/.][0-9]{1,2})"#
        guard let raw = firstCapture(pattern, in: text) else { return nil }
        return parseFlexibleDate(raw)
    }

    static func parseDocumentDate(from text: String) -> Date? {
        let pattern = #"(?i)(?:factuurdatum|invoice\s*date|documentdatum|datum)\s*[:=]?\s*([0-9]{1,2}[-/.][0-9]{1,2}[-/.][0-9]{2,4}|[0-9]{4}[-/.][0-9]{1,2}[-/.][0-9]{1,2})"#
        if let raw = firstCapture(pattern, in: text), let date = parseFlexibleDate(raw) {
            return date
        }
        return parseFlexibleDate(firstCapture(
            #"\b((?:19|20)\d{2}[-/.](0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01]))\b"#,
            in: String(text.prefix(400))
        ) ?? "")
    }

    static func parseFlexibleDate(_ raw: String) -> Date? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let formats = ["yyyy-MM-dd", "yyyy/MM/dd", "yyyy.MM.dd", "dd-MM-yyyy", "dd/MM/yyyy", "dd.MM.yyyy", "dd-MM-yy", "dd/MM/yy"]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    static func decimal(from raw: String) -> Decimal? {
        var normalized = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.contains(",") {
            normalized = normalized.replacingOccurrences(of: ".", with: "").replacingOccurrences(of: ",", with: ".")
        }
        return Decimal(string: normalized)
    }

    static func firstCapture(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges > 1,
              let swift = Range(match.range(at: 1), in: text) else { return nil }
        return String(text[swift])
    }

    #if canImport(FoundationModels)
    /// TODO: Call `LanguageModelSession` + a `@Generable` schema once deployment is raised
    /// to an OS that ships Foundation Models. Returning `nil` keeps macOS 14 / Personal Team
    /// on the heuristic path even if a newer SDK can import the module.
    static func extractWithFoundationModels(
        from document: DocumentRecord,
        fallback: StructuredDocumentFields
    ) async -> StructuredDocumentFields? {
        _ = document
        _ = fallback
        return nil
    }
    #endif
}

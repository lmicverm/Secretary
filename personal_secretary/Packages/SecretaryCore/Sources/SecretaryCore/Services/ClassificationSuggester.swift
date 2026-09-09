import Foundation

/// A ready-to-apply classification suggestion.
public struct ClassificationSuggestion: Identifiable, Hashable, Sendable {
    public var id: String { "\(space.rawValue)/\(category)/\(year.map(String.init) ?? "none")/\(documentType)/\(isNewCategory ? "new" : "known")" }
    public var space: DocumentSpace
    public var category: String
    public var year: Int?
    public var documentType: String
    public var shortTitle: String
    public var confidence: Double
    public var reason: String
    /// True when this category is not in the default taxonomy / existing folders yet.
    public var isNewCategory: Bool

    public init(
        space: DocumentSpace,
        category: String,
        year: Int? = nil,
        documentType: String = "document",
        shortTitle: String,
        confidence: Double,
        reason: String,
        isNewCategory: Bool = false
    ) {
        self.space = space
        self.category = category
        self.year = year
        self.documentType = documentType
        self.shortTitle = shortTitle
        self.confidence = confidence
        self.reason = reason
        self.isNewCategory = isNewCategory
    }

    public var destinationLabel: String {
        let base: String
        if let year {
            base = "\(space.rawValue) / \(category) / \(year)"
        } else {
            base = "\(space.rawValue) / \(category)"
        }
        return isNewCategory ? "\(base) (new)" : base
    }

    public func asTarget(notes: String = "", tags: [String] = [], expiryDate: Date? = nil) -> ClassificationTarget {
        ClassificationTarget(
            space: space,
            category: category,
            year: FolderSchema.normalizedYear(year),
            documentType: documentType,
            shortTitle: shortTitle,
            notes: notes,
            tags: tags,
            expiryDate: expiryDate
        )
    }
}

/// Suggests destinations from similar past filings, learned tokens, and Belgian keyword heuristics.
public enum ClassificationSuggester {
    public static func suggestions(
        for document: DocumentRecord,
        catalog: [DocumentRecord],
        learning: ClassificationLearningStore,
        limit: Int = 5
    ) -> [ClassificationSuggestion] {
        let fullText = [document.filename, document.title, document.notes, document.ocrText]
            .joined(separator: "\n")
        let tokens = TextFeatures.tokens(from: fullText)
        let detectedYear = FolderSchema.normalizedYear(TextFeatures.detectYear(from: fullText))
        let title = suggestedTitle(for: document)
        let knownCategories = knownCategoryNames(from: catalog)
        var scored: [String: Accumulator] = [:]

        // 1) Similar already-classified documents
        let classified = catalog.filter { !$0.isInbox && !$0.isArchived && $0.space != nil && $0.category != nil }
        for other in classified {
            let otherTokens = TextFeatures.tokens(
                from: [other.filename, other.title, other.notes, other.ocrText].joined(separator: "\n")
            )
            let overlap = TextFeatures.jaccard(tokens, otherTokens)
            guard overlap >= 0.08 else { continue }
            let year = detectedYear ?? FolderSchema.normalizedYear(other.year)
            let key = destinationKey(space: other.space!, category: other.category!, year: year)
            var acc = scored[key] ?? Accumulator(
                space: other.space!,
                category: other.category!,
                year: year,
                documentType: inferredType(from: other.filename) ?? "document",
                isNewCategory: !knownCategories.contains(normalizedCategoryKey(other.category!))
            )
            acc.score += overlap * 4.0
            acc.year = year
            acc.reasons.insert("similar to \(other.displayTitle)")
            if let type = inferredType(from: other.filename) {
                acc.documentType = type
            }
            scored[key] = acc
        }

        // 2) Learned token → destination weights
        for signal in learning.matchingSignals(tokens: tokens) {
            guard let space = DocumentSpace(rawValue: signal.space) else { continue }
            let year = detectedYear ?? FolderSchema.normalizedYear(signal.year)
            let key = destinationKey(space: space, category: signal.category, year: year)
            var acc = scored[key] ?? Accumulator(
                space: space,
                category: signal.category,
                year: year,
                documentType: signal.documentType ?? "document",
                isNewCategory: !knownCategories.contains(normalizedCategoryKey(signal.category))
            )
            acc.score += min(Double(signal.weight), 12) * 0.35
            acc.year = year
            acc.reasons.insert("learned from past filings")
            if let type = signal.documentType {
                acc.documentType = type
            }
            scored[key] = acc
        }

        // 3) Keyword heuristics for known taxonomy
        for rule in KeywordRules.rules {
            guard tokens.contains(where: { rule.keywords.contains($0) }) else { continue }
            let year = (rule.preferYear || detectedYear != nil) ? detectedYear : nil
            let key = destinationKey(space: rule.space, category: rule.category, year: year)
            var acc = scored[key] ?? Accumulator(
                space: rule.space,
                category: rule.category,
                year: year,
                documentType: rule.documentType,
                isNewCategory: false
            )
            acc.score += rule.weight
            acc.year = year
            acc.reasons.insert(rule.reason)
            acc.documentType = rule.documentType
            scored[key] = acc
        }

        // 4) Propose extra / new categories when content points outside the default set
        for proposal in NewCategoryRules.proposals {
            guard tokens.contains(where: { proposal.keywords.contains($0) }) else { continue }
            let exists = knownCategories.contains(normalizedCategoryKey(proposal.category))
            let year = (proposal.preferYear || detectedYear != nil) ? detectedYear : nil
            let key = destinationKey(space: proposal.space, category: proposal.category, year: year)
            var acc = scored[key] ?? Accumulator(
                space: proposal.space,
                category: proposal.category,
                year: year,
                documentType: proposal.documentType,
                isNewCategory: !exists
            )
            acc.score += proposal.weight
            acc.year = year
            acc.isNewCategory = !exists
            acc.reasons.insert(exists ? proposal.reason : "new category · \(proposal.reason)")
            acc.documentType = proposal.documentType
            scored[key] = acc
        }

        // 5) If nothing strong matched, invent a category from distinctive document tokens
        let bestScore = scored.values.map(\.score).max() ?? 0
        if bestScore < 1.6, let invented = inventCategory(from: tokens, title: title, known: knownCategories) {
            let year = detectedYear
            let key = destinationKey(space: invented.space, category: invented.category, year: year)
            if scored[key] == nil {
                scored[key] = Accumulator(
                    space: invented.space,
                    category: invented.category,
                    year: year,
                    documentType: invented.documentType,
                    isNewCategory: true,
                    score: 1.4,
                    reasons: ["suggested from document wording"]
                )
            }
        }

        return scored.values
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { acc in
                ClassificationSuggestion(
                    space: acc.space,
                    category: acc.category,
                    year: FolderSchema.normalizedYear(acc.year),
                    documentType: acc.documentType,
                    shortTitle: title,
                    confidence: min(acc.score / 6.0, 1.0),
                    reason: {
                        var parts = Array(acc.reasons.prefix(2))
                        if let y = FolderSchema.normalizedYear(acc.year) {
                            parts.append("year \(y) from document")
                        }
                        return parts.joined(separator: " · ")
                    }(),
                    isNewCategory: acc.isNewCategory
                )
            }
    }

    public static func suggestedTitle(for document: DocumentRecord) -> String {
        DocumentTitleGenerator.makeTitle(
            originalFilename: document.originalFilename,
            filename: document.filename,
            ocrText: document.ocrText,
            documentType: inferredType(from: document.filename)
        )
    }

    public static func knownCategoryNames(from catalog: [DocumentRecord]) -> Set<String> {
        var names = Set(DefaultTaxonomy.personalCategories.map(normalizedCategoryKey)
            + DefaultTaxonomy.bvCategories.map(normalizedCategoryKey))
        for record in catalog {
            if let category = record.category {
                names.insert(normalizedCategoryKey(category))
            }
        }
        return names
    }

    public static func normalizedCategoryKey(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// Turn a free-form label into a safe folder category name.
    public static func sanitizeCategoryName(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Misc" }
        let parts = trimmed
            .replacingOccurrences(of: #"[_/\\]+"#, with: " ", options: .regularExpression)
            .split(whereSeparator: { $0.isWhitespace || $0 == "-" })
            .map(String.init)
            .filter { !$0.isEmpty }
        let joined = parts
            .map { part -> String in
                guard let first = part.first else { return part }
                return String(first).uppercased() + part.dropFirst().lowercased()
            }
            .joined()
        let allowed = CharacterSet.alphanumerics
        let compact = String(joined.unicodeScalars.compactMap { allowed.contains($0) ? Character($0) : nil })
        return compact.isEmpty ? "Misc" : String(compact.prefix(40))
    }

    private static func inventCategory(
        from tokens: Set<String>,
        title: String,
        known: Set<String>
    ) -> (space: DocumentSpace, category: String, documentType: String)? {
        let blocked: Set<String> = TextFeatures.stopwords.union([
            "document", "import", "scan", "photo", "drop", "pdf", "page", "belgium", "belgie", "belgië",
            "date", "datum", "naam", "name", "adres", "address", "tel", "email", "www"
        ])
        let candidates = tokens
            .filter { $0.count >= 5 && !blocked.contains($0) && $0.rangeOfCharacter(from: .decimalDigits) == nil }
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs < rhs
            }
        guard let best = candidates.first else {
            let fromTitle = sanitizeCategoryName(title)
            let key = normalizedCategoryKey(fromTitle)
            guard !known.contains(key), fromTitle != "Misc", fromTitle.count >= 4 else { return nil }
            return (.personal, fromTitle, "document")
        }
        let category = sanitizeCategoryName(best)
        let key = normalizedCategoryKey(category)
        guard !known.contains(key) else { return nil }
        let space: DocumentSpace = tokens.contains(where: { ["bv", "btw", "vat", "vennootschap", "invoice", "factuur"].contains($0) })
            ? .bv : .personal
        return (space, category, "document")
    }

    private static func preferYear(from other: DocumentRecord, tokens: Set<String>) -> Int? {
        FolderSchema.normalizedYear(TextFeatures.detectYear(in: tokens) ?? other.year)
    }

    private static func inferredType(from filename: String) -> String? {
        let parts = (filename as NSString).deletingPathExtension.split(separator: "__")
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    private static func destinationKey(space: DocumentSpace, category: String, year: Int?) -> String {
        "\(space.rawValue)|\(category)|\(year.map(String.init) ?? "")"
    }

    private struct Accumulator {
        var space: DocumentSpace
        var category: String
        var year: Int?
        var documentType: String
        var isNewCategory: Bool = false
        var score: Double = 0
        var reasons: Set<String> = []
    }
}

// MARK: - Text features

/// Public entry point for extracting a calendar year from document text.
public enum DocumentDateParser {
    public static func year(from text: String) -> Int? {
        FolderSchema.normalizedYear(TextFeatures.detectYear(from: text))
    }

    public static func year(in document: DocumentRecord) -> Int? {
        year(from: [document.filename, document.title, document.notes, document.ocrText].joined(separator: "\n"))
    }
}

enum TextFeatures {
    static let stopwords: Set<String> = [
        "de", "het", "een", "van", "en", "voor", "met", "op", "aan", "bij", "is", "te", "dat", "die",
        "the", "and", "for", "with", "from", "this", "that", "your", "you", "are", "was", "were",
        "le", "la", "les", "des", "une", "un", "du", "au", "aux", "et", "pour", "dans",
        "pdf", "page", "www", "http", "https", "com", "be", "nl", "fr", "document", "import", "scan", "photo"
    ]

    static func tokens(from text: String) -> Set<String> {
        let lowered = text.lowercased()
        let parts = lowered.split { !$0.isLetter && !$0.isNumber }
        var result = Set<String>()
        for part in parts {
            let token = String(part)
            guard token.count >= 3, !stopwords.contains(token) else { continue }
            result.insert(token)
            // Keep short alphanumeric codes like KBC, BTW if length 3+
        }
        return result
    }

    static func jaccard(_ a: Set<String>, _ b: Set<String>) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let inter = a.intersection(b).count
        let union = a.union(b).count
        guard union > 0 else { return 0 }
        return Double(inter) / Double(union)
    }

    static func detectYear(in tokens: Set<String>) -> Int? {
        detectYear(from: tokens.joined(separator: " "))
    }

    /// Pull a calendar year from document text using real date patterns (BE/EU + ISO).
    static func detectYear(from text: String) -> Int? {
        let current = Calendar.current.component(.year, from: Date())
        let range = 1990...(current + 1)
        var scores: [Int: Int] = [:]

        func consider(_ year: Int, weight: Int = 1) {
            guard range.contains(year) else { return }
            scores[year, default: 0] += weight
        }

        // Explicit tax-year phrases (Belgian)
        let phrasePatterns = [
            #"aanslagjaar\s*[:=]?\s*((?:19|20)\d{2})"#,
            #"inkomstenjaar\s*[:=]?\s*((?:19|20)\d{2})"#,
            #"boekjaar\s*[:=]?\s*((?:19|20)\d{2})"#,
            #"fiscal(?:e)?\s+jaar\s*[:=]?\s*((?:19|20)\d{2})"#,
            #"tax\s*year\s*[:=]?\s*((?:19|20)\d{2})"#,
            #"jaar\s*[:=]?\s*((?:19|20)\d{2})"#
        ]
        for pattern in phrasePatterns {
            for match in matches(pattern, in: text) {
                if let y = Int(match) { consider(y, weight: 5) }
            }
        }

        // ISO: 2024-03-15 or 2024/03/15
        for match in matches(#"\b((?:19|20)\d{2})[-/.](0?[1-9]|1[0-2])[-/.](0?[1-9]|[12]\d|3[01])\b"#, in: text) {
            if let y = Int(match) { consider(y, weight: 3) }
        }

        // EU/BE: 15.03.2024 / 15-03-2024 / 15/03/2024
        for match in matches(#"\b(?:0?[1-9]|[12]\d|3[01])[-/.](0?[1-9]|1[0-2])[-/.]((?:19|20)\d{2})\b"#, in: text) {
            if let y = Int(match) { consider(y, weight: 3) }
        }

        // Month-year: 03/2024 or 03.2024
        for match in matches(#"\b(0?[1-9]|1[0-2])[-/.]((?:19|20)\d{2})\b"#, in: text) {
            if let y = Int(match) { consider(y, weight: 2) }
        }

        // Standalone years (weaker)
        for match in matches(#"\b((?:19|20)\d{2})\b"#, in: text) {
            if let y = Int(match) { consider(y, weight: 1) }
        }

        return scores.max(by: { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value < rhs.value }
            return lhs.key < rhs.key
        })?.key
    }

    private static func matches(_ pattern: String, in text: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return []
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, options: [], range: range).compactMap { result in
            // Prefer the last capture group when present (often the year).
            let group = result.numberOfRanges > 1 ? result.numberOfRanges - 1 : 0
            guard let swiftRange = Range(result.range(at: group), in: text) else { return nil }
            return String(text[swiftRange])
        }
    }

    /// Distinctive tokens worth remembering for learning (rarer / longer preferred).
    static func learningTokens(from text: String, limit: Int = 24) -> [String] {
        let all = Array(tokens(from: text))
        return all
            .sorted { lhs, rhs in
                if lhs.count != rhs.count { return lhs.count > rhs.count }
                return lhs < rhs
            }
            .prefix(limit)
            .map { $0 }
    }
}

// MARK: - Extra / new category proposals (outside default taxonomy)

private enum NewCategoryRules {
    struct Proposal {
        let keywords: Set<String>
        let space: DocumentSpace
        let category: String
        let documentType: String
        let weight: Double
        let preferYear: Bool
        let reason: String
    }

    static let proposals: [Proposal] = [
        Proposal(keywords: ["elektriciteit", "electricity", "gas", "waterfactuur", "fluvius", "engie", "luminus", "totalenergies", "nutsvoorziening"], space: .personal, category: "Utilities", documentType: "bill", weight: 2.3, preferYear: true, reason: "energy/utilities keywords"),
        Proposal(keywords: ["proximus", "telenet", "orange", "mobile", "telecom", "abonnement", "simkaart"], space: .personal, category: "Telecom", documentType: "bill", weight: 2.2, preferYear: true, reason: "telecom keywords"),
        Proposal(keywords: ["pensioen", "pension", "pensioensparen", "vapo", "tak21", "tak23"], space: .personal, category: "Pension", documentType: "pension", weight: 2.2, preferYear: true, reason: "pension keywords"),
        Proposal(keywords: ["advocaat", "notarisakte", "rechtbank", "dagvaarding", "vonnis", "legal", "lawyer"], space: .personal, category: "Legal", documentType: "legal", weight: 2.1, preferYear: false, reason: "legal keywords"),
        Proposal(keywords: ["vlucht", "flight", "hotel", "booking", "reise", "travel", "treinbiljet", "eurostar"], space: .personal, category: "Travel", documentType: "travel", weight: 2.0, preferYear: true, reason: "travel keywords"),
        Proposal(keywords: ["garantie", "warranty", "aankoopbewijs", "receipt", "kassaticket"], space: .personal, category: "Purchases", documentType: "receipt", weight: 1.9, preferYear: true, reason: "purchase/receipt keywords"),
        Proposal(keywords: ["lidgeld", "membership", "club", "abonnementskaart"], space: .personal, category: "Memberships", documentType: "membership", weight: 1.8, preferYear: true, reason: "membership keywords"),
        Proposal(keywords: ["schenking", "gift", "donatie", "donation"], space: .personal, category: "Donations", documentType: "donation", weight: 1.8, preferYear: true, reason: "donation keywords"),
        Proposal(keywords: ["attest", "certificate", "vergunning", "permit", "machtiging"], space: .personal, category: "Certificates", documentType: "certificate", weight: 1.9, preferYear: false, reason: "certificate/permit keywords"),
        Proposal(keywords: ["huisdier", "dierenarts", "veterinarian", "pet"], space: .personal, category: "Pets", documentType: "vet", weight: 2.0, preferYear: false, reason: "pet keywords"),
        Proposal(keywords: ["octrooi", "patent", "merk", "trademark", "ip"], space: .bv, category: "IntellectualProperty", documentType: "ip", weight: 2.1, preferYear: false, reason: "IP keywords"),
        Proposal(keywords: ["subsidie", "grant", "vlaio", "kmo"], space: .bv, category: "Grants", documentType: "grant", weight: 2.0, preferYear: true, reason: "grant/subsidy keywords"),
        Proposal(keywords: ["huurwaarborg", "rental", "property", "vastgoed"], space: .bv, category: "RealEstate", documentType: "property", weight: 1.9, preferYear: false, reason: "real-estate keywords"),
        Proposal(keywords: ["software", "saas", "licentie", "license", "aws", "azure"], space: .bv, category: "Software", documentType: "license", weight: 1.8, preferYear: true, reason: "software/SaaS keywords"),
    ]
}

// MARK: - Bootstrap keyword rules

private enum KeywordRules {
    struct Rule {
        let keywords: Set<String>
        let space: DocumentSpace
        let category: String
        let documentType: String
        let weight: Double
        let preferYear: Bool
        let reason: String
    }

    static let rules: [Rule] = [
        Rule(keywords: ["verzekering", "verzekeringspolis", "polis", "insurance", "assurance", "premie"], space: .personal, category: "Insurance", documentType: "policy", weight: 2.2, preferYear: false, reason: "insurance keywords"),
        Rule(keywords: ["aanslagbiljet", "belasting", "tax", "ipp", "personenbelasting", "taxatie"], space: .personal, category: "Tax", documentType: "tax", weight: 2.4, preferYear: true, reason: "tax keywords"),
        Rule(keywords: ["btw", "vat", "jaarrekening", "balans", "boekhoud", "accounting"], space: .bv, category: "Tax", documentType: "tax", weight: 2.3, preferYear: true, reason: "BV tax/accounting keywords"),
        Rule(keywords: ["factuur", "invoice", "creditnota"], space: .bv, category: "Invoices", documentType: "invoice", weight: 2.0, preferYear: true, reason: "invoice keywords"),
        Rule(keywords: ["statuten", "aandeelhouders", "governance", "notulen", "bestuur"], space: .bv, category: "Governance", documentType: "governance", weight: 2.2, preferYear: false, reason: "governance keywords"),
        Rule(keywords: ["rsz", "sociale", "secrétariat", "socialsecretariat", "loonfiche"], space: .bv, category: "SocialSecretariat", documentType: "social", weight: 2.2, preferYear: true, reason: "social secretariat keywords"),
        Rule(keywords: ["bank", "rekening", "iban", "bankafschrift", "statement", "kbc", "belfius", "ing"], space: .personal, category: "Banking", documentType: "statement", weight: 1.6, preferYear: true, reason: "banking keywords"),
        Rule(keywords: ["school", "rapport", "inschrijving", "tuition", "ouderbijdrage"], space: .personal, category: "School", documentType: "school", weight: 2.0, preferYear: true, reason: "school keywords"),
        Rule(keywords: ["huur", "lease", "hypotheek", "notaris", "akte", "kadaster", "woning"], space: .personal, category: "Housing", documentType: "housing", weight: 2.0, preferYear: false, reason: "housing keywords"),
        Rule(keywords: ["identiteitskaart", "paspoort", "rijbewijs", "eidas"], space: .personal, category: "Identity", documentType: "id", weight: 2.4, preferYear: false, reason: "identity keywords"),
        Rule(keywords: ["ziekenhuis", "dokter", "apotheek", "mutualiteit", "ziekteverzekering"], space: .personal, category: "Health", documentType: "health", weight: 2.0, preferYear: false, reason: "health keywords"),
        Rule(keywords: ["voertuig", "auto", "div", "keuring", "verzekeringsbewijs"], space: .personal, category: "Vehicles", documentType: "vehicle", weight: 1.8, preferYear: false, reason: "vehicle keywords"),
        Rule(keywords: ["loonbrief", "payroll", "werkgever", "arbeidscontract"], space: .personal, category: "Work", documentType: "payroll", weight: 2.0, preferYear: true, reason: "work keywords"),
        Rule(keywords: ["contract", "overeenkomst", "agreement"], space: .bv, category: "Contracts", documentType: "contract", weight: 1.5, preferYear: false, reason: "contract keywords"),
    ]
}

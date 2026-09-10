import Foundation

/// Builds short, human-readable titles from filenames and OCR text.
public enum DocumentTitleGenerator {
    /// Prefer OCR when it yields a clear subject; otherwise clean the source filename.
    public static func makeTitle(
        originalFilename: String,
        filename: String,
        ocrText: String = "",
        documentType: String? = nil
    ) -> String {
        let source = originalFilename.isEmpty ? filename : originalFilename
        let fromFile = titleFromFilename(source, documentType: documentType)
        if let fromOCR = titleFromOCR(ocrText, hintType: documentType), !fromOCR.isEmpty {
            if SuggestionSanitizer.isAcceptablePhrase(fromOCR),
               !SuggestionSanitizer.looksLikeOCRFragment(fromOCR, filenameTitle: fromFile) {
                return fromOCR
            }
        }
        return fromFile
    }

    public static func titleFromFilename(_ filename: String, documentType: String? = nil) -> String {
        var base = (filename as NSString).deletingPathExtension
        base = stripSecretaryFilenamePrefix(base)
        base = base
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // Drop trailing noise like scan001, copy, final
        let noise = ["copy", "final", "scan", "img", "image", "photo", "document", "doc", "file", "untitled"]
        var words = base.split(separator: " ").map(String.init)
        while let last = words.last?.lowercased(),
              noise.contains(last) || last.range(of: #"^\d{3,}$"#, options: .regularExpression) != nil {
            words.removeLast()
        }

        var title = words.joined(separator: " ")
        if title.isEmpty {
            title = documentType.map { prettyType($0) } ?? "Document"
        }
        return String(title.prefix(72)).trimmingCharacters(in: .whitespacesAndNewlines).capitalizedWords
    }

    /// First short OCR line that looks like an issuer / correspondent name.
    public static func correspondentHint(from ocrText: String) -> String? {
        let lines = ocrText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && $0.count >= 4 && $0.count <= 90 }
            .prefix(12)

        let issuer = lines.first { line in
            let lower = line.lowercased()
            if lower.range(of: #"^\d{1,2}[-/.]\d{1,2}[-/.]\d{2,4}$"#, options: .regularExpression) != nil {
                return false
            }
            if lower.contains("page ") || lower.hasPrefix("http") { return false }
            let blocked: Set<String> = [
                "factuur", "invoice", "creditnota", "btw", "vat", "totaal", "total",
                "aanslagbiljet", "verzekering", "polis"
            ]
            if blocked.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) { return false }
            guard SuggestionSanitizer.isAcceptablePhrase(line) else { return false }
            let letters = line.filter(\.isLetter).count
            return letters >= 4 && line.count <= 48
        }
        guard let issuer else { return nil }
        return String(issuer.prefix(48)).capitalizedWords
    }

    public static func titleFromOCR(_ text: String, hintType: String? = nil) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 12 else { return nil }

        let patterns: [(String, String)] = [
            (#"(?i)\baanslagbiljet\b"#, "Aanslagbiljet"),
            (#"(?i)\bpersonenbelasting\b"#, "Personenbelasting"),
            (#"(?i)\bfactuur\b|\binvoice\b"#, "Factuur"),
            (#"(?i)\bcreditnota\b|\bcredit\s*note\b"#, "Creditnota"),
            (#"(?i)\bpolis\b|\bverzekeringspolis\b|\binsurance\s*policy\b"#, "Verzekeringspolis"),
            (#"(?i)\bbankafschrift\b|\baccount\s*statement\b"#, "Bankafschrift"),
            (#"(?i)\bloonfiche\b|\bloonbrief\b|\bpayslip\b"#, "Loonfiche"),
            (#"(?i)\bjaarrekening\b"#, "Jaarrekening"),
            (#"(?i)\bhuurcontract\b|\bhuurovereenkomst\b"#, "Huurcontract"),
            (#"(?i)\bidentiteitskaart\b|\beID\b"#, "Identiteitskaart"),
            (#"(?i)\brijbewijs\b"#, "Rijbewijs"),
            (#"(?i)\bpaspoort\b|\bpassport\b"#, "Paspoort"),
            (#"(?i)\bkeuring\b"#, "Keuring"),
            (#"(?i)\bovereenkomst\b|\bcontract\b"#, "Overeenkomst"),
            (#"(?i)\bnotulen\b"#, "Notulen"),
            (#"(?i)\bstatuten\b"#, "Statuten"),
        ]

        var subject: String?
        for (pattern, label) in patterns {
            if trimmed.range(of: pattern, options: .regularExpression) != nil {
                subject = label
                break
            }
        }

        let issuer = correspondentHint(from: text)

        if let subject, let issuer {
            let cleanIssuer = issuer.capitalizedWords
            if !cleanIssuer.localizedCaseInsensitiveContains(subject) {
                return String("\(subject) — \(cleanIssuer)".prefix(72))
            }
            return subject
        }
        if let subject { return subject }
        if let hintType, hintType != "document", hintType != "import", hintType != "scan", hintType != "drop" {
            if let issuer {
                return String("\(prettyType(hintType)) — \(issuer.capitalizedWords)".prefix(72))
            }
            return prettyType(hintType)
        }
        if let issuer, issuer.split(separator: " ").count <= 6 {
            return String(issuer.prefix(72)).capitalizedWords
        }
        return nil
    }

    /// True when the stored title still looks like a raw import/filename stub.
    public static func looksGeneric(_ title: String, filename: String, originalFilename: String) -> Bool {
        let t = title.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if t.isEmpty || t == "document" || t == "import" || t == "scan" || t == "drop" || t == "photo" {
            return true
        }
        let fromFile = titleFromFilename(originalFilename.isEmpty ? filename : originalFilename).lowercased()
        return t == fromFile || t == DocumentRecord.defaultTitle(from: filename).lowercased()
    }

    private static func stripSecretaryFilenamePrefix(_ base: String) -> String {
        var value = base
        value = value.replacingOccurrences(
            of: #"^\d{4}-\d{2}-\d{2}__"#,
            with: "",
            options: .regularExpression
        )
        // type__title
        if let range = value.range(of: #"^[a-z0-9-]+__"#, options: [.regularExpression, .caseInsensitive]) {
            value = String(value[range.upperBound...])
        }
        return value
    }

    private static func prettyType(_ type: String) -> String {
        type
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .capitalizedWords
    }
}

private extension String {
    var capitalizedWords: String {
        split(separator: " ")
            .map { word -> String in
                let s = String(word)
                // Keep short ALL-CAPS tokens (KBC, BTW, RSZ, IBAN)
                if s.count <= 4, s.uppercased() == s, s.rangeOfCharacter(from: .letters) != nil {
                    return s.uppercased()
                }
                guard let first = s.first else { return s }
                return String(first).uppercased() + s.dropFirst().lowercased()
            }
            .joined(separator: " ")
    }
}

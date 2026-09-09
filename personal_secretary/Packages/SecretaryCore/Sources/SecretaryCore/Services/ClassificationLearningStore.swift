import Foundation

/// Persists token → destination weights learned when you classify documents.
public final class ClassificationLearningStore: @unchecked Sendable {
    public struct Signal: Codable, Hashable, Sendable {
        public var token: String
        public var space: String
        public var category: String
        public var year: Int?
        public var documentType: String?
        public var weight: Int

        public init(
            token: String,
            space: String,
            category: String,
            year: Int? = nil,
            documentType: String? = nil,
            weight: Int = 1
        ) {
            self.token = token
            self.space = space
            self.category = category
            self.year = year
            self.documentType = documentType
            self.weight = weight
        }
    }

    private struct Payload: Codable {
        var signals: [Signal]
    }

    private let fileURL: URL
    private let queue = DispatchQueue(label: "be.secretary.ClassificationLearningStore")
    private var signals: [Signal]

    public init(libraryRoot: URL) {
        let meta = libraryRoot.appendingPathComponent(FolderSchema.metaFolder, isDirectory: true)
        self.fileURL = meta.appendingPathComponent("learning.json")
        if let data = try? Data(contentsOf: fileURL),
           let payload = try? JSONDecoder().decode(Payload.self, from: data) {
            self.signals = payload.signals
        } else {
            self.signals = []
        }
    }

    public func matchingSignals(tokens: Set<String>) -> [Signal] {
        queue.sync {
            signals.filter { tokens.contains($0.token) }
        }
    }

    /// Call after a successful classify so future similar docs get better suggestions.
    public func learn(from document: DocumentRecord, target: ClassificationTarget) {
        let text = [document.filename, document.title, document.notes, document.ocrText]
            .joined(separator: "\n")
        let tokens = TextFeatures.learningTokens(from: text)
        queue.sync {
            for token in tokens {
                if let idx = signals.firstIndex(where: {
                    $0.token == token
                        && $0.space == target.space.rawValue
                        && $0.category == target.category
                }) {
                    signals[idx].weight += 1
                    signals[idx].year = target.year ?? signals[idx].year
                    signals[idx].documentType = target.documentType
                } else {
                    signals.append(
                        Signal(
                            token: token,
                            space: target.space.rawValue,
                            category: target.category,
                            year: target.year,
                            documentType: target.documentType,
                            weight: 1
                        )
                    )
                }
            }
            // Cap store size — keep strongest signals
            if signals.count > 2000 {
                signals = signals.sorted { $0.weight > $1.weight }.prefix(1500).map { $0 }
            }
            persistLocked()
        }
    }

    private func persistLocked() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(Payload(signals: signals))
            try CloudFileCoordinator.coordinatedWrite(to: fileURL, options: .forReplacing) { url in
                try data.write(to: url, options: .atomic)
            }
        } catch {
            // Learning is best-effort; never fail classification because of it.
        }
    }
}

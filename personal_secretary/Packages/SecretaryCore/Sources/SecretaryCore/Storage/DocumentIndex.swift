import Foundation
import SQLite3

/// Rebuildable SQLite + FTS5 index. Files on disk remain the source of truth.
public final class DocumentIndex: @unchecked Sendable {
    private var db: OpaquePointer?
    private let dbURL: URL
    private let queue = DispatchQueue(label: "be.secretary.DocumentIndex")

    public init(databaseURL: URL) throws {
        self.dbURL = databaseURL
        try open()
        try migrate()
    }

    deinit {
        if let db {
            sqlite3_close(db)
        }
    }

    public func close() {
        queue.sync {
            if let db {
                sqlite3_close(db)
                self.db = nil
            }
        }
    }

    // MARK: - CRUD

    public func upsert(_ record: DocumentRecord) throws {
        try queue.sync {
            let tags = record.tags.joined(separator: ",")
            let sql = """
            INSERT INTO documents (
                id, relative_path, filename, space, category, year, title, notes, tags,
                content_hash, ocr_text, is_favorite, expiry_date, file_size,
                created_at, modified_at, indexed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT(id) DO UPDATE SET
                relative_path=excluded.relative_path,
                filename=excluded.filename,
                space=excluded.space,
                category=excluded.category,
                year=excluded.year,
                title=excluded.title,
                notes=excluded.notes,
                tags=excluded.tags,
                content_hash=excluded.content_hash,
                ocr_text=excluded.ocr_text,
                is_favorite=excluded.is_favorite,
                expiry_date=excluded.expiry_date,
                file_size=excluded.file_size,
                created_at=excluded.created_at,
                modified_at=excluded.modified_at,
                indexed_at=excluded.indexed_at;
            """
            let stmt = try prepare(sql)
            defer { sqlite3_finalize(stmt) }

            bind(stmt, 1, record.id)
            bind(stmt, 2, record.relativePath)
            bind(stmt, 3, record.filename)
            bind(stmt, 4, record.space?.rawValue)
            bind(stmt, 5, record.category)
            if let year = record.year {
                sqlite3_bind_int(stmt, 6, Int32(year))
            } else {
                sqlite3_bind_null(stmt, 6)
            }
            bind(stmt, 7, record.title)
            bind(stmt, 8, record.notes)
            bind(stmt, 9, tags)
            bind(stmt, 10, record.contentHash)
            bind(stmt, 11, record.ocrText)
            sqlite3_bind_int(stmt, 12, record.isFavorite ? 1 : 0)
            if let expiry = record.expiryDate {
                sqlite3_bind_double(stmt, 13, expiry.timeIntervalSince1970)
            } else {
                sqlite3_bind_null(stmt, 13)
            }
            sqlite3_bind_int64(stmt, 14, record.fileSize)
            sqlite3_bind_double(stmt, 15, record.createdAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 16, record.modifiedAt.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 17, record.indexedAt.timeIntervalSince1970)

            try stepDone(stmt)

            try upsertFTS(record)
        }
    }

    public func delete(id: String) throws {
        try queue.sync {
            try exec("DELETE FROM documents WHERE id = '\(escape(id))';")
            try exec("DELETE FROM documents_fts WHERE id = '\(escape(id))';")
        }
    }

    public func delete(relativePath: String) throws {
        try queue.sync {
            if let existing = try? fetchOneUnlocked(relativePath: relativePath) {
                try exec("DELETE FROM documents WHERE id = '\(escape(existing.id))';")
                try exec("DELETE FROM documents_fts WHERE id = '\(escape(existing.id))';")
            }
        }
    }

    public func fetch(id: String) throws -> DocumentRecord? {
        try queue.sync {
            try fetchOneUnlocked(id: id)
        }
    }

    public func fetch(relativePath: String) throws -> DocumentRecord? {
        try queue.sync {
            try fetchOneUnlocked(relativePath: relativePath)
        }
    }

    public func fetchAll() throws -> [DocumentRecord] {
        try queue.sync {
            try fetchListUnlocked(sql: "SELECT * FROM documents ORDER BY modified_at DESC;")
        }
    }

    public func findByHash(_ hash: String, excludingID: String? = nil) throws -> [DocumentRecord] {
        try queue.sync {
            var sql = "SELECT * FROM documents WHERE content_hash = '\(escape(hash))'"
            if let excludingID {
                sql += " AND id != '\(escape(excludingID))'"
            }
            sql += ";"
            return try fetchListUnlocked(sql: sql)
        }
    }

    public func search(_ filter: DocumentFilter) throws -> [DocumentRecord] {
        try queue.sync {
            var clauses: [String] = []
            if filter.inboxOnly {
                clauses.append("relative_path LIKE 'Inbox/%'")
            }
            if filter.favoritesOnly {
                clauses.append("is_favorite = 1")
            }
            if let space = filter.space {
                clauses.append("space = '\(escape(space.rawValue))'")
            }
            if let category = filter.category {
                clauses.append("category = '\(escape(category))'")
            }
            if let year = filter.year {
                clauses.append("year = \(year)")
            }
            if let days = filter.expiringWithinDays {
                let now = Date().timeIntervalSince1970
                let until = now + Double(days) * 86400
                clauses.append("expiry_date IS NOT NULL AND expiry_date >= \(now) AND expiry_date <= \(until)")
            }

            let trimmed = filter.query.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                let whereSQL = clauses.isEmpty ? "" : "WHERE " + clauses.joined(separator: " AND ")
                return try fetchListUnlocked(sql: "SELECT * FROM documents \(whereSQL) ORDER BY modified_at DESC;")
            }

            // Each word must match somewhere in searchable fields (AND across words).
            let words = trimmed
                .split(whereSeparator: { $0.isWhitespace })
                .map(String.init)
                .filter { !$0.isEmpty }

            for word in words {
                let like = "%\(escapeLike(word))%"
                var orParts = [
                    "filename LIKE '\(like)' ESCAPE '\\'",
                    "title LIKE '\(like)' ESCAPE '\\'",
                    "notes LIKE '\(like)' ESCAPE '\\'",
                    "tags LIKE '\(like)' ESCAPE '\\'",
                    "ocr_text LIKE '\(like)' ESCAPE '\\'",
                    "relative_path LIKE '\(like)' ESCAPE '\\'",
                    "IFNULL(space,'') LIKE '\(like)' ESCAPE '\\'",
                    "IFNULL(category,'') LIKE '\(like)' ESCAPE '\\'"
                ]
                let ftsQuery = ftsSafeQuery(word)
                if !ftsQuery.isEmpty {
                    orParts.append("id IN (SELECT id FROM documents_fts WHERE documents_fts MATCH '\(escape(ftsQuery))')")
                }
                clauses.append("(" + orParts.joined(separator: " OR ") + ")")
            }

            let whereSQL = "WHERE " + clauses.joined(separator: " AND ")
            return try fetchListUnlocked(sql: "SELECT * FROM documents \(whereSQL) ORDER BY modified_at DESC;")
        }
    }

    public func clearAll() throws {
        try queue.sync {
            try exec("DELETE FROM documents;")
            try exec("DELETE FROM documents_fts;")
        }
    }

    // MARK: - Private

    private func open() throws {
        let dir = dbURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        if sqlite3_open(dbURL.path, &db) != SQLITE_OK {
            throw IndexError.openFailed(String(cString: sqlite3_errmsg(db)))
        }
        try exec("PRAGMA journal_mode=WAL;")
        try exec("PRAGMA foreign_keys=ON;")
    }

    private func migrate() throws {
        try exec("""
        CREATE TABLE IF NOT EXISTS documents (
            id TEXT PRIMARY KEY,
            relative_path TEXT NOT NULL UNIQUE,
            filename TEXT NOT NULL,
            space TEXT,
            category TEXT,
            year INTEGER,
            title TEXT NOT NULL DEFAULT '',
            notes TEXT NOT NULL DEFAULT '',
            tags TEXT NOT NULL DEFAULT '',
            content_hash TEXT,
            ocr_text TEXT NOT NULL DEFAULT '',
            is_favorite INTEGER NOT NULL DEFAULT 0,
            expiry_date REAL,
            file_size INTEGER NOT NULL DEFAULT 0,
            created_at REAL NOT NULL,
            modified_at REAL NOT NULL,
            indexed_at REAL NOT NULL
        );
        """)
        try exec("CREATE INDEX IF NOT EXISTS idx_documents_hash ON documents(content_hash);")
        try exec("CREATE INDEX IF NOT EXISTS idx_documents_space ON documents(space, category);")
        try exec("CREATE INDEX IF NOT EXISTS idx_documents_expiry ON documents(expiry_date);")

        // FTS5 external content-ish table keyed by id
        try exec("""
        CREATE VIRTUAL TABLE IF NOT EXISTS documents_fts USING fts5(
            id UNINDEXED,
            filename,
            title,
            notes,
            tags,
            ocr_text,
            relative_path,
            tokenize = 'porter unicode61'
        );
        """)
    }

    private func upsertFTS(_ record: DocumentRecord) throws {
        try exec("DELETE FROM documents_fts WHERE id = '\(escape(record.id))';")
        let sql = """
        INSERT INTO documents_fts (id, filename, title, notes, tags, ocr_text, relative_path)
        VALUES (?, ?, ?, ?, ?, ?, ?);
        """
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        bind(stmt, 1, record.id)
        bind(stmt, 2, record.filename)
        bind(stmt, 3, record.title)
        bind(stmt, 4, record.notes)
        bind(stmt, 5, record.tags.joined(separator: " "))
        bind(stmt, 6, record.ocrText)
        bind(stmt, 7, record.relativePath)
        try stepDone(stmt)
    }

    private func fetchOneUnlocked(id: String) throws -> DocumentRecord? {
        try fetchListUnlocked(sql: "SELECT * FROM documents WHERE id = '\(escape(id))' LIMIT 1;").first
    }

    private func fetchOneUnlocked(relativePath: String) throws -> DocumentRecord? {
        try fetchListUnlocked(sql: "SELECT * FROM documents WHERE relative_path = '\(escape(relativePath))' LIMIT 1;").first
    }

    private func fetchListUnlocked(sql: String) throws -> [DocumentRecord] {
        let stmt = try prepare(sql)
        defer { sqlite3_finalize(stmt) }
        var results: [DocumentRecord] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            results.append(rowToRecord(stmt))
        }
        return results
    }

    private func rowToRecord(_ stmt: OpaquePointer?) -> DocumentRecord {
        func text(_ idx: Int32) -> String {
            guard let c = sqlite3_column_text(stmt, idx) else { return "" }
            return String(cString: c)
        }
        func optText(_ idx: Int32) -> String? {
            guard sqlite3_column_type(stmt, idx) != SQLITE_NULL else { return nil }
            return text(idx)
        }
        let tags = text(8).split(separator: ",").map(String.init).filter { !$0.isEmpty }
        let spaceRaw = optText(3)
        return DocumentRecord(
            id: text(0),
            relativePath: text(1),
            filename: text(2),
            space: spaceRaw.flatMap(DocumentSpace.init(rawValue:)),
            category: optText(4),
            year: sqlite3_column_type(stmt, 5) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 5)),
            title: text(6),
            notes: text(7),
            tags: tags,
            contentHash: optText(9),
            ocrText: text(10),
            isFavorite: sqlite3_column_int(stmt, 11) == 1,
            expiryDate: sqlite3_column_type(stmt, 12) == SQLITE_NULL ? nil : Date(timeIntervalSince1970: sqlite3_column_double(stmt, 12)),
            fileSize: sqlite3_column_int64(stmt, 13),
            createdAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 14)),
            modifiedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 15)),
            indexedAt: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 16))
        )
    }

    private func prepare(_ sql: String) throws -> OpaquePointer? {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw IndexError.prepareFailed(String(cString: sqlite3_errmsg(db)))
        }
        return stmt
    }

    private func stepDone(_ stmt: OpaquePointer?) throws {
        let code = sqlite3_step(stmt)
        guard code == SQLITE_DONE else {
            throw IndexError.stepFailed(String(cString: sqlite3_errmsg(db)))
        }
    }

    private func exec(_ sql: String) throws {
        var err: UnsafeMutablePointer<CChar>?
        if sqlite3_exec(db, sql, nil, nil, &err) != SQLITE_OK {
            let message = err.map { String(cString: $0) } ?? "unknown"
            sqlite3_free(err)
            throw IndexError.execFailed(message)
        }
    }

    private func bind(_ stmt: OpaquePointer?, _ index: Int32, _ value: String?) {
        if let value {
            sqlite3_bind_text(stmt, index, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        } else {
            sqlite3_bind_null(stmt, index)
        }
    }

    private func escape(_ value: String) -> String {
        value.replacingOccurrences(of: "'", with: "''")
    }

    private func escapeLike(_ value: String) -> String {
        escape(value)
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    private func ftsSafeQuery(_ raw: String) -> String {
        let tokens = raw
            .split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count >= 1 }
        guard !tokens.isEmpty else { return "" }
        // FTS5 prefix query: verzek* matches verzekering
        return tokens.map { "\($0)*" }.joined(separator: " ")
    }

    public enum IndexError: Error, LocalizedError {
        case openFailed(String)
        case prepareFailed(String)
        case stepFailed(String)
        case execFailed(String)

        public var errorDescription: String? {
            switch self {
            case .openFailed(let m): return "Could not open index: \(m)"
            case .prepareFailed(let m): return "Could not prepare SQL: \(m)"
            case .stepFailed(let m): return "SQL step failed: \(m)"
            case .execFailed(let m): return "SQL exec failed: \(m)"
            }
        }
    }
}

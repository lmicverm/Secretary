import Foundation
import Security

/// Lightweight AgentMail REST client — poll when the app is open (no always-on server).
public struct AgentMailClient: Sendable {
    public var apiKey: String
    public var baseURL: URL

    public init(apiKey: String, baseURL: URL = URL(string: "https://api.agentmail.to")!) {
        self.apiKey = apiKey
        self.baseURL = baseURL
    }

    public struct InboxInfo: Decodable, Sendable {
        public var inboxId: String
        public var email: String?

        enum CodingKeys: String, CodingKey {
            case inboxId = "inbox_id"
            case email
        }
    }

    public struct MessageSummary: Decodable, Sendable, Identifiable {
        public var messageId: String
        public var subject: String?
        public var from: String?
        public var attachments: [AttachmentMeta]?

        public var id: String { messageId }

        enum CodingKeys: String, CodingKey {
            case messageId = "message_id"
            case subject
            case from
            case attachments
        }
    }

    public struct AttachmentMeta: Decodable, Sendable {
        public var attachmentId: String
        public var filename: String?
        public var contentType: String?
        public var contentDisposition: String?

        enum CodingKeys: String, CodingKey {
            case attachmentId = "attachment_id"
            case filename
            case contentType = "content_type"
            case contentDisposition = "content_disposition"
        }
    }

    private struct MessageListResponse: Decodable {
        var messages: [MessageSummary]
    }

    private struct AttachmentDownload: Decodable {
        var downloadURL: String
        var filename: String?

        enum CodingKeys: String, CodingKey {
            case downloadURL = "download_url"
            case filename
        }
    }

    private struct CreateInboxResponse: Decodable {
        var inboxId: String
        var email: String?

        enum CodingKeys: String, CodingKey {
            case inboxId = "inbox_id"
            case email
        }
    }

    public func listInboxes() async throws -> [InboxInfo] {
        struct Resp: Decodable { var inboxes: [InboxInfo]? }
        let resp: Resp = try await get(path: "/v0/inboxes")
        return resp.inboxes ?? []
    }

    public func createInbox(username: String, clientId: String) async throws -> InboxInfo {
        let body: [String: String] = [
            "username": username,
            "client_id": clientId
        ]
        let created: CreateInboxResponse = try await post(path: "/v0/inboxes", json: body)
        return InboxInfo(inboxId: created.inboxId, email: created.email)
    }

    public func listMessages(inboxId: String, limit: Int = 30) async throws -> [MessageSummary] {
        let resp: MessageListResponse = try await get(path: "/v0/inboxes/\(inboxId)/messages?limit=\(limit)")
        return resp.messages
    }

    public func downloadAttachment(
        inboxId: String,
        messageId: String,
        attachmentId: String
    ) async throws -> (Data, String) {
        let meta: AttachmentDownload = try await get(
            path: "/v0/inboxes/\(inboxId)/messages/\(messageId)/attachments/\(attachmentId)"
        )
        guard let url = URL(string: meta.downloadURL) else {
            throw AgentMailError.invalidResponse
        }
        let (data, response) = try await URLSession.shared.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw AgentMailError.httpStatus((response as? HTTPURLResponse)?.statusCode ?? -1)
        }
        let name = meta.filename ?? "attachment.pdf"
        return (data, name)
    }

    // MARK: - HTTP

    private func get<T: Decodable>(path: String) async throws -> T {
        guard let url = URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw AgentMailError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return try await decode(request)
    }

    private func post<T: Decodable>(path: String, json: [String: String]) async throws -> T {
        guard let url = URL(string: baseURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path) else {
            throw AgentMailError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try JSONSerialization.data(withJSONObject: json)
        return try await decode(request)
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw AgentMailError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else {
            let body = String(data: data, encoding: .utf8) ?? ""
            throw AgentMailError.apiError(http.statusCode, body)
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw AgentMailError.decodeFailed(error.localizedDescription)
        }
    }

    public enum AgentMailError: Error, LocalizedError {
        case invalidResponse
        case httpStatus(Int)
        case apiError(Int, String)
        case decodeFailed(String)
        case notConfigured

        public var errorDescription: String? {
            switch self {
            case .invalidResponse: return "Invalid AgentMail response."
            case .httpStatus(let c): return "AgentMail HTTP \(c)."
            case .apiError(let c, let b): return "AgentMail \(c): \(b.prefix(200))"
            case .decodeFailed(let m): return "AgentMail decode: \(m)"
            case .notConfigured: return "AgentMail is not configured. Add an API key in Settings."
            }
        }
    }
}

/// Stores AgentMail credentials + processed message IDs.
public enum MailboxSettings {
    private static let apiKeyAccount = "agentmail.apiKey"
    private static let inboxIdKey = "agentmail.inboxId"
    private static let inboxEmailKey = "agentmail.inboxEmail"

    public static var apiKey: String? {
        get { Keychain.get(account: apiKeyAccount) }
        set {
            if let newValue, !newValue.isEmpty {
                Keychain.set(newValue, account: apiKeyAccount)
            } else {
                Keychain.delete(account: apiKeyAccount)
            }
        }
    }

    public static var inboxId: String? {
        get { UserDefaults.standard.string(forKey: inboxIdKey) }
        set { UserDefaults.standard.set(newValue, forKey: inboxIdKey) }
    }

    public static var inboxEmail: String? {
        get { UserDefaults.standard.string(forKey: inboxEmailKey) }
        set { UserDefaults.standard.set(newValue, forKey: inboxEmailKey) }
    }

    public static var isConfigured: Bool {
        !(apiKey ?? "").isEmpty && !(inboxId ?? "").isEmpty
    }
}

enum Keychain {
    private static let service = "be.vermeir.secretary"

    static func set(_ value: String, account: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    static func get(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
    }
}

/// Result of an ingest operation with success/skip/error counts.
public struct MailIngestResult: Sendable {
    public var imported: Int = 0
    public var skippedDuplicate: Int = 0
    public var skippedUnsupported: Int = 0
    public var errors: [String] = []
    
    public var total: Int { imported + skippedDuplicate + skippedUnsupported + errors.count }
    public var hasErrors: Bool { !errors.isEmpty }
    
    public var summary: String {
        var parts: [String] = []
        if imported > 0 { parts.append("\(imported) imported") }
        if skippedDuplicate > 0 { parts.append("\(skippedDuplicate) skipped (duplicate)") }
        if skippedUnsupported > 0 { parts.append("\(skippedUnsupported) skipped (unsupported type)") }
        if !errors.isEmpty { parts.append("\(errors.count) error(s)") }
        return parts.isEmpty ? "Nothing to import" : parts.joined(separator: ", ")
    }
}

/// Imports email attachments into the library Inbox.
public struct MailIngestService: Sendable {
    public init() {}
    
    private static let supportedExtensions: Set<String> = [
        "pdf",
        "jpg", "jpeg", "png", "heic", "heif", "tiff", "tif", "gif", "webp",
        "doc", "docx", "xls", "xlsx", "ppt", "pptx",
        "odt", "ods", "odp",
        "rtf", "txt", "csv",
        "pages", "numbers", "keynote"
    ]
    
    private static let junkFilenamePatterns: [String] = [
        "signature", "logo", "banner", "footer", "header", "spacer", "pixel",
        "tracking", "unsubscribe", "email-icon", "social-icon"
    ]
    
    private static func isJunkAttachment(_ meta: AgentMailClient.AttachmentMeta) -> Bool {
        let filename = (meta.filename ?? "").lowercased()
        let contentType = (meta.contentType ?? "").lowercased()
        
        if filename.isEmpty && contentType.hasPrefix("image/") {
            return true
        }
        
        for pattern in junkFilenamePatterns {
            if filename.contains(pattern) { return true }
        }
        
        if filename.hasPrefix("image0") && contentType.hasPrefix("image/") {
            return true
        }
        
        return false
    }
    
    private static func isSupportedAttachment(_ meta: AgentMailClient.AttachmentMeta) -> Bool {
        let filename = meta.filename ?? ""
        let ext = (filename as NSString).pathExtension.lowercased()
        
        if supportedExtensions.contains(ext) {
            return true
        }
        
        let contentType = (meta.contentType ?? "").lowercased()
        if contentType == "application/pdf" { return true }
        if contentType.hasPrefix("image/") && !contentType.contains("svg") { return true }
        if contentType.contains("word") || contentType.contains("excel") ||
           contentType.contains("powerpoint") || contentType.contains("spreadsheet") ||
           contentType.contains("presentation") || contentType.contains("document") {
            return true
        }
        
        return false
    }

    public func ingestNewAttachments(into library: DocumentLibrary) async throws -> MailIngestResult {
        guard let apiKey = MailboxSettings.apiKey, let inboxId = MailboxSettings.inboxId else {
            throw AgentMailClient.AgentMailError.notConfigured
        }
        let client = AgentMailClient(apiKey: apiKey)
        let processed = ProcessedMailStore(libraryRoot: library.rootURL)
        let contentHashes = ContentHashStore(libraryRoot: library.rootURL)
        let messages = try await client.listMessages(inboxId: inboxId)
        var result = MailIngestResult()
        
        for message in messages {
            guard !processed.contains(message.messageId) else { continue }
            
            let attachments = (message.attachments ?? []).filter { meta in
                let disposition = (meta.contentDisposition ?? "attachment").lowercased()
                if disposition == "inline" {
                    if Self.isJunkAttachment(meta) { return false }
                    return !(meta.filename ?? "").isEmpty
                }
                return true
            }
            
            if attachments.isEmpty {
                processed.mark(message.messageId)
                continue
            }
            
            for attachment in attachments {
                do {
                    if Self.isJunkAttachment(attachment) {
                        result.skippedUnsupported += 1
                        continue
                    }
                    
                    if !Self.isSupportedAttachment(attachment) {
                        result.skippedUnsupported += 1
                        continue
                    }
                    
                    let (data, filename) = try await client.downloadAttachment(
                        inboxId: inboxId,
                        messageId: message.messageId,
                        attachmentId: attachment.attachmentId
                    )
                    
                    let dataHash = ContentHasher.sha256(of: data)
                    if contentHashes.contains(dataHash) {
                        result.skippedDuplicate += 1
                        continue
                    }
                    
                    let ext = Self.normalizeExtension(
                        filename: filename,
                        fallbackFilename: attachment.filename,
                        contentType: attachment.contentType
                    )
                    let hint = (filename as NSString).deletingPathExtension
                    let subjectHint = message.subject.map { FolderSchema.sanitize($0) } ?? hint
                    _ = try library.importData(
                        data,
                        filenameHint: subjectHint.isEmpty ? hint : "\(subjectHint)-\(hint)",
                        pathExtension: ext
                    )
                    
                    contentHashes.mark(dataHash)
                    result.imported += 1
                } catch {
                    result.errors.append("\(attachment.filename ?? "attachment"): \(error.localizedDescription)")
                }
            }
            processed.mark(message.messageId)
        }
        return result
    }
    
    private static func normalizeExtension(filename: String, fallbackFilename: String?, contentType: String?) -> String {
        var ext = (filename as NSString).pathExtension.lowercased()
        if ext.isEmpty, let fallback = fallbackFilename {
            ext = (fallback as NSString).pathExtension.lowercased()
        }
        if ext.isEmpty, let ct = contentType?.lowercased() {
            if ct.contains("pdf") { ext = "pdf" }
            else if ct.contains("jpeg") || ct.contains("jpg") { ext = "jpg" }
            else if ct.contains("png") { ext = "png" }
            else if ct.contains("heic") { ext = "heic" }
            else if ct.contains("tiff") { ext = "tiff" }
            else if ct.contains("gif") { ext = "gif" }
            else if ct.contains("webp") { ext = "webp" }
            else if ct.contains("word") { ext = "docx" }
            else if ct.contains("excel") || ct.contains("spreadsheet") { ext = "xlsx" }
            else if ct.contains("powerpoint") || ct.contains("presentation") { ext = "pptx" }
        }
        return ext.isEmpty ? "pdf" : ext
    }
}

final class ProcessedMailStore: @unchecked Sendable {
    private let url: URL
    private var ids: Set<String>
    private let lock = NSLock()

    init(libraryRoot: URL) {
        url = libraryRoot
            .appendingPathComponent(FolderSchema.metaFolder)
            .appendingPathComponent("mail_processed.json")
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            ids = Set(list)
        } else {
            ids = []
        }
    }

    func contains(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ids.contains(id)
    }

    func mark(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        ids.insert(id)
        persist()
    }
    
    private func persist() {
        let list = Array(ids).sorted()
        if let data = try? JSONEncoder().encode(list) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

final class ContentHashStore: @unchecked Sendable {
    private let url: URL
    private var hashes: Set<String>
    private let lock = NSLock()

    init(libraryRoot: URL) {
        url = libraryRoot
            .appendingPathComponent(FolderSchema.metaFolder)
            .appendingPathComponent("mail_content_hashes.json")
        if let data = try? Data(contentsOf: url),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            hashes = Set(list)
        } else {
            hashes = []
        }
    }

    func contains(_ hash: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hashes.contains(hash)
    }

    func mark(_ hash: String) {
        lock.lock()
        defer { lock.unlock() }
        hashes.insert(hash)
        persist()
    }
    
    private func persist() {
        let list = Array(hashes).sorted()
        if let data = try? JSONEncoder().encode(list) {
            try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: url, options: .atomic)
        }
    }
}

import SecretaryCore
import SwiftUI
#if os(macOS)
import AppKit
#endif

struct SettingsView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var newCategorySpace: DocumentSpace = .personal
    @State private var newCategoryName = ""
    @State private var apiKey = MailboxSettings.apiKey ?? ""
    @State private var mailboxUsername = "secretary"
    @State private var availableInboxes: [AgentMailClient.InboxInfo] = []
    @State private var selectedInboxId: String = MailboxSettings.inboxId ?? ""
    @State private var isLoadingInboxes = false
    @State private var mailboxError: String?
    @State private var mailboxSuccess: String?
    @State private var isFetchingMail = false

    var body: some View {
        TabView {
            libraryTab
                .tabItem { Label("Library", systemImage: "folder") }
            intakeTab
                .tabItem { Label("Intake", systemImage: "tray.and.arrow.down") }
            mailboxTab
                .tabItem { Label("Mailbox", systemImage: "envelope") }
        }
        #if os(macOS)
        .frame(width: 500, height: 440)
        #endif
        .tint(SecretaryTheme.accent)
    }

    private var libraryTab: some View {
        Form {
            Section {
                LabeledContent("Path") {
                    Text(store.rootPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: 260, alignment: .trailing)
                }
                LabeledContent("Source") {
                    Text(store.usingCustomRoot ? "Custom folder" : (store.usingiCloud ? "iCloud Drive" : "Local"))
                }
                #if os(macOS)
                Button("Choose library folder…") {
                    store.chooseLibraryRoot()
                }
                if store.usingCustomRoot {
                    Button("Reset to default location") {
                        store.resetLibraryRootToDefault()
                    }
                }
                #endif
            } header: {
                Text("Location")
            }

            Section("Index") {
                Button("Index pending documents") {
                    Task { await store.indexPendingDocuments() }
                }
                Button("Rebuild index (OCR + search)") {
                    store.rebuildIndex()
                }
            }

            Section("Category") {
                Picker("Space", selection: $newCategorySpace) {
                    ForEach(DocumentSpace.allCases) { Text($0.displayName).tag($0) }
                }
                TextField("New category name", text: $newCategoryName)
                Button("Create folder") {
                    let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    store.addCategory(space: newCategorySpace, name: name)
                    newCategoryName = ""
                }
            }

            Section {
                LabeledContent("Version", value: SecretaryCoreInfo.version)
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var intakeTab: some View {
        Form {
            Section {
                Text("Put PDFs or photos in the Drop folder. Secretary moves them into Inbox when the app opens or when you scan.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                #if os(macOS)
                Button("Open Drop folder in Finder") {
                    store.revealDropFolder()
                }
                #endif
                Button("Scan Drop folder now") {
                    Task { await store.scanDropFolder() }
                }
            } header: {
                Text("Drop folder")
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }

    private var mailboxTab: some View {
        Form {
            Section {
                Text("Send documents to a dedicated AgentMail address. Attachments (PDFs, images, Office docs) import into Inbox.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            
            Section("API Key") {
                SecureField("AgentMail API key", text: $apiKey)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                
                if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Label("Get an API key at agentmail.to", systemImage: "key")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    HStack {
                        Button("Save API key") {
                            saveAPIKey()
                        }
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        if MailboxSettings.apiKey != nil {
                            Button("Clear", role: .destructive) {
                                clearAPIKey()
                            }
                        }
                    }
                }
            }
            
            Section("Inbox") {
                if MailboxSettings.apiKey == nil {
                    Text("Add an API key first")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else if isLoadingInboxes {
                    HStack {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading inboxes…")
                            .foregroundStyle(.secondary)
                    }
                } else if availableInboxes.isEmpty {
                    TextField("New inbox username", text: $mailboxUsername)
                        .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    Button("Create inbox") {
                        Task { await createInbox() }
                    }
                    .disabled(mailboxUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    
                    Button("Refresh inbox list") {
                        Task { await loadInboxes() }
                    }
                } else {
                    Picker("Select inbox", selection: $selectedInboxId) {
                        Text("None").tag("")
                        ForEach(availableInboxes, id: \.inboxId) { inbox in
                            Text(inbox.email ?? inbox.inboxId)
                                .tag(inbox.inboxId)
                        }
                    }
                    .onChange(of: selectedInboxId) { _, newValue in
                        selectInbox(newValue)
                    }
                    
                    if let email = MailboxSettings.inboxEmail, !email.isEmpty {
                        LabeledContent("Current address") {
                            Text(email)
                                .textSelection(.enabled)
                                .font(.caption.monospaced())
                        }
                    }
                    
                    HStack {
                        TextField("Or create new", text: $mailboxUsername)
                            .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                        Button("Create") {
                            Task { await createInbox() }
                        }
                        .disabled(mailboxUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    Button("Refresh list") {
                        Task { await loadInboxes() }
                    }
                }
            }
            
            Section("Fetch Attachments") {
                if !MailboxSettings.isConfigured {
                    Text("Configure API key and inbox first")
                        .foregroundStyle(.secondary)
                        .font(.callout)
                } else {
                    HStack {
                        Button {
                            Task { await fetchMailAttachments() }
                        } label: {
                            if isFetchingMail {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Label("Fetch mail attachments", systemImage: "arrow.down.doc")
                            }
                        }
                        .disabled(isFetchingMail)
                    }
                    
                    if let result = store.lastMailIngestResult {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Label("\(result.imported)", systemImage: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                                Text("imported")
                                    .foregroundStyle(.secondary)
                            }
                            if result.skippedDuplicate > 0 {
                                HStack {
                                    Label("\(result.skippedDuplicate)", systemImage: "doc.on.doc")
                                        .foregroundStyle(.orange)
                                    Text("skipped (duplicate)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if result.skippedUnsupported > 0 {
                                HStack {
                                    Label("\(result.skippedUnsupported)", systemImage: "xmark.circle")
                                        .foregroundStyle(.gray)
                                    Text("skipped (unsupported)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if !result.errors.isEmpty {
                                HStack {
                                    Label("\(result.errors.count)", systemImage: "exclamationmark.triangle.fill")
                                        .foregroundStyle(.red)
                                    Text("error(s)")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .font(.caption)
                    }
                }
            }
            
            if let error = mailboxError {
                Section {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            
            if let success = mailboxSuccess {
                Section {
                    Label(success, systemImage: "checkmark.circle")
                        .foregroundStyle(.green)
                        .font(.callout)
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
        .onAppear {
            if MailboxSettings.apiKey != nil && availableInboxes.isEmpty {
                Task { await loadInboxes() }
            }
        }
    }
    
    private func saveAPIKey() {
        let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        MailboxSettings.apiKey = trimmed
        mailboxError = nil
        mailboxSuccess = "API key saved securely"
        Task { await loadInboxes() }
    }
    
    private func clearAPIKey() {
        MailboxSettings.apiKey = nil
        MailboxSettings.inboxId = nil
        MailboxSettings.inboxEmail = nil
        apiKey = ""
        availableInboxes = []
        selectedInboxId = ""
        mailboxError = nil
        mailboxSuccess = "API key cleared"
    }
    
    private func loadInboxes() async {
        guard let key = MailboxSettings.apiKey else { return }
        isLoadingInboxes = true
        mailboxError = nil
        defer { isLoadingInboxes = false }
        
        do {
            let client = AgentMailClient(apiKey: key)
            availableInboxes = try await client.listInboxes()
            if let currentId = MailboxSettings.inboxId,
               availableInboxes.contains(where: { $0.inboxId == currentId }) {
                selectedInboxId = currentId
            } else if let first = availableInboxes.first {
                selectInbox(first.inboxId)
            }
        } catch {
            mailboxError = error.localizedDescription
        }
    }
    
    private func selectInbox(_ inboxId: String) {
        guard !inboxId.isEmpty else {
            MailboxSettings.inboxId = nil
            MailboxSettings.inboxEmail = nil
            return
        }
        if let inbox = availableInboxes.first(where: { $0.inboxId == inboxId }) {
            MailboxSettings.inboxId = inbox.inboxId
            MailboxSettings.inboxEmail = inbox.email
            mailboxSuccess = "Inbox selected: \(inbox.email ?? inbox.inboxId)"
        }
    }
    
    private func createInbox() async {
        guard let key = MailboxSettings.apiKey else { return }
        let username = mailboxUsername.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !username.isEmpty else { return }
        
        isLoadingInboxes = true
        mailboxError = nil
        defer { isLoadingInboxes = false }
        
        do {
            let client = AgentMailClient(apiKey: key)
            let inbox = try await client.createInbox(username: username, clientId: "secretary-v1")
            MailboxSettings.inboxId = inbox.inboxId
            MailboxSettings.inboxEmail = inbox.email
            mailboxSuccess = "Created inbox: \(inbox.email ?? inbox.inboxId)"
            await loadInboxes()
            selectedInboxId = inbox.inboxId
        } catch {
            mailboxError = error.localizedDescription
        }
    }
    
    private func fetchMailAttachments() async {
        isFetchingMail = true
        mailboxError = nil
        mailboxSuccess = nil
        defer { isFetchingMail = false }
        
        await store.checkMailbox()
        
        if let result = store.lastMailIngestResult {
            if result.hasErrors {
                mailboxError = result.errors.first
            } else if result.imported > 0 {
                mailboxSuccess = result.summary
            }
        }
    }
}

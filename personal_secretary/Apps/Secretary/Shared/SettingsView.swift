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
        .frame(width: 520, height: 480)
        #endif
        .tint(SecretaryTheme.accent)
    }

    private var libraryTab: some View {
        Form {
            Section {
                LabeledContent("Path") {
                    Text(store.rootPath)
                        .font(SecretaryTheme.Typography.metadata)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                        .frame(maxWidth: 280, alignment: .trailing)
                }
                LabeledContent("Source") {
                    Text(store.usingCustomRoot ? "Custom folder" : (store.usingiCloud ? "iCloud Drive" : "Local"))
                        .font(SecretaryTheme.Typography.caption)
                        .foregroundStyle(SecretaryTheme.textSecondary)
                }
                #if os(macOS)
                Button {
                    store.chooseLibraryRoot()
                } label: {
                    Text("Choose library folder…")
                        .font(SecretaryTheme.Typography.caption)
                }
                .buttonStyle(.bordered)
                
                if store.usingCustomRoot {
                    Button {
                        store.resetLibraryRootToDefault()
                    } label: {
                        Text("Reset to default")
                            .font(SecretaryTheme.Typography.caption)
                    }
                    .buttonStyle(.bordered)
                }
                #endif
            } header: {
                Text("Location")
            }

            Section {
                Button {
                    Task { await store.indexPendingDocuments() }
                } label: {
                    Label("Index pending documents", systemImage: "arrow.triangle.2.circlepath")
                        .font(SecretaryTheme.Typography.caption)
                }
                .buttonStyle(.bordered)
                
                Button {
                    store.rebuildIndex()
                } label: {
                    Label("Rebuild full index", systemImage: "arrow.clockwise")
                        .font(SecretaryTheme.Typography.caption)
                }
                .buttonStyle(.bordered)
            } header: {
                Text("Index")
            } footer: {
                Text("Rebuilding re-runs OCR and recreates the search index.")
                    .font(SecretaryTheme.Typography.metadata)
                    .foregroundStyle(SecretaryTheme.textTertiary)
            }

            Section {
                Picker("Space", selection: $newCategorySpace) {
                    ForEach(DocumentSpace.allCases) { Text($0.displayName).tag($0) }
                }
                .font(SecretaryTheme.Typography.caption)
                
                TextField("New category name", text: $newCategoryName)
                    .font(SecretaryTheme.Typography.bodySecondary)
                
                Button {
                    let name = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !name.isEmpty else { return }
                    store.addCategory(space: newCategorySpace, name: name)
                    newCategoryName = ""
                } label: {
                    Label("Create folder", systemImage: "folder.badge.plus")
                        .font(SecretaryTheme.Typography.caption)
                }
                .buttonStyle(.bordered)
                .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } header: {
                Text("Categories")
            }

            Section {
                HStack {
                    Text("Version")
                        .foregroundStyle(SecretaryTheme.textSecondary)
                    Spacer()
                    Text(SecretaryCoreInfo.version)
                        .font(SecretaryTheme.Typography.metadataMono)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                }
                .font(SecretaryTheme.Typography.caption)
            }
        }
        .formStyle(.grouped)
        .padding(SecretaryTheme.spacingSM)
    }

    private var intakeTab: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: SecretaryTheme.spacingSM) {
                    Text("Put PDFs or photos in the Drop folder. Secretary moves them into Inbox when the app opens or when you scan.")
                        .font(SecretaryTheme.Typography.caption)
                        .foregroundStyle(SecretaryTheme.textSecondary)
                    
                    HStack(spacing: SecretaryTheme.spacingSM) {
                        #if os(macOS)
                        Button {
                            store.revealDropFolder()
                        } label: {
                            Label("Open in Finder", systemImage: "folder")
                                .font(SecretaryTheme.Typography.caption)
                        }
                        .buttonStyle(.bordered)
                        #endif
                        
                        Button {
                            Task { await store.scanDropFolder() }
                        } label: {
                            Label("Scan now", systemImage: "arrow.down.doc")
                                .font(SecretaryTheme.Typography.caption)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SecretaryTheme.accent)
                    }
                }
            } header: {
                Text("Drop folder")
            }
        }
        .formStyle(.grouped)
        .padding(SecretaryTheme.spacingSM)
    }

    private var mailboxTab: some View {
        Form {
            Section {
                Text("Send documents to a dedicated AgentMail address. Attachments (PDFs, images, Office docs) import into Inbox.")
                    .font(SecretaryTheme.Typography.caption)
                    .foregroundStyle(SecretaryTheme.textSecondary)
            }
            
            Section {
                SecureField("AgentMail API key", text: $apiKey)
                    .font(SecretaryTheme.Typography.bodySecondary)
                    .textContentType(.password)
                    .autocorrectionDisabled()
                #if os(iOS)
                    .textInputAutocapitalization(.never)
                #endif
                
                if apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    HStack(spacing: SecretaryTheme.spacingSM) {
                        Image(systemName: "key")
                            .foregroundStyle(SecretaryTheme.accent)
                        Text("Get an API key at agentmail.to")
                    }
                    .font(SecretaryTheme.Typography.caption)
                    .foregroundStyle(SecretaryTheme.textTertiary)
                } else {
                    HStack(spacing: SecretaryTheme.spacingSM) {
                        Button {
                            saveAPIKey()
                        } label: {
                            Label("Save key", systemImage: "checkmark")
                                .font(SecretaryTheme.Typography.captionMedium)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SecretaryTheme.accent)
                        .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        if MailboxSettings.apiKey != nil {
                            Button(role: .destructive) {
                                clearAPIKey()
                            } label: {
                                Label("Clear", systemImage: "xmark")
                                    .font(SecretaryTheme.Typography.captionMedium)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            } header: {
                Text("API Key")
            }
            
            Section {
                if MailboxSettings.apiKey == nil {
                    HStack(spacing: SecretaryTheme.spacingSM) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(SecretaryTheme.textTertiary)
                        Text("Add an API key first")
                    }
                    .font(SecretaryTheme.Typography.caption)
                    .foregroundStyle(SecretaryTheme.textTertiary)
                } else if isLoadingInboxes {
                    HStack(spacing: SecretaryTheme.spacingSM) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading inboxes…")
                            .font(SecretaryTheme.Typography.caption)
                            .foregroundStyle(SecretaryTheme.textTertiary)
                    }
                } else if availableInboxes.isEmpty {
                    TextField("New inbox username", text: $mailboxUsername)
                        .font(SecretaryTheme.Typography.bodySecondary)
                        .autocorrectionDisabled()
                    #if os(iOS)
                        .textInputAutocapitalization(.never)
                    #endif
                    
                    HStack(spacing: SecretaryTheme.spacingSM) {
                        Button {
                            Task { await createInbox() }
                        } label: {
                            Label("Create inbox", systemImage: "plus")
                                .font(SecretaryTheme.Typography.captionMedium)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(SecretaryTheme.accent)
                        .disabled(mailboxUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        
                        Button {
                            Task { await loadInboxes() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                                .font(SecretaryTheme.Typography.captionMedium)
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Picker("Select inbox", selection: $selectedInboxId) {
                        Text("None").tag("")
                        ForEach(availableInboxes, id: \.inboxId) { inbox in
                            Text(inbox.email ?? inbox.inboxId)
                                .tag(inbox.inboxId)
                        }
                    }
                    .font(SecretaryTheme.Typography.caption)
                    .onChange(of: selectedInboxId) { _, newValue in
                        selectInbox(newValue)
                    }
                    
                    if let email = MailboxSettings.inboxEmail, !email.isEmpty {
                        HStack {
                            Text("Active address")
                                .font(SecretaryTheme.Typography.caption)
                                .foregroundStyle(SecretaryTheme.textSecondary)
                            Spacer()
                            Text(email)
                                .textSelection(.enabled)
                                .font(SecretaryTheme.Typography.metadataMono)
                                .foregroundStyle(SecretaryTheme.accent)
                        }
                    }
                    
                    HStack(spacing: SecretaryTheme.spacingSM) {
                        TextField("Or create new", text: $mailboxUsername)
                            .font(SecretaryTheme.Typography.caption)
                            .autocorrectionDisabled()
                        #if os(iOS)
                            .textInputAutocapitalization(.never)
                        #endif
                        
                        Button {
                            Task { await createInbox() }
                        } label: {
                            Text("Create")
                                .font(SecretaryTheme.Typography.captionMedium)
                        }
                        .buttonStyle(.bordered)
                        .disabled(mailboxUsername.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    
                    Button {
                        Task { await loadInboxes() }
                    } label: {
                        Label("Refresh list", systemImage: "arrow.clockwise")
                            .font(SecretaryTheme.Typography.caption)
                    }
                    .buttonStyle(.bordered)
                }
            } header: {
                Text("Inbox")
            }
            
            Section {
                if !MailboxSettings.isConfigured {
                    HStack(spacing: SecretaryTheme.spacingSM) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(SecretaryTheme.textTertiary)
                        Text("Configure API key and inbox first")
                    }
                    .font(SecretaryTheme.Typography.caption)
                    .foregroundStyle(SecretaryTheme.textTertiary)
                } else {
                    Button {
                        Task { await fetchMailAttachments() }
                    } label: {
                        HStack(spacing: SecretaryTheme.spacingSM) {
                            if isFetchingMail {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.doc")
                            }
                            Text("Fetch mail attachments")
                        }
                        .font(SecretaryTheme.Typography.captionMedium)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SecretaryTheme.accent)
                    .disabled(isFetchingMail)
                    
                    if let result = store.lastMailIngestResult {
                        VStack(alignment: .leading, spacing: SecretaryTheme.spacingSM) {
                            resultRow(
                                count: result.imported,
                                icon: "checkmark.circle.fill",
                                label: "imported",
                                color: SecretaryTheme.success
                            )
                            
                            if result.skippedDuplicate > 0 {
                                resultRow(
                                    count: result.skippedDuplicate,
                                    icon: "doc.on.doc",
                                    label: "skipped (duplicate)",
                                    color: SecretaryTheme.warn
                                )
                            }
                            
                            if result.skippedUnsupported > 0 {
                                resultRow(
                                    count: result.skippedUnsupported,
                                    icon: "xmark.circle",
                                    label: "skipped (unsupported)",
                                    color: SecretaryTheme.textTertiary
                                )
                            }
                            
                            if !result.errors.isEmpty {
                                resultRow(
                                    count: result.errors.count,
                                    icon: "exclamationmark.triangle.fill",
                                    label: "error(s)",
                                    color: .red
                                )
                            }
                        }
                        .padding(.top, SecretaryTheme.spacingXS)
                    }
                }
            } header: {
                Text("Fetch Attachments")
            }
            
            if let error = mailboxError {
                Section {
                    StatusBanner(message: error, style: .error)
                }
            }
            
            if let success = mailboxSuccess {
                Section {
                    StatusBanner(message: success, style: .success)
                }
            }
        }
        .formStyle(.grouped)
        .padding(SecretaryTheme.spacingSM)
        .onAppear {
            if MailboxSettings.apiKey != nil && availableInboxes.isEmpty {
                Task { await loadInboxes() }
            }
        }
    }
    
    private func resultRow(count: Int, icon: String, label: String, color: Color) -> some View {
        HStack(spacing: SecretaryTheme.spacingSM) {
            Image(systemName: icon)
                .foregroundStyle(color)
            Text("\(count)")
                .font(SecretaryTheme.Typography.captionMedium)
                .foregroundStyle(SecretaryTheme.textPrimary)
            Text(label)
                .font(SecretaryTheme.Typography.caption)
                .foregroundStyle(SecretaryTheme.textTertiary)
        }
        .font(SecretaryTheme.Typography.caption)
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

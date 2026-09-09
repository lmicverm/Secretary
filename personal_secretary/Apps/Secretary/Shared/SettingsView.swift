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
        .frame(width: 460, height: 380)
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
                Text("Optional: send documents to a dedicated AgentMail address. Attachments import into Inbox when you check mail.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                SecureField("API key", text: $apiKey)
                TextField("Inbox username", text: $mailboxUsername)
                if let email = MailboxSettings.inboxEmail {
                    LabeledContent("Address", value: email)
                }
                Button("Save & link mailbox") {
                    Task { await store.setupMailbox(apiKey: apiKey, username: mailboxUsername) }
                }
                Button("Check mailbox now") {
                    Task { await store.checkMailbox() }
                }
            }
        }
        .formStyle(.grouped)
        .padding(8)
    }
}

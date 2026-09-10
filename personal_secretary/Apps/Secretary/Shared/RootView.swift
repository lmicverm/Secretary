import SecretaryCore
import SwiftUI

enum SidebarDestination: Hashable, Identifiable {
    case all
    case inbox
    case favorites
    case expiring
    case category(DocumentSpace, String)

    var id: Self { self }

    var filter: DocumentFilter {
        switch self {
        case .all: return DocumentFilter()
        case .inbox: return DocumentFilter(inboxOnly: true)
        case .favorites: return DocumentFilter(favoritesOnly: true)
        case .expiring: return DocumentFilter(expiringWithinDays: 60)
        case .category(let space, let name):
            return DocumentFilter(space: space, category: name)
        }
    }

    var title: String {
        switch self {
        case .all: return "All documents"
        case .inbox: return "Inbox"
        case .favorites: return "Favorites"
        case .expiring: return "Expiring"
        case .category(_, let name): return name
        }
    }
}

struct RootView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var selectedDestination: SidebarDestination? = .inbox
    @State private var selectedDocumentID: String?
    @State private var columnVisibility = NavigationSplitViewVisibility.all

    private var selectedDocument: DocumentRecord? {
        guard let selectedDocumentID else { return nil }
        return store.documents.first(where: { $0.id == selectedDocumentID })
            ?? store.document(id: selectedDocumentID)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(selection: $selectedDestination)
                .navigationSplitViewColumnWidth(
                    min: 200,
                    ideal: SecretaryTheme.sidebarWidth,
                    max: SecretaryTheme.sidebarWidthMax
                )
        } content: {
            DocumentListView(selectedDocumentID: $selectedDocumentID)
                .navigationSplitViewColumnWidth(
                    min: 260,
                    ideal: SecretaryTheme.listWidth,
                    max: SecretaryTheme.listWidthMax
                )
                .id(selectedDestination)
        } detail: {
            Group {
                if let selectedDocument {
                    DocumentDetailView(document: selectedDocument)
                        .id(selectedDocument.id)
                } else {
                    emptyDetail
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            applyDestination(selectedDestination ?? .inbox)
        }
        .onChange(of: selectedDestination) { _, destination in
            selectedDocumentID = nil
            applyDestination(destination)
            #if os(iOS)
            // Compact width: move from sidebar into the list column.
            if destination != nil {
                columnVisibility = .doubleColumn
            }
            #endif
        }
        .alert("Error", isPresented: Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
        .overlay(alignment: .bottom) {
            if let status = store.statusMessage {
                Text(status)
                    .font(SecretaryTheme.Typography.captionMedium)
                    .padding(.horizontal, SecretaryTheme.spacingLG)
                    .padding(.vertical, SecretaryTheme.spacingSM)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous))
                    .padding(.bottom, SecretaryTheme.spacingLG)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { store.statusMessage = nil }
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.statusMessage)
    }

    private func applyDestination(_ destination: SidebarDestination?) {
        let filter = destination?.filter ?? DocumentFilter(inboxOnly: true)
        store.applyFilter(filter)
    }

    private var emptyDetail: some View {
        EmptyStateView(
            icon: "doc.text.magnifyingglass",
            title: "Select a document",
            description: "Choose something from the list, or open Inbox to classify new files."
        )
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var selection: SidebarDestination?
    #if os(macOS)
    @Environment(\.openSettings) private var openSettings
    #endif

    var body: some View {
        List(selection: $selection) {
            Section {
                navRow("All documents", systemImage: "doc.text", destination: .all)
                inboxRow
                navRow("Favorites", systemImage: "star", destination: .favorites)
                expiringRow
            } header: {
                Text("Library")
                    .sectionHeaderStyle()
            }

            Section {
                ForEach(store.personalCategories, id: \.self) { name in
                    navRow(name, systemImage: "folder", destination: .category(.personal, name))
                }
            } header: {
                HStack(spacing: SecretaryTheme.spacingXS) {
                    Image(systemName: "person")
                        .font(.caption2)
                    Text("Personal")
                }
                .sectionHeaderStyle()
            }

            Section {
                ForEach(store.bvCategories, id: \.self) { name in
                    navRow(name, systemImage: "folder", destination: .category(.bv, name))
                }
            } header: {
                HStack(spacing: SecretaryTheme.spacingXS) {
                    Image(systemName: "building.2")
                        .font(.caption2)
                    Text("Business")
                }
                .sectionHeaderStyle()
            }

            Section {
                #if os(iOS)
                ScanDocumentsButton()
                #endif
                #if os(macOS)
                Button {
                    store.revealDropFolder()
                } label: {
                    Label("Open Drop folder", systemImage: "folder")
                }
                .buttonStyle(.plain)
                .foregroundStyle(SecretaryTheme.textSecondary)
                #endif
                Button {
                    Task { await store.scanDropFolder() }
                } label: {
                    Label("Scan Drop folder", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.plain)
                .foregroundStyle(SecretaryTheme.textSecondary)
                mailboxIntakeRow
            } header: {
                Text("Intake")
                    .sectionHeaderStyle()
            }

            Section {
                #if os(iOS)
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                #endif
                HStack {
                    Label("Storage", systemImage: "externaldrive")
                    Spacer()
                    Text(store.usingCustomRoot ? "Custom" : (store.usingiCloud ? "iCloud" : "Local"))
                        .font(SecretaryTheme.Typography.caption)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                }
                .foregroundStyle(SecretaryTheme.textSecondary)
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Secretary")
        .tint(SecretaryTheme.accent)
    }

    private var inboxRow: some View {
        NavigationLink(value: SidebarDestination.inbox) {
            HStack {
                Label("Inbox", systemImage: "tray")
                Spacer()
                if store.inboxCount > 0 {
                    Text("\(store.inboxCount)")
                        .font(SecretaryTheme.Typography.captionMedium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(
                            Capsule()
                                .fill(SecretaryTheme.accent)
                        )
                }
            }
        }
        .tag(SidebarDestination.inbox)
    }
    
    private var expiringRow: some View {
        NavigationLink(value: SidebarDestination.expiring) {
            HStack {
                Label("Expiring", systemImage: "calendar.badge.clock")
                Spacer()
            }
        }
        .tag(SidebarDestination.expiring)
    }

    @ViewBuilder
    private var mailboxIntakeRow: some View {
        if store.mailboxConfigured {
            Button {
                Task { await store.checkMailbox() }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Label("Check mailbox", systemImage: "envelope")
                    if let email = store.mailboxEmail, !email.isEmpty {
                        Text(email)
                            .font(SecretaryTheme.Typography.metadata)
                            .foregroundStyle(SecretaryTheme.textTertiary)
                            .lineLimit(1)
                    }
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(SecretaryTheme.textSecondary)
        } else {
            #if os(iOS)
            NavigationLink {
                SettingsView(initialTab: .mailbox)
            } label: {
                Label("Set up mailbox…", systemImage: "envelope.badge")
            }
            .foregroundStyle(SecretaryTheme.textSecondary)
            #else
            Button {
                store.openMailboxSettings()
                openSettings()
            } label: {
                Label("Set up mailbox…", systemImage: "envelope.badge")
            }
            .buttonStyle(.plain)
            .foregroundStyle(SecretaryTheme.textSecondary)
            #endif
        }
    }

    private func navRow(_ title: String, systemImage: String, destination: SidebarDestination) -> some View {
        NavigationLink(value: destination) {
            Label(title, systemImage: systemImage)
        }
        .tag(destination)
    }
}

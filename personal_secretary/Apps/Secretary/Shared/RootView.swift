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
                    max: 260
                )
        } content: {
            DocumentListView(selectedDocumentID: $selectedDocumentID)
                .navigationSplitViewColumnWidth(
                    min: 260,
                    ideal: SecretaryTheme.listWidth,
                    max: 400
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
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .padding(.bottom, 16)
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
        VStack(spacing: 12) {
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text("Select a document")
                .font(.title3.weight(.semibold))
            Text("Choose something from the list, or open Inbox to classify new files.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SidebarView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var selection: SidebarDestination?

    var body: some View {
        List(selection: $selection) {
            Section("Quick") {
                navRow("All documents", systemImage: "tray.full", destination: .all)
                navRow("Inbox (\(store.inboxCount))", systemImage: "tray", destination: .inbox)
                navRow("Favorites", systemImage: "star.fill", destination: .favorites)
                navRow("Expiring", systemImage: "calendar.badge.exclamationmark", destination: .expiring)
            }

            Section("Personal") {
                ForEach(store.personalCategories, id: \.self) { name in
                    navRow(name, systemImage: "person", destination: .category(.personal, name))
                }
            }

            Section("BV") {
                ForEach(store.bvCategories, id: \.self) { name in
                    navRow(name, systemImage: "building.2", destination: .category(.bv, name))
                }
            }

            Section("Intake") {
                #if os(iOS)
                ScanDocumentsButton()
                #endif
                #if os(macOS)
                Button {
                    store.revealDropFolder()
                } label: {
                    Label("Open Drop folder", systemImage: "folder")
                }
                #endif
                Button {
                    Task { await store.scanDropFolder() }
                } label: {
                    Label("Scan Drop", systemImage: "arrow.down.doc")
                }
                Button {
                    Task { await store.checkMailbox() }
                } label: {
                    Label("Check mailbox", systemImage: "envelope")
                }
            }

            Section {
                #if os(iOS)
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                #endif
                LabeledContent("Storage") {
                    Text(store.usingCustomRoot ? "Custom" : (store.usingiCloud ? "iCloud" : "Local"))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Secretary")
        .tint(SecretaryTheme.accent)
    }

    private func navRow(_ title: String, systemImage: String, destination: SidebarDestination) -> some View {
        NavigationLink(value: destination) {
            Label(title, systemImage: systemImage)
        }
        .tag(destination)
    }
}

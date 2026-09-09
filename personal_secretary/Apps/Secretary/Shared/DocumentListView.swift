import SecretaryCore
import SwiftUI
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#endif

struct DocumentListView: View {
    @EnvironmentObject private var store: LibraryStore
    @Binding var selectedDocumentID: String?
    @State private var query = ""
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search anything…", text: $query)
                    .textFieldStyle(.plain)
                    .onChange(of: query) { _, newValue in
                        searchTask?.cancel()
                        searchTask = Task {
                            try? await Task.sleep(nanoseconds: 220_000_000)
                            guard !Task.isCancelled else { return }
                            await MainActor.run { applyQuery(newValue) }
                        }
                    }
                    .onSubmit { applyQuery(query) }
                if !query.isEmpty {
                    Button {
                        query = ""
                        applyQuery("")
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(.bar)

            List(selection: $selectedDocumentID) {
                if store.documents.isEmpty {
                    ContentUnavailableView {
                        Label(emptyTitle, systemImage: emptyIcon)
                    } description: {
                        Text(emptyDescription)
                    } actions: {
                        #if os(iOS)
                        ImportToolbarButtons()
                            .buttonStyle(.borderedProminent)
                        #endif
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else {
                    ForEach(store.documents) { doc in
                        DocumentRow(document: doc)
                            .tag(doc.id)
                            .contextMenu {
                                Button(doc.isInbox ? "Classify…" : "Reclassify…") {
                                    selectedDocumentID = doc.id
                                }
                                Button(doc.isFavorite ? "Remove Favorite" : "Favorite") {
                                    store.toggleFavorite(doc)
                                }
                                Button("Remove from app", role: .destructive) {
                                    store.removeFromLibrary(doc)
                                    if selectedDocumentID == doc.id {
                                        selectedDocumentID = nil
                                    }
                                }
                                #if os(macOS)
                                if let url = store.fileURL(for: doc) {
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([url])
                                    }
                                }
                                #endif
                            }
                    }
                }
            }
            #if os(macOS)
            .onDrop(of: SecretaryUTTypes.importTypes.map(\.identifier), isTargeted: nil) { providers in
                handleDrop(providers)
                return true
            }
            #endif
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItemGroup {
                if store.isBusy {
                    ProgressView()
                        .controlSize(.small)
                }
                #if os(iOS)
                ImportToolbarButtons()
                #else
                MacImportButton()
                #endif
            }
        }
    }

    private var emptyTitle: String {
        if store.filter.inboxOnly { return "Inbox is empty" }
        return "No documents"
    }

    private var emptyIcon: String {
        store.filter.inboxOnly ? "tray" : "doc.text"
    }

    private var emptyDescription: String {
        #if os(iOS)
        return "Tap Add to scan a page, pick photos, or import PDFs from Files."
        #else
        return "Import files, or drop them into the Drop folder."
        #endif
    }

    private var title: String {
        if store.filter.inboxOnly { return "Inbox" }
        if store.filter.favoritesOnly { return "Favorites" }
        if let space = store.filter.space, let cat = store.filter.category {
            return "\(space.rawValue) / \(cat)"
        }
        if store.filter.expiringWithinDays != nil { return "Expiring" }
        return "Documents"
    }

    private func applyQuery(_ text: String? = nil) {
        let q = text ?? query
        // Searching should look across the whole library, not only the current sidebar folder.
        if q.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var f = store.filter
            f.query = ""
            store.applyFilter(f)
        } else {
            store.applyFilter(DocumentFilter(query: q))
        }
    }

    #if os(macOS)
    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        for provider in providers {
            provider.loadFileRepresentation(forTypeIdentifier: UTType.data.identifier) { url, _ in
                guard let url else { return }
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.copyItem(at: url, to: temp)
                DispatchQueue.main.async {
                    store.importURLs([temp])
                }
            }
        }
        return true
    }
    #endif
}

struct DocumentRow: View {
    let document: DocumentRecord

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: iconName)
                .font(.body.weight(.medium))
                .foregroundStyle(SecretaryTheme.accent)
                .frame(width: 22, alignment: .center)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(document.displayTitle)
                        .font(.body.weight(.medium))
                        .lineLimit(1)
                    if document.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.caption2)
                            .foregroundStyle(.yellow)
                    }
                }
                Text(pathLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)
            if let expiry = document.expiryDate {
                Text(expiry, style: .date)
                    .font(.caption2)
                    .foregroundStyle(expiry < Date() ? .red : SecretaryTheme.warn)
            }
        }
        .padding(.vertical, 2)
    }

    private var pathLabel: String {
        if document.isInbox { return "Inbox" }
        if let space = document.space, let category = document.category {
            if let year = document.year {
                return "\(space.rawValue) · \(category) · \(year)"
            }
            return "\(space.rawValue) · \(category)"
        }
        return document.relativePath
    }

    private var iconName: String {
        if document.isInbox { return "tray" }
        switch document.space {
        case .bv: return "building.2"
        case .personal: return "person"
        case .none: return "doc"
        }
    }
}

#if os(macOS)
struct MacImportButton: View {
    @EnvironmentObject private var store: LibraryStore

    var body: some View {
        Menu {
            Button("Import Files…") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = true
                panel.canChooseDirectories = false
                panel.allowedContentTypes = SecretaryUTTypes.importTypes
                if panel.runModal() == .OK {
                    store.importURLs(panel.urls)
                }
            }
            Button("Import Folder into Inbox…") {
                let panel = NSOpenPanel()
                panel.allowsMultipleSelection = false
                panel.canChooseDirectories = true
                panel.canChooseFiles = false
                if panel.runModal() == .OK, let folder = panel.url {
                    store.importFolder(folder)
                }
            }
        } label: {
            Label("Import", systemImage: "plus")
        }
    }
}
#endif

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
            HStack(spacing: SecretaryTheme.spacingSM) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(SecretaryTheme.textTertiary)
                TextField("Search anything…", text: $query)
                    .textFieldStyle(.plain)
                    .font(SecretaryTheme.Typography.bodySecondary)
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
            .padding(.horizontal, SecretaryTheme.spacingMD)
            .padding(.vertical, SecretaryTheme.spacingMD)
            .background(.bar)

            List(selection: $selectedDocumentID) {
                if store.documents.isEmpty {
                    VStack(spacing: SecretaryTheme.spacingLG) {
                        EmptyStateView(
                            icon: emptyIcon,
                            title: emptyTitle,
                            description: emptyDescription
                        )
                        #if os(iOS)
                        ImportToolbarButtons()
                            .buttonStyle(.borderedProminent)
                            .tint(SecretaryTheme.accent)
                        #endif
                    }
                    .frame(maxWidth: .infinity, minHeight: 280)
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
                } else if DocumentListGrouping.shouldGroup(filter: store.filter) {
                    ForEach(DocumentListGrouping.sections(from: store.documents)) { section in
                        Section(section.title) {
                            ForEach(section.documents) { doc in
                                documentRow(doc)
                            }
                        }
                    }
                } else {
                    ForEach(store.documents) { doc in
                        documentRow(doc)
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
        if store.filter.favoritesOnly { return "No favorites yet" }
        if store.filter.expiringWithinDays != nil { return "Nothing expiring soon" }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "No matches" }
        return "No documents"
    }

    private var emptyIcon: String {
        if store.filter.inboxOnly { return "tray" }
        if store.filter.favoritesOnly { return "star" }
        if store.filter.expiringWithinDays != nil { return "calendar.badge.clock" }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "magnifyingglass" }
        return "doc.text"
    }

    private var emptyDescription: String {
        if store.filter.favoritesOnly {
            return "Star a document to keep it here."
        }
        if store.filter.expiringWithinDays != nil {
            return "Documents with a renewal date in the next 60 days will appear here."
        }
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Try a different title, tag, or folder name."
        }
        #if os(iOS)
        return "Tap Add to scan a page, pick photos, or import PDFs from Files."
        #else
        return "Import files, or drop them into the Drop folder."
        #endif
    }

    @ViewBuilder
    private func documentRow(_ doc: DocumentRecord) -> some View {
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
                let accessing = url.startAccessingSecurityScopedResource()
                defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                let ext = url.pathExtension.isEmpty ? "pdf" : url.pathExtension
                let temp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(ext)
                do {
                    try FileManager.default.copyItem(at: url, to: temp)
                } catch {
                    NSLog("Secretary: drop copy failed for \(url.lastPathComponent): \(error.localizedDescription)")
                    return
                }
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
    
    private var isExpiringSoon: Bool {
        guard let expiry = document.expiryDate else { return false }
        return expiry <= Date().addingTimeInterval(30 * 24 * 60 * 60)
    }
    
    private var isExpired: Bool {
        guard let expiry = document.expiryDate else { return false }
        return expiry < Date()
    }

    var body: some View {
        HStack(alignment: .center, spacing: SecretaryTheme.spacingMD) {
            iconView
            
            VStack(alignment: .leading, spacing: SecretaryTheme.spacingXS) {
                HStack(spacing: SecretaryTheme.spacingSM) {
                    Text(document.displayTitle)
                        .font(SecretaryTheme.Typography.bodyMedium)
                        .foregroundStyle(SecretaryTheme.textPrimary)
                        .lineLimit(1)
                    
                    if document.isFavorite {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(Color.yellow.opacity(0.85))
                    }
                }
                
                HStack(spacing: SecretaryTheme.spacingSM) {
                    Text(pathLabel)
                        .font(SecretaryTheme.Typography.caption)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                        .lineLimit(1)
                    
                    if document.paymentStatus == .unpaid {
                        unpaidBadge
                    }
                    if let expiry = document.expiryDate {
                        expiryBadge(expiry)
                    }
                }
            }
            
            Spacer(minLength: SecretaryTheme.spacingXS)
        }
        .padding(.vertical, SecretaryTheme.spacingXS)
    }
    
    private var iconView: some View {
        Image(systemName: iconName)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(document.isInbox ? SecretaryTheme.warn : SecretaryTheme.accent.opacity(0.7))
            .frame(width: 24, height: 24)
            .background(
                RoundedRectangle(cornerRadius: SecretaryTheme.radiusSmall, style: .continuous)
                    .fill(document.isInbox ? SecretaryTheme.warnSoft : SecretaryTheme.accentMuted)
            )
    }
    
    private var unpaidBadge: some View {
        Text("Unpaid")
            .font(SecretaryTheme.Typography.metadata)
            .foregroundStyle(SecretaryTheme.warn)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(SecretaryTheme.warnSoft, in: Capsule())
    }

    @ViewBuilder
    private func expiryBadge(_ date: Date) -> some View {
        HStack(spacing: 3) {
            Image(systemName: isExpired ? "exclamationmark.circle.fill" : "calendar")
                .font(.system(size: 9))
            Text(date, style: .date)
                .font(SecretaryTheme.Typography.metadata)
        }
        .foregroundStyle(isExpired ? .red : (isExpiringSoon ? SecretaryTheme.warn : SecretaryTheme.textTertiary))
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
                presentOpenPanel(files: true)
            }
            Button("Import Folder into Inbox…") {
                presentOpenPanel(files: false)
            }
        } label: {
            Label("Import", systemImage: "plus")
        }
    }

    /// SwiftUI Menu is still tracking when this action runs. `NSOpenPanel.runModal()`
    /// in that state is a known AppKit abort (`__pthread_kill`). Wait a turn first.
    private func presentOpenPanel(files: Bool) {
        DispatchQueue.main.async {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = files
            panel.canChooseDirectories = !files
            panel.canChooseFiles = files
            if files {
                panel.allowedContentTypes = SecretaryUTTypes.importTypes
            }
            guard panel.runModal() == .OK else { return }
            if files {
                store.importURLs(panel.urls)
            } else if let folder = panel.url {
                store.importFolder(folder)
            }
        }
    }
}
#endif

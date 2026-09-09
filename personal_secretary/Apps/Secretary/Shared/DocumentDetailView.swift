import PDFKit
import SecretaryCore
import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

struct DocumentDetailView: View {
    @EnvironmentObject private var store: LibraryStore
    let document: DocumentRecord

    @State private var title: String = ""
    @State private var notes: String = ""
    @State private var tagsText: String = ""
    @State private var expiryEnabled = false
    @State private var expiryDate = Date()
    @State private var showClassify = false
    @State private var duplicates: [DocumentRecord] = []
    @State private var suggestions: [ClassificationSuggestion] = []
    @State private var showReclassifyPanel = false

    // Editable draft (filled from a suggestion or category tap)
    @State private var draftSpace: DocumentSpace = .personal
    @State private var draftCategory: String = DefaultTaxonomy.personalCategories[0]
    @State private var draftUseYear = false
    @State private var draftYear = Calendar.current.component(.year, from: Date())
    @State private var draftType = "document"
    @State private var draftTitle = ""
    @State private var selectedSuggestionID: String?
    @State private var confirmRemove = false

    private var liveDocument: DocumentRecord {
        store.documents.first(where: { $0.id == document.id }) ?? document
    }

    private var isClassifying: Bool {
        liveDocument.isInbox || showReclassifyPanel
    }

    private var draftCategories: [String] {
        var names = Set(
            draftSpace == .personal
                ? DefaultTaxonomy.personalCategories
                : DefaultTaxonomy.bvCategories
        )
        for name in store.categories(for: draftSpace) {
            names.insert(name)
        }
        for suggestion in suggestions where suggestion.space == draftSpace {
            names.insert(suggestion.category)
        }
        let trimmed = draftCategory.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            names.insert(ClassificationSuggester.sanitizeCategoryName(trimmed))
        }
        return names.sorted()
    }

    private var destinationPreview: String {
        if draftUseYear {
            return "\(draftSpace.rawValue) / \(draftCategory) / \(draftYear)"
        }
        return "\(draftSpace.rawValue) / \(draftCategory)"
    }

    var body: some View {
        DetailPage {
            VStack(alignment: .leading, spacing: SecretaryTheme.sectionSpacing) {
                header
                if isClassifying {
                    classifyPanel
                } else {
                    reclassifyPrompt
                }
                preview
                metadataForm
                if !duplicates.isEmpty {
                    duplicateBanner
                }
                actions
            }
        }
        .navigationTitle(liveDocument.displayTitle)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .tint(SecretaryTheme.accent)
        .onAppear { refreshAll() }
        .onChange(of: document.id) { _, _ in
            showReclassifyPanel = false
            selectedSuggestionID = nil
            refreshAll()
        }
        .onChange(of: liveDocument.ocrText) { _, _ in
            reloadSuggestions()
            if isClassifying, selectedSuggestionID == nil {
                seedDraftFromDocument()
            }
        }
        .sheet(isPresented: $showClassify) {
            ClassifySheet(document: liveDocument)
                .environmentObject(store)
                #if os(macOS)
                .frame(width: 480, height: 560)
                #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(liveDocument.relativePath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if liveDocument.isInbox {
                Label("Waiting in Inbox", systemImage: "tray")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(SecretaryTheme.warn)
            }
        }
    }

    private var reclassifyPrompt: some View {
        SecretaryPanel(tint: SecretaryTheme.panel, stroke: SecretaryTheme.stroke) {
            HStack(alignment: .center, spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Filed location")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("\(liveDocument.space?.rawValue ?? "—") / \(liveDocument.category ?? "—")\(liveDocument.year.map { " / \($0)" } ?? "")")
                        .font(.headline)
                    Text("Move to another folder when needed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Button("Reclassify") { prepareReclassify() }
                    .buttonStyle(.borderedProminent)
                    .tint(SecretaryTheme.accent)
            }
        }
    }

    private var classifyPanel: some View {
        SecretaryPanel(tint: SecretaryTheme.warnSoft, stroke: SecretaryTheme.warn.opacity(0.25)) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Label(liveDocument.isInbox ? "Classify" : "Reclassify", systemImage: "sparkles")
                        .font(.title3.weight(.semibold))
                    Spacer()
                    if liveDocument.ocrText.isEmpty {
                        HStack(spacing: 6) {
                            ProgressView().controlSize(.mini)
                            Text("Reading…").font(.caption).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("\(liveDocument.ocrText.count) chars indexed")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if !liveDocument.isInbox {
                        Button("Cancel") { showReclassifyPanel = false }
                    }
                }

                if !suggestions.isEmpty {
                    Text("Suggestions — tap to load, then adjust")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    VStack(spacing: 8) {
                        ForEach(suggestions.prefix(4)) { suggestion in
                            suggestionRow(suggestion)
                        }
                    }
                }

                Divider().opacity(0.5)

                Text("Destination")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                Picker("Space", selection: $draftSpace) {
                    ForEach(DocumentSpace.allCases) { space in
                        Text(space.displayName).tag(space)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: draftSpace) { _, _ in
                    if !draftCategories.contains(draftCategory) {
                        draftCategory = draftCategories.first ?? "Tax"
                    }
                }

                FlowCategoryPicker(
                    categories: draftCategories,
                    selection: $draftCategory,
                    highlighted: Set(suggestions.filter(\.isNewCategory).map(\.category))
                )

                TextField("Or type a new category", text: $draftCategory)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 12) {
                    Toggle("Year folder", isOn: $draftUseYear)
                        .toggleStyle(.switch)
                    if draftUseYear {
                        Stepper(value: $draftYear, in: 1990...2100) {
                            Text(String(format: "%04d", draftYear))
                                .font(.body.monospacedDigit().weight(.medium))
                                .frame(minWidth: 52, alignment: .leading)
                        }
                    }
                }

                HStack(spacing: 10) {
                    TextField("Type", text: $draftType)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: 140)
                    TextField("Title", text: $draftTitle)
                        .textFieldStyle(.roundedBorder)
                }

                Text(destinationPreview)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    Button {
                        applyDraft()
                    } label: {
                        Label("Move here", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SecretaryTheme.accent)
                    .controlSize(.large)
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("More…") { showClassify = true }
                        .buttonStyle(.bordered)
                }
            }
        }
    }

    private func suggestionRow(_ suggestion: ClassificationSuggestion) -> some View {
        let selected = selectedSuggestionID == suggestion.id
        return Button {
            loadSuggestion(suggestion)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? SecretaryTheme.accent : .secondary)
                    .font(.title3)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(suggestion.destinationLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        if suggestion.isNewCategory {
                            Text("NEW")
                                .font(.caption2.weight(.bold))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(SecretaryTheme.warnSoft, in: Capsule())
                                .foregroundStyle(SecretaryTheme.warn)
                        }
                    }
                    Text(suggestion.reason)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
                Text("\(Int(suggestion.confidence * 100))%")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(selected ? SecretaryTheme.accentSoft : Color.primary.opacity(0.03))
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var preview: some View {
        if let url = store.fileURL(for: liveDocument) {
            DocumentPreview(url: url)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 220, idealHeight: 260, maxHeight: 320)
                .background(SecretaryTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous)
                        .strokeBorder(SecretaryTheme.stroke, lineWidth: 1)
                )
        }
    }

    private var metadataForm: some View {
        SecretaryPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text("Details").font(.headline)
                TextField("Title", text: $title)
                    .textFieldStyle(.roundedBorder)
                TextField("Notes", text: $notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                TextField("Tags (comma-separated)", text: $tagsText)
                    .textFieldStyle(.roundedBorder)
                Toggle("Expiry / renewal date", isOn: $expiryEnabled)
                if expiryEnabled {
                    DatePicker("Expires", selection: $expiryDate, displayedComponents: .date)
                }
                Button("Save details") {
                    let tags = tagsText.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
                    store.saveMetadata(
                        liveDocument,
                        title: title,
                        notes: notes,
                        tags: tags,
                        expiry: expiryEnabled ? expiryDate : nil
                    )
                }
                .buttonStyle(.bordered)
            }
        }
    }

    private var duplicateBanner: some View {
        SecretaryPanel(tint: SecretaryTheme.warnSoft, stroke: SecretaryTheme.warn.opacity(0.3)) {
            VStack(alignment: .leading, spacing: 6) {
                Label("Possible duplicates", systemImage: "doc.on.doc")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(SecretaryTheme.warn)
                ForEach(duplicates) { dup in
                    Text(dup.relativePath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 8) {
                if !liveDocument.isInbox {
                    Button("Reclassify") { prepareReclassify() }
                        .buttonStyle(.borderedProminent)
                        .tint(SecretaryTheme.accent)
                }
                Button(liveDocument.isFavorite ? "Unfavorite" : "Favorite") {
                    store.toggleFavorite(liveDocument)
                }
                .buttonStyle(.bordered)
                #if os(macOS)
                if let url = store.fileURL(for: liveDocument) {
                    Button("Open") { NSWorkspace.shared.open(url) }
                        .buttonStyle(.bordered)
                    Button("Show in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                    .buttonStyle(.bordered)
                }
                #endif
                #if os(iOS)
                if let url = store.fileURL(for: liveDocument) {
                    ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") }
                        .buttonStyle(.bordered)
                }
                #endif
                Spacer(minLength: 0)
                Button("Remove from app", role: .destructive) {
                    confirmRemove = true
                }
                .buttonStyle(.bordered)
            }
        }
        .confirmationDialog(
            "Remove from app?",
            isPresented: $confirmRemove,
            titleVisibility: .visible
        ) {
            Button("Remove from app", role: .destructive) {
                store.removeFromLibrary(liveDocument)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file stays on disk. It will only disappear from Secretary’s list and search.")
        }
    }

    private func prepareReclassify() {
        seedDraftFromDocument()
        reloadSuggestions()
        if let top = suggestions.first {
            loadSuggestion(top)
        }
        showReclassifyPanel = true
    }

    private func loadSuggestion(_ suggestion: ClassificationSuggestion) {
        selectedSuggestionID = suggestion.id
        draftSpace = suggestion.space
        draftCategory = suggestion.category
        draftType = suggestion.documentType
        draftTitle = suggestion.shortTitle
        if let year = FolderSchema.normalizedYear(suggestion.year) {
            draftUseYear = true
            draftYear = year
        } else if let detected = TextFeaturesYear.detect(in: liveDocument) {
            draftUseYear = true
            draftYear = detected
        } else {
            draftUseYear = false
        }
    }

    private func seedDraftFromDocument() {
        draftSpace = liveDocument.space ?? .personal
        draftCategory = liveDocument.category ?? draftCategories.first ?? "Tax"
        draftTitle = ClassificationSuggester.suggestedTitle(for: liveDocument)
        draftType = "document"
        if let year = FolderSchema.normalizedYear(TextFeaturesYear.detect(in: liveDocument) ?? liveDocument.year) {
            draftUseYear = true
            draftYear = year
        } else {
            draftUseYear = false
            draftYear = Calendar.current.component(.year, from: Date())
        }
    }

    private func applyDraft() {
        let category = ClassificationSuggester.sanitizeCategoryName(draftCategory)
        draftCategory = category
        store.ensureCategory(space: draftSpace, name: category)
        let target = ClassificationTarget(
            space: draftSpace,
            category: category,
            year: draftUseYear ? FolderSchema.normalizedYear(draftYear) : nil,
            documentType: draftType.isEmpty ? "document" : draftType,
            shortTitle: draftTitle,
            notes: liveDocument.notes,
            tags: liveDocument.tags,
            expiryDate: liveDocument.expiryDate
        )
        store.classify(document: liveDocument, as: target)
        showReclassifyPanel = false
        selectedSuggestionID = nil
    }

    private func refreshAll() {
        syncFields()
        duplicates = store.duplicates(of: liveDocument)
        seedDraftFromDocument()
        reloadSuggestions()
        if let top = suggestions.first, liveDocument.isInbox {
            loadSuggestion(top)
        }
        Task {
            await store.ensureDownloaded(liveDocument)
            await store.ensureIndexed(documentID: liveDocument.id)
        }
    }

    private func reloadSuggestions() {
        suggestions = store.suggestions(for: liveDocument)
    }

    private func syncFields() {
        title = liveDocument.title
        notes = liveDocument.notes
        tagsText = liveDocument.tags.joined(separator: ", ")
        if let expiry = liveDocument.expiryDate {
            expiryEnabled = true
            expiryDate = expiry
        } else {
            expiryEnabled = false
        }
    }
}

/// Compact wrapping category chips.
struct FlowCategoryPicker: View {
    let categories: [String]
    @Binding var selection: String
    var highlighted: Set<String> = []

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
            ForEach(categories, id: \.self) { category in
                let selected = selection == category
                let isNew = highlighted.contains(category)
                Button {
                    selection = category
                } label: {
                    HStack(spacing: 4) {
                        Text(category)
                        if isNew {
                            Text("+")
                                .font(.caption2.weight(.bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(.subheadline.weight(selected ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? SecretaryTheme.accentSoft : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            selected ? SecretaryTheme.accent.opacity(0.45)
                                : (isNew ? SecretaryTheme.warn.opacity(0.5) : SecretaryTheme.stroke),
                            lineWidth: 1
                        )
                )
                .foregroundStyle(selected ? SecretaryTheme.accent : .primary)
            }
        }
    }
}

enum TextFeaturesYear {
    static func detect(in document: DocumentRecord) -> Int? {
        DocumentDateParser.year(in: document)
    }
}

struct DocumentPreview: View {
    let url: URL

    var body: some View {
        let ext = url.pathExtension.lowercased()
        if ext == "pdf" {
            PDFKitRepresentedView(url: url)
        } else if ["png", "jpg", "jpeg", "heic", "tif", "tiff"].contains(ext) {
            #if os(macOS)
            if let image = NSImage(contentsOf: url) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
            #else
            if let image = UIImage(contentsOfFile: url.path) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
            #endif
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ContentUnavailableView("Preview unavailable", systemImage: "doc")
    }
}

#if os(macOS)
struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL
    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
        }
    }
}
#else
struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        return view
    }
    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
        }
    }
}
#endif

struct ClassifySheet: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let document: DocumentRecord

    @State private var suggestions: [ClassificationSuggestion] = []
    @State private var space: DocumentSpace = .personal
    @State private var category: String = DefaultTaxonomy.personalCategories[0]
    @State private var useYear = false
    @State private var year = Calendar.current.component(.year, from: Date())
    @State private var documentType = "document"
    @State private var shortTitle = ""

    private var categories: [String] {
        var names = Set(store.categories(for: space))
        for suggestion in suggestions where suggestion.space == space {
            names.insert(suggestion.category)
        }
        if !category.isEmpty { names.insert(category) }
        return names.sorted()
    }

    var body: some View {
        NavigationStack {
            Form {
                if !suggestions.isEmpty {
                    Section("Suggestions") {
                        ForEach(suggestions) { suggestion in
                            Button {
                                space = suggestion.space
                                category = suggestion.category
                                documentType = suggestion.documentType
                                shortTitle = suggestion.shortTitle
                                if let y = FolderSchema.normalizedYear(suggestion.year) {
                                    useYear = true
                                    year = y
                                }
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    HStack {
                                        Text(suggestion.destinationLabel)
                                        if suggestion.isNewCategory {
                                            Text("NEW").font(.caption2.weight(.bold)).foregroundStyle(.orange)
                                        }
                                    }
                                    Text(suggestion.reason).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Destination") {
                    Picker("Space", selection: $space) {
                        ForEach(DocumentSpace.allCases) { Text($0.displayName).tag($0) }
                    }
                    Picker("Category", selection: $category) {
                        ForEach(categories, id: \.self) { Text($0).tag($0) }
                    }
                    TextField("Or new category", text: $category)
                    Toggle("Year folder", isOn: $useYear)
                    if useYear {
                        Stepper(value: $year, in: 1990...2100) {
                            Text(String(format: "%04d", year)).monospacedDigit()
                        }
                    }
                    TextField("Type", text: $documentType)
                    TextField("Title", text: $shortTitle)
                }
            }
            .navigationTitle("Classify")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move") {
                        let cleaned = ClassificationSuggester.sanitizeCategoryName(category)
                        store.ensureCategory(space: space, name: cleaned)
                        store.classify(
                            document: document,
                            as: ClassificationTarget(
                                space: space,
                                category: cleaned,
                                year: useYear ? FolderSchema.normalizedYear(year) : nil,
                                documentType: documentType,
                                shortTitle: shortTitle.isEmpty ? document.displayTitle : shortTitle
                            )
                        )
                        dismiss()
                    }
                }
            }
            .onAppear {
                shortTitle = ClassificationSuggester.suggestedTitle(for: document)
                suggestions = store.suggestions(for: document)
                if let top = suggestions.first {
                    space = top.space
                    category = top.category
                    documentType = top.documentType
                    shortTitle = top.shortTitle
                    if let y = FolderSchema.normalizedYear(top.year) {
                        useYear = true
                        year = y
                    }
                } else if let y = DocumentDateParser.year(in: document) {
                    useYear = true
                    year = y
                }
            }
        }
        #if os(macOS)
        .frame(width: 460, height: 520)
        #endif
    }
}

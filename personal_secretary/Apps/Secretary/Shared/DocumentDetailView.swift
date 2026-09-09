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
    @State private var paymentStatus: PaymentStatus = .notApplicable
    @State private var paidAt = Date()
    @State private var showExtractedText = false
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
    /// Last tags written by auto-fill so OCR upgrades can replace them without clobbering edits.
    @State private var autoFilledTags: [String] = []
    @StateObject private var findSession = PDFFindSession()
    #if os(macOS)
    @AppStorage(DetailSplitLayout.metaWidthDefaultsKey) private var storedMetaWidth = DetailSplitLayout.defaultMetaWidth
    #endif

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
        Group {
            #if os(macOS)
            macDetail
            #else
            iosDetail
            #endif
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
            findSession.dismiss()
            refreshAll()
        }
        .onReceive(NotificationCenter.default.publisher(for: .secretaryFindInDocument)) { _ in
            findSession.begin(supportsFind: isPDFPreview)
        }
        .onChange(of: liveDocument.ocrText) { _, _ in
            reloadSuggestions()
            if isClassifying, selectedSuggestionID == nil {
                seedDraftFromDocument()
            }
            applySuggestedTagsIfNeeded()
        }
        .sheet(isPresented: $showExtractedText) {
            extractedTextSheet
        }
    }

    private var extractedTextSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: SecretaryTheme.spacingLG) {
                    if liveDocument.ocrText.isEmpty {
                        Text("No extracted text yet.")
                            .font(SecretaryTheme.Typography.bodySecondary)
                            .foregroundStyle(SecretaryTheme.textTertiary)
                    } else {
                        Text(liveDocument.ocrText)
                            .font(SecretaryTheme.Typography.bodySecondary)
                            .textSelection(.enabled)
                    }
                    if !liveDocument.notes.isEmpty {
                        Text("Notes")
                            .font(SecretaryTheme.Typography.captionBold)
                            .foregroundStyle(SecretaryTheme.textTertiary)
                        Text(liveDocument.notes)
                            .font(SecretaryTheme.Typography.bodySecondary)
                            .textSelection(.enabled)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(SecretaryTheme.spacingLG)
            }
            .navigationTitle("Extracted text")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showExtractedText = false }
                }
            }
        }
        #if os(macOS)
        .frame(width: 520, height: 480)
        #endif
    }

    private var isPDFPreview: Bool {
        store.fileURL(for: liveDocument)?.pathExtension.lowercased() == "pdf"
    }

    #if os(macOS)
    /// Paperless-style: metadata/classify on the left, preview filling the remaining pane.
    private var macDetail: some View {
        GeometryReader { geo in
            let detailWidth = geo.size.width
            if DetailSplitLayout.canSplit(detailWidth: Double(detailWidth)) {
                let metaWidth = CGFloat(
                    DetailSplitLayout.clampedMetaWidth(storedMetaWidth, detailWidth: Double(detailWidth))
                )
                HStack(alignment: .top, spacing: 0) {
                    ScrollView {
                        metaStack
                            .padding(.horizontal, SecretaryTheme.spacingLG)
                            .padding(.vertical, SecretaryTheme.spacingLG)
                    }
                    .frame(width: metaWidth)
                    .frame(maxHeight: .infinity)

                    DetailSplitHandle(
                        currentMetaWidth: metaWidth,
                        detailWidth: detailWidth,
                        storedMetaWidth: $storedMetaWidth
                    )

                    previewPane
                        .padding(.trailing, SecretaryTheme.spacingLG)
                        .padding(.vertical, SecretaryTheme.spacingLG)
                        .frame(minWidth: SecretaryTheme.detailPreviewMinWidth)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: SecretaryTheme.sectionSpacing) {
                        metaStack
                        previewPane
                            .frame(minHeight: SecretaryTheme.previewHeight(forViewport: geo.size.height))
                            .frame(maxWidth: .infinity)
                    }
                    .padding(SecretaryTheme.spacingLG)
                }
            }
        }
    }
    #endif

    #if !os(macOS)
    private var iosDetail: some View {
        DetailPage {
            VStack(alignment: .leading, spacing: SecretaryTheme.sectionSpacing) {
                metaStack
                compactPreview
            }
        }
    }
    #endif

    private var metaStack: some View {
        VStack(alignment: .leading, spacing: SecretaryTheme.sectionSpacing) {
            header
            if isClassifying {
                classifyPanel
            } else {
                reclassifyPrompt
            }
            metadataForm
            if !duplicates.isEmpty {
                duplicateBanner
            }
            actions
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    #if os(macOS)
    @ViewBuilder
    private var previewPane: some View {
        Group {
            if let url = store.fileURL(for: liveDocument) {
                DocumentPreview(url: url, findSession: findSession)
            } else {
                EmptyStateView(icon: "doc", title: "Preview unavailable")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SecretaryTheme.panel)
        .clipShape(RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous)
                .strokeBorder(SecretaryTheme.stroke, lineWidth: 1)
        )
    }
    #endif

    private var header: some View {
        VStack(alignment: .leading, spacing: SecretaryTheme.spacingSM) {
            HStack(spacing: SecretaryTheme.spacingSM) {
                Text(liveDocument.relativePath)
                    .font(SecretaryTheme.Typography.caption)
                    .foregroundStyle(SecretaryTheme.textTertiary)
                    .textSelection(.enabled)
                    .lineLimit(1)
                
                Spacer(minLength: 0)
                
                if liveDocument.isFavorite {
                    Label("Favorite", systemImage: "star.fill")
                        .font(SecretaryTheme.Typography.captionMedium)
                        .foregroundStyle(.yellow.opacity(0.85))
                        .labelStyle(.iconOnly)
                }
            }
            
            if liveDocument.isInbox {
                HStack(spacing: SecretaryTheme.spacingSM) {
                    Image(systemName: "tray")
                        .font(.system(size: 12))
                    Text("Waiting for classification")
                        .font(SecretaryTheme.Typography.captionMedium)
                }
                .foregroundStyle(SecretaryTheme.warn)
                .padding(.horizontal, SecretaryTheme.spacingMD)
                .padding(.vertical, SecretaryTheme.spacingSM)
                .background(
                    RoundedRectangle(cornerRadius: SecretaryTheme.radiusSmall, style: .continuous)
                        .fill(SecretaryTheme.warnSoft)
                )
            }
        }
    }

    private var reclassifyPrompt: some View {
        SecretaryPanel {
            HStack(alignment: .center, spacing: SecretaryTheme.spacingLG) {
                Image(systemName: "folder")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(SecretaryTheme.accent.opacity(0.7))
                    .frame(width: 32, height: 32)
                    .background(
                        RoundedRectangle(cornerRadius: SecretaryTheme.radiusSmall, style: .continuous)
                            .fill(SecretaryTheme.accentMuted)
                    )
                
                VStack(alignment: .leading, spacing: SecretaryTheme.spacingXS) {
                    Text("\(liveDocument.space?.rawValue ?? "—") / \(liveDocument.category ?? "—")\(liveDocument.year.map { " / \($0)" } ?? "")")
                        .font(SecretaryTheme.Typography.bodyMedium)
                        .foregroundStyle(SecretaryTheme.textPrimary)
                    Text("Current location")
                        .font(SecretaryTheme.Typography.caption)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                }
                
                Spacer(minLength: SecretaryTheme.spacingSM)
                
                Button {
                    prepareReclassify()
                } label: {
                    Text("Move")
                        .font(SecretaryTheme.Typography.captionMedium)
                }
                .buttonStyle(.bordered)
                .tint(SecretaryTheme.accent)
            }
        }
    }

    private var classifyPanel: some View {
        SecretaryPanel(tint: SecretaryTheme.warnSoft, stroke: SecretaryTheme.warn.opacity(0.15)) {
            VStack(alignment: .leading, spacing: SecretaryTheme.spacingLG) {
                HStack(alignment: .center) {
                    VStack(alignment: .leading, spacing: SecretaryTheme.spacingXS) {
                        Text(liveDocument.isInbox ? "Classify Document" : "Move Document")
                            .font(SecretaryTheme.Typography.sectionTitle)
                            .foregroundStyle(SecretaryTheme.textPrimary)
                        
                        if liveDocument.ocrText.isEmpty {
                            HStack(spacing: SecretaryTheme.spacingSM) {
                                ProgressView().controlSize(.mini)
                                Text("Reading content…")
                                    .font(SecretaryTheme.Typography.caption)
                                    .foregroundStyle(SecretaryTheme.textTertiary)
                            }
                        } else {
                            Text("\(liveDocument.ocrText.count) characters indexed")
                                .font(SecretaryTheme.Typography.metadata)
                                .foregroundStyle(SecretaryTheme.textTertiary)
                        }
                    }
                    
                    Spacer()
                    
                    if !liveDocument.isInbox {
                        Button {
                            showReclassifyPanel = false
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(SecretaryTheme.textTertiary)
                                .frame(width: 24, height: 24)
                                .background(
                                    Circle()
                                        .fill(Color.primary.opacity(0.05))
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: SecretaryTheme.spacingSM) {
                        Text("Suggestions")
                            .font(SecretaryTheme.Typography.captionBold)
                            .foregroundStyle(SecretaryTheme.textTertiary)

                        VStack(spacing: SecretaryTheme.spacingSM) {
                            ForEach(suggestions.prefix(3)) { suggestion in
                                suggestionRow(suggestion)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: SecretaryTheme.spacingMD) {
                    Text("Destination")
                        .font(SecretaryTheme.Typography.captionBold)
                        .foregroundStyle(SecretaryTheme.textTertiary)

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
                        .font(SecretaryTheme.Typography.caption)

                    HStack(spacing: SecretaryTheme.spacingMD) {
                        Toggle("Year folder", isOn: $draftUseYear)
                            .toggleStyle(.switch)
                            .font(SecretaryTheme.Typography.caption)
                        if draftUseYear {
                            Stepper(value: $draftYear, in: 1990...2100) {
                                Text(String(format: "%04d", draftYear))
                                    .font(SecretaryTheme.Typography.metadataMono)
                                    .frame(minWidth: 48, alignment: .leading)
                            }
                        }
                    }

                    HStack(spacing: SecretaryTheme.spacingSM) {
                        TextField("Type", text: $draftType)
                            .textFieldStyle(.roundedBorder)
                            .font(SecretaryTheme.Typography.caption)
                            .frame(maxWidth: 120)
                        TextField("Title", text: $draftTitle)
                            .textFieldStyle(.roundedBorder)
                            .font(SecretaryTheme.Typography.caption)
                    }

                    HStack(spacing: SecretaryTheme.spacingSM) {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 10))
                            .foregroundStyle(SecretaryTheme.textTertiary)
                        Text(destinationPreview)
                            .font(SecretaryTheme.Typography.caption)
                            .foregroundStyle(SecretaryTheme.textSecondary)
                    }
                }

                if let summary = DocumentUnderstanding.extract(
                    from: liveDocument,
                    preferredTitle: draftTitle,
                    preferredType: draftType
                ).summaryLine {
                    Text(summary)
                        .font(SecretaryTheme.Typography.metadata)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                }

                HStack(spacing: SecretaryTheme.spacingSM) {
                    Button {
                        applyDraft()
                    } label: {
                        Label("Move here", systemImage: "folder")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(SecretaryTheme.accent)
                    .controlSize(.regular)
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    extrasMenu
                }
            }
        }
    }

    private var extrasMenu: some View {
        Menu {
            Button("Ignore this file", role: .destructive) {
                store.removeFromLibrary(liveDocument)
            }
            Button("Show extracted text") {
                showExtractedText = true
            }
            if let url = store.fileURL(for: liveDocument) {
                #if os(macOS)
                Button("Reveal in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
                Button("Copy path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url.path, forType: .string)
                }
                #else
                Button("Copy path") {
                    UIPasteboard.general.string = url.path
                }
                #endif
            }
        } label: {
            Text("More")
        }
        .buttonStyle(.bordered)
    }

    private func suggestionRow(_ suggestion: ClassificationSuggestion) -> some View {
        let selected = selectedSuggestionID == suggestion.id
        return Button {
            loadSuggestion(suggestion)
        } label: {
            HStack(spacing: SecretaryTheme.spacingMD) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected ? SecretaryTheme.accent : SecretaryTheme.textTertiary)
                    .font(.system(size: 18))
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: SecretaryTheme.spacingSM) {
                        Text(suggestion.destinationLabel)
                            .font(SecretaryTheme.Typography.captionMedium)
                            .foregroundStyle(selected ? SecretaryTheme.accent : SecretaryTheme.textPrimary)
                        
                        if suggestion.isNewCategory {
                            Text("new")
                                .font(.system(size: 9, weight: .semibold))
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(SecretaryTheme.warnSoft, in: Capsule())
                                .foregroundStyle(SecretaryTheme.warn)
                        }
                    }
                    
                    Text(suggestion.reason)
                        .font(SecretaryTheme.Typography.metadata)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                        .lineLimit(1)
                }
                
                Spacer(minLength: 0)
                
                Text("\(Int(suggestion.confidence * 100))%")
                    .font(SecretaryTheme.Typography.metadataMono)
                    .foregroundStyle(SecretaryTheme.textTertiary)
            }
            .padding(.horizontal, SecretaryTheme.spacingMD)
            .padding(.vertical, SecretaryTheme.spacingSM)
            .background(
                RoundedRectangle(cornerRadius: SecretaryTheme.radiusSmall, style: .continuous)
                    .fill(selected ? SecretaryTheme.accentSoft : Color.primary.opacity(0.02))
            )
            .overlay(
                RoundedRectangle(cornerRadius: SecretaryTheme.radiusSmall, style: .continuous)
                    .strokeBorder(selected ? SecretaryTheme.accent.opacity(0.3) : Color.clear, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    #if !os(macOS)
    @ViewBuilder
    private var compactPreview: some View {
        if let url = store.fileURL(for: liveDocument) {
            DocumentPreview(url: url, findSession: findSession)
                .frame(maxWidth: .infinity)
                .frame(minHeight: SecretaryTheme.previewMinHeight, idealHeight: SecretaryTheme.previewIdealHeight, maxHeight: SecretaryTheme.previewMaxHeight)
                .background(SecretaryTheme.panel)
                .clipShape(RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: SecretaryTheme.radius, style: .continuous)
                        .strokeBorder(SecretaryTheme.stroke, lineWidth: 1)
                )
        }
    }
    #endif

    private var metadataForm: some View {
        SecretaryPanel {
            VStack(alignment: .leading, spacing: SecretaryTheme.spacingMD) {
                Text("Details")
                    .font(SecretaryTheme.Typography.captionBold)
                    .foregroundStyle(SecretaryTheme.textTertiary)
                
                VStack(alignment: .leading, spacing: SecretaryTheme.spacingSM) {
                    Text("Title")
                        .font(SecretaryTheme.Typography.metadata)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                    TextField("Document title", text: $title)
                        .textFieldStyle(.roundedBorder)
                        .font(SecretaryTheme.Typography.bodySecondary)
                }
                
                VStack(alignment: .leading, spacing: SecretaryTheme.spacingSM) {
                    Text("Notes")
                        .font(SecretaryTheme.Typography.metadata)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                    TextField("Add notes…", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .font(SecretaryTheme.Typography.bodySecondary)
                        .lineLimit(2...4)
                }
                
                VStack(alignment: .leading, spacing: SecretaryTheme.spacingSM) {
                    Text("Tags")
                        .font(SecretaryTheme.Typography.metadata)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                    TextField("Comma-separated tags", text: $tagsText)
                        .textFieldStyle(.roundedBorder)
                        .font(SecretaryTheme.Typography.bodySecondary)
                }
                
                HStack(spacing: SecretaryTheme.spacingMD) {
                    Toggle("Expiry date", isOn: $expiryEnabled)
                        .font(SecretaryTheme.Typography.caption)
                    if expiryEnabled {
                        DatePicker("", selection: $expiryDate, displayedComponents: .date)
                            .labelsHidden()
                    }
                }

                if showsPaymentControls {
                    HStack(spacing: SecretaryTheme.spacingMD) {
                        Toggle("Paid", isOn: Binding(
                            get: { paymentStatus == .paid },
                            set: { paymentStatus = $0 ? .paid : .unpaid }
                        ))
                        .font(SecretaryTheme.Typography.caption)
                        if paymentStatus == .paid {
                            DatePicker("", selection: $paidAt, displayedComponents: .date)
                                .labelsHidden()
                        }
                    }
                }
                
                Button {
                    store.saveMetadata(
                        liveDocument,
                        title: title,
                        notes: notes,
                        tags: parsedTags(from: tagsText),
                        expiry: expiryEnabled ? expiryDate : nil,
                        paymentStatus: showsPaymentControls ? paymentStatus : liveDocument.paymentStatus,
                        paidAt: showsPaymentControls && paymentStatus == .paid ? paidAt : nil
                    )
                } label: {
                    Text("Save")
                        .font(SecretaryTheme.Typography.captionMedium)
                }
                .buttonStyle(.bordered)
                .tint(SecretaryTheme.accent)
            }
        }
    }

    private var duplicateBanner: some View {
        SecretaryPanel(tint: SecretaryTheme.warnSoft, stroke: SecretaryTheme.warn.opacity(0.15)) {
            VStack(alignment: .leading, spacing: SecretaryTheme.spacingSM) {
                HStack(spacing: SecretaryTheme.spacingSM) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                    Text("Possible duplicates")
                        .font(SecretaryTheme.Typography.captionMedium)
                }
                .foregroundStyle(SecretaryTheme.warn)
                
                ForEach(duplicates) { dup in
                    Text(dup.relativePath)
                        .font(SecretaryTheme.Typography.metadata)
                        .foregroundStyle(SecretaryTheme.textTertiary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: SecretaryTheme.spacingMD) {
            Text("Actions")
                .font(SecretaryTheme.Typography.captionBold)
                .foregroundStyle(SecretaryTheme.textTertiary)
            
            HStack(spacing: SecretaryTheme.spacingSM) {
                if !liveDocument.isInbox {
                    Button {
                        prepareReclassify()
                    } label: {
                        Label("Move", systemImage: "folder")
                            .font(SecretaryTheme.Typography.captionMedium)
                    }
                    .buttonStyle(.bordered)
                    .tint(SecretaryTheme.accent)
                }
                
                Button {
                    store.toggleFavorite(liveDocument)
                } label: {
                    Label(
                        liveDocument.isFavorite ? "Unfavorite" : "Favorite",
                        systemImage: liveDocument.isFavorite ? "star.slash" : "star"
                    )
                    .font(SecretaryTheme.Typography.captionMedium)
                }
                .buttonStyle(.bordered)
                
                #if os(macOS)
                if let url = store.fileURL(for: liveDocument) {
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Label("Open", systemImage: "arrow.up.right.square")
                            .font(SecretaryTheme.Typography.captionMedium)
                    }
                    .buttonStyle(.bordered)
                    
                    Button {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    } label: {
                        Label("Reveal", systemImage: "folder")
                            .font(SecretaryTheme.Typography.captionMedium)
                    }
                    .buttonStyle(.bordered)
                }
                #endif
                
                #if os(iOS)
                if let url = store.fileURL(for: liveDocument) {
                    ShareLink(item: url) {
                        Label("Share", systemImage: "square.and.arrow.up")
                            .font(SecretaryTheme.Typography.captionMedium)
                    }
                    .buttonStyle(.bordered)
                }
                #endif
                
                Spacer(minLength: 0)
                
                Button(role: .destructive) {
                    confirmRemove = true
                } label: {
                    Label("Remove", systemImage: "trash")
                        .font(SecretaryTheme.Typography.captionMedium)
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
            Text("The file stays on disk. It will only disappear from Secretary's list and search.")
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
        draftType = ClassificationSuggester.cleanedDocumentType(suggestion.documentType)
        draftTitle = ClassificationSuggester.cleanedDisplayTitle(suggestion.shortTitle, document: liveDocument)
        if let year = FolderSchema.normalizedYear(suggestion.year) {
            draftUseYear = true
            draftYear = year
        } else if let detected = TextFeaturesYear.detect(in: liveDocument) {
            draftUseYear = true
            draftYear = detected
        } else {
            draftUseYear = false
        }
        applySuggestedTagsIfNeeded(preferred: suggestion.tags)
    }

    private func seedDraftFromDocument() {
        draftSpace = liveDocument.space ?? .personal
        draftCategory = liveDocument.category ?? draftCategories.first ?? "Tax"
        let fields = DocumentUnderstanding.extract(from: liveDocument)
        draftTitle = fields.title
        draftType = fields.documentType
        if let year = FolderSchema.normalizedYear(TextFeaturesYear.detect(in: liveDocument) ?? liveDocument.year) {
            draftUseYear = true
            draftYear = year
        } else {
            draftUseYear = false
            draftYear = Calendar.current.component(.year, from: Date())
        }
    }

    private var showsPaymentControls: Bool {
        paymentStatus == .paid || paymentStatus == .unpaid || DocumentUnderstanding.looksLikeInvoice(
            text: [liveDocument.filename, liveDocument.title, liveDocument.ocrText, draftType, tagsText].joined(separator: "\n"),
            documentType: draftType.isEmpty ? nil : draftType,
            tags: parsedTags(from: tagsText) + liveDocument.tags,
            category: liveDocument.category ?? draftCategory
        )
    }

    private func applyDraft() {
        let category = ClassificationSuggester.sanitizeCategoryName(draftCategory)
        draftCategory = category
        store.ensureCategory(space: draftSpace, name: category)
        let year = draftUseYear ? FolderSchema.normalizedYear(draftYear) : nil
        let tags = parsedTags(from: tagsText)
        let fields = DocumentUnderstanding.extract(
            from: liveDocument,
            preferredTitle: draftTitle,
            preferredType: draftType,
            preferredTags: tags
        )
        let cleanTitle = fields.title
        let cleanType = fields.documentType
        draftTitle = cleanTitle
        draftType = cleanType
        let target = ClassificationTarget(
            space: draftSpace,
            category: category,
            year: year,
            documentType: cleanType,
            shortTitle: cleanTitle,
            notes: liveDocument.notes,
            tags: tags,
            expiryDate: liveDocument.expiryDate ?? fields.dueDate,
            documentDate: fields.documentDate
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
        if liveDocument.tags.isEmpty {
            applySuggestedTagsIfNeeded()
        } else {
            tagsText = liveDocument.tags.joined(separator: ", ")
            autoFilledTags = []
        }
        if let expiry = liveDocument.expiryDate {
            expiryEnabled = true
            expiryDate = expiry
        } else {
            expiryEnabled = false
        }
        paymentStatus = liveDocument.paymentStatus
        paidAt = liveDocument.paidAt ?? Date()
        if paymentStatus == .notApplicable,
           DocumentUnderstanding.looksLikeInvoice(
            text: [liveDocument.filename, liveDocument.title, liveDocument.ocrText].joined(separator: "\n"),
            documentType: FolderSchema.documentType(fromFilename: liveDocument.filename),
            tags: liveDocument.tags,
            category: liveDocument.category
           ) {
            paymentStatus = .unpaid
        }
    }

    private func parsedTags(from text: String) -> [String] {
        text.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    /// Prefill the tags field from heuristics when the document has none, or refresh an earlier auto-fill.
    private func applySuggestedTagsIfNeeded(preferred: [String] = []) {
        let current = parsedTags(from: tagsText)
        guard liveDocument.tags.isEmpty else { return }
        guard current.isEmpty || current == autoFilledTags else { return }
        let suggested = preferred.isEmpty
            ? ClassificationSuggester.suggestedTags(
                for: liveDocument,
                space: isClassifying ? draftSpace : liveDocument.space,
                category: isClassifying ? draftCategory : liveDocument.category,
                year: isClassifying && draftUseYear ? draftYear : liveDocument.year,
                documentType: isClassifying ? draftType : nil
            )
            : preferred
        guard !suggested.isEmpty else { return }
        tagsText = suggested.joined(separator: ", ")
        autoFilledTags = suggested
    }
}

/// Compact wrapping category chips.
struct FlowCategoryPicker: View {
    let categories: [String]
    @Binding var selection: String
    var highlighted: Set<String> = []

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 100), spacing: SecretaryTheme.spacingSM)], spacing: SecretaryTheme.spacingSM) {
            ForEach(categories, id: \.self) { category in
                let selected = selection == category
                let isNew = highlighted.contains(category)
                Button {
                    selection = category
                } label: {
                    HStack(spacing: SecretaryTheme.spacingXS) {
                        Text(category)
                            .lineLimit(1)
                        if isNew {
                            Text("+")
                                .font(.system(size: 10, weight: .bold))
                        }
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .font(SecretaryTheme.Typography.caption)
                .fontWeight(selected ? .semibold : .regular)
                .padding(.horizontal, SecretaryTheme.spacingMD)
                .padding(.vertical, SecretaryTheme.spacingSM)
                .background(
                    RoundedRectangle(cornerRadius: SecretaryTheme.radiusSmall, style: .continuous)
                        .fill(selected ? SecretaryTheme.accentSoft : Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: SecretaryTheme.radiusSmall, style: .continuous)
                        .strokeBorder(
                            selected ? SecretaryTheme.accent.opacity(0.4)
                                : (isNew ? SecretaryTheme.warn.opacity(0.4) : SecretaryTheme.strokeSubtle),
                            lineWidth: 0.5
                        )
                )
                .foregroundStyle(selected ? SecretaryTheme.accent : SecretaryTheme.textPrimary)
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
    @ObservedObject var findSession: PDFFindSession

    var body: some View {
        let ext = url.pathExtension.lowercased()
        ZStack(alignment: .top) {
            previewContent(ext: ext)
            HStack(spacing: 0) {
                if findSession.isPresented {
                    DocumentFindBar(session: findSession)
                    Spacer(minLength: 0)
                } else {
                    Spacer()
                    Button {
                        findSession.begin(supportsFind: ext == "pdf")
                    } label: {
                        Image(systemName: "magnifyingglass")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(SecretaryTheme.textSecondary)
                            .padding(6)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .help("Find in Document")
                    #if os(macOS)
                    .keyboardShortcut("f", modifiers: .command)
                    #endif
                    .accessibilityLabel("Find in document")
                }
            }
            .padding(SecretaryTheme.spacingSM)
            .zIndex(1)
        }
    }

    @ViewBuilder
    private func previewContent(ext: String) -> some View {
        if ext == "pdf" {
            PDFKitRepresentedView(url: url, findSession: findSession)
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
        EmptyStateView(icon: "doc", title: "Preview unavailable")
            .frame(minHeight: 180)
    }
}

#if os(macOS)
struct PDFKitRepresentedView: NSViewRepresentable {
    let url: URL
    var findSession: PDFFindSession?

    func makeNSView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        findSession?.attach(view)
        return view
    }

    func updateNSView(_ nsView: PDFView, context: Context) {
        if nsView.document?.documentURL != url {
            nsView.document = PDFDocument(url: url)
            findSession?.resetForNewDocument()
        }
        findSession?.attach(nsView)
    }
}

private struct DetailSplitHandle: View {
    let currentMetaWidth: CGFloat
    let detailWidth: CGFloat
    @Binding var storedMetaWidth: Double
    @State private var dragOrigin: CGFloat?
    @State private var hovering = false

    var body: some View {
        ZStack {
            Color.clear
                .frame(width: CGFloat(DetailSplitLayout.dividerHitWidth))
                .contentShape(Rectangle())
            Rectangle()
                .fill(hovering ? SecretaryTheme.accent.opacity(0.45) : SecretaryTheme.stroke)
                .frame(width: hovering ? 2 : 1)
                .padding(.vertical, SecretaryTheme.spacingMD)
        }
        .frame(maxHeight: .infinity)
        .onHover { isHovering in
            hovering = isHovering
            if isHovering {
                NSCursor.resizeLeftRight.set()
            } else if dragOrigin == nil {
                NSCursor.arrow.set()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if dragOrigin == nil {
                        dragOrigin = currentMetaWidth
                    }
                    let proposed = (dragOrigin ?? currentMetaWidth) + value.translation.width
                    storedMetaWidth = DetailSplitLayout.clampedMetaWidth(
                        Double(proposed),
                        detailWidth: Double(detailWidth)
                    )
                }
                .onEnded { _ in
                    dragOrigin = nil
                    if !hovering {
                        NSCursor.arrow.set()
                    }
                }
        )
        .help("Drag to resize")
        .accessibilityLabel("Resize details and preview")
    }
}
#else
struct PDFKitRepresentedView: UIViewRepresentable {
    let url: URL
    var findSession: PDFFindSession?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.document = PDFDocument(url: url)
        findSession?.attach(view)
        return view
    }

    func updateUIView(_ uiView: PDFView, context: Context) {
        if uiView.document?.documentURL != url {
            uiView.document = PDFDocument(url: url)
            findSession?.resetForNewDocument()
        }
        findSession?.attach(uiView)
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
                        let fields = DocumentUnderstanding.extract(
                            from: document,
                            preferredTitle: shortTitle.isEmpty ? document.displayTitle : shortTitle,
                            preferredType: documentType,
                            preferredTags: document.tags
                        )
                        store.ensureCategory(space: space, name: cleaned)
                        store.classify(
                            document: document,
                            as: ClassificationTarget(
                                space: space,
                                category: cleaned,
                                year: useYear ? FolderSchema.normalizedYear(year) : nil,
                                documentType: fields.documentType,
                                shortTitle: fields.title,
                                notes: document.notes,
                                tags: document.tags,
                                documentDate: fields.documentDate
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

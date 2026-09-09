import PDFKit
import SwiftUI

extension Notification.Name {
    /// Posted by the Mac Find menu (⌘F) so the visible document detail can open its find bar.
    static let secretaryFindInDocument = Notification.Name("secretary.findInDocument")
}

/// Drives PDFKit find / highlight / next-previous for the open file preview.
@MainActor
final class PDFFindSession: ObservableObject {
    @Published var isPresented = false
    @Published var query = ""
    @Published var matchIndex = 0
    @Published var matchCount = 0
    @Published var message: String?
    @Published var supportsTextSearch = true

    private weak var pdfView: PDFView?
    private var selections: [PDFSelection] = []
    private var searchTask: Task<Void, Never>?

    func attach(_ view: PDFView) {
        guard pdfView !== view else { return }
        pdfView = view
        if isPresented, supportsTextSearch, !query.isEmpty {
            searchNow()
        }
    }

    func begin(supportsFind: Bool) {
        supportsTextSearch = supportsFind
        isPresented = true
        if !supportsFind {
            clearHighlights()
            matchCount = 0
            matchIndex = 0
            message = "Search is only available for PDF text."
            return
        }
        if query.isEmpty {
            message = nil
        } else {
            searchNow()
        }
    }

    func dismiss() {
        isPresented = false
        query = ""
        message = nil
        matchCount = 0
        matchIndex = 0
        selections = []
        clearHighlights()
        searchTask?.cancel()
    }

    func resetForNewDocument() {
        query = ""
        message = nil
        matchCount = 0
        matchIndex = 0
        selections = []
        clearHighlights()
        if isPresented, !supportsTextSearch {
            message = "Search is only available for PDF text."
        }
    }

    func queryDidChange(_ newQuery: String) {
        query = newQuery
        guard isPresented, supportsTextSearch else { return }
        searchTask?.cancel()
        searchTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 160_000_000)
            guard !Task.isCancelled else { return }
            searchNow()
        }
    }

    func findNext() {
        guard supportsTextSearch else { return }
        if selections.isEmpty {
            searchNow()
            return
        }
        revealMatch(at: matchIndex + 1)
    }

    func findPrevious() {
        guard supportsTextSearch else { return }
        if selections.isEmpty {
            searchNow()
            return
        }
        revealMatch(at: matchIndex - 1)
    }

    private func searchNow() {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard supportsTextSearch else { return }
        guard !trimmed.isEmpty else {
            selections = []
            matchCount = 0
            matchIndex = 0
            message = nil
            clearHighlights()
            return
        }
        guard let pdfView, let document = pdfView.document else {
            message = "Preview is not ready."
            return
        }

        let found = document.findString(trimmed, withOptions: [.caseInsensitive])
        selections = found
        matchCount = found.count

        if found.isEmpty {
            clearHighlights()
            matchIndex = 0
            if documentHasSearchableText(document) {
                message = "No matches"
            } else {
                message = "This PDF has no searchable text."
            }
            return
        }

        message = nil
        pdfView.highlightedSelections = found
        revealMatch(at: 0)
    }

    private func revealMatch(at index: Int) {
        guard !selections.isEmpty else { return }
        let count = selections.count
        let normalized = ((index % count) + count) % count
        matchIndex = normalized
        guard let pdfView else { return }
        let selection = selections[normalized]
        pdfView.highlightedSelections = selections
        pdfView.setCurrentSelection(selection, animate: true)
        pdfView.scrollSelectionToVisible(nil)
    }

    private func clearHighlights() {
        pdfView?.highlightedSelections = nil
        pdfView?.setCurrentSelection(nil, animate: false)
    }

    private func documentHasSearchableText(_ document: PDFDocument) -> Bool {
        if let all = document.string, all.contains(where: { $0.isLetter || $0.isNumber }) {
            return true
        }
        let limit = min(document.pageCount, 12)
        for index in 0..<limit {
            if let pageText = document.page(at: index)?.string,
               pageText.contains(where: { $0.isLetter || $0.isNumber }) {
                return true
            }
        }
        return false
    }
}

struct DocumentFindBar: View {
    @ObservedObject var session: PDFFindSession
    @FocusState private var queryFocused: Bool

    var body: some View {
        HStack(spacing: SecretaryTheme.spacingSM) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(SecretaryTheme.textTertiary)
                .font(.system(size: 12, weight: .medium))

            TextField("Find in document", text: Binding(
                get: { session.query },
                set: { session.queryDidChange($0) }
            ))
            .textFieldStyle(.plain)
            .font(SecretaryTheme.Typography.caption)
            .focused($queryFocused)
            .onSubmit { session.findNext() }
            .disabled(!session.supportsTextSearch)

            statusLabel

            if session.supportsTextSearch {
                Button {
                    session.findPrevious()
                } label: {
                    Image(systemName: "chevron.up")
                }
                .buttonStyle(.plain)
                .help("Previous match")
                .keyboardShortcut("g", modifiers: [.command, .shift])
                .disabled(session.query.isEmpty)

                Button {
                    session.findNext()
                } label: {
                    Image(systemName: "chevron.down")
                }
                .buttonStyle(.plain)
                .help("Next match")
                .keyboardShortcut("g", modifiers: .command)
                .disabled(session.query.isEmpty)
            }

            Button {
                session.dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(SecretaryTheme.textTertiary)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.primary.opacity(0.06)))
            }
            .buttonStyle(.plain)
            .help("Close find")
        }
        .padding(.horizontal, SecretaryTheme.spacingMD)
        .padding(.vertical, SecretaryTheme.spacingSM)
        .background(
            RoundedRectangle(cornerRadius: SecretaryTheme.radiusSmall, style: .continuous)
                .fill(.ultraThinMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: SecretaryTheme.radiusSmall, style: .continuous)
                .strokeBorder(SecretaryTheme.stroke, lineWidth: 1)
        )
        .onAppear { queryFocused = session.supportsTextSearch }
        .onChange(of: session.isPresented) { _, presented in
            if presented { queryFocused = session.supportsTextSearch }
        }
        #if os(macOS)
        .onExitCommand { session.dismiss() }
        #endif
    }

    @ViewBuilder
    private var statusLabel: some View {
        if session.matchCount > 0 {
            Text("\(session.matchIndex + 1) of \(session.matchCount)")
                .font(SecretaryTheme.Typography.metadataMono)
                .foregroundStyle(SecretaryTheme.textTertiary)
                .frame(minWidth: 56, alignment: .trailing)
        } else if let message = session.message {
            Text(message)
                .font(SecretaryTheme.Typography.metadata)
                .foregroundStyle(SecretaryTheme.warn)
                .lineLimit(1)
        }
    }
}

import CoreSpotlight
import Foundation
import UniformTypeIdentifiers

public enum SpotlightIndexer {
    public static let domainIdentifier = "be.vermeir.secretary.documents"

    public static func index(_ record: DocumentRecord, fileURL: URL) {
        let attribute = CSSearchableItemAttributeSet(contentType: UTType(filenameExtension: fileURL.pathExtension) ?? .data)
        attribute.title = record.displayTitle
        attribute.displayName = record.displayTitle
        attribute.contentDescription = record.notes.isEmpty ? record.relativePath : record.notes
        attribute.keywords = record.tags + [record.category, record.space?.rawValue].compactMap { $0 }
        attribute.textContent = [record.title, record.notes, record.ocrText, record.filename]
            .filter { !$0.isEmpty }
            .joined(separator: "\n")
        attribute.path = fileURL.path
        if let expiry = record.expiryDate {
            attribute.dueDate = expiry
        }

        let item = CSSearchableItem(
            uniqueIdentifier: record.id,
            domainIdentifier: domainIdentifier,
            attributeSet: attribute
        )
        CSSearchableIndex.default().indexSearchableItems([item]) { _ in }
    }

    public static func remove(ids: [String]) {
        CSSearchableIndex.default().deleteSearchableItems(withIdentifiers: ids) { _ in }
    }

    public static func removeAll() {
        CSSearchableIndex.default().deleteSearchableItems(withDomainIdentifiers: [domainIdentifier]) { _ in }
    }
}

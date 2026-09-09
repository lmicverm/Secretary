import SecretaryCore
import UIKit
import UniformTypeIdentifiers

@objc(ShareViewController)
final class ShareViewController: UIViewController {
    private let statusLabel = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        statusLabel.textAlignment = .center
        statusLabel.numberOfLines = 0
        statusLabel.text = "Saving to Secretary Inbox…"
        statusLabel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(statusLabel)
        NSLayoutConstraint.activate([
            statusLabel.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            statusLabel.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            statusLabel.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        Task { await importSharedItems() }
    }

    private func importSharedItems() async {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            finish()
            return
        }

        do {
            let library = try DocumentLibrary()
            var imported = 0
            for item in items {
                guard let attachments = item.attachments else { continue }
                for provider in attachments {
                    if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                        let url: URL = try await load(provider, type: UTType.fileURL.identifier)
                        _ = try library.importFile(from: url)
                        imported += 1
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) {
                        let data: Data = try await load(provider, type: UTType.pdf.identifier)
                        _ = try library.importData(data, filenameHint: "shared", pathExtension: "pdf")
                        imported += 1
                    } else if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                        let data: Data = try await load(provider, type: UTType.image.identifier)
                        _ = try library.importData(data, filenameHint: "shared-image", pathExtension: "jpg")
                        imported += 1
                    }
                }
            }
            await MainActor.run {
                statusLabel.text = imported > 0 ? "Saved \(imported) item(s) to Inbox." : "Nothing to import."
            }
            try await Task.sleep(nanoseconds: 600_000_000)
        } catch {
            await MainActor.run {
                statusLabel.text = error.localizedDescription
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }
        finish()
    }

    private func load<T>(_ provider: NSItemProvider, type: String) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            provider.loadItem(forTypeIdentifier: type, options: nil) { item, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                if T.self == URL.self, let url = item as? URL {
                    continuation.resume(returning: url as! T)
                } else if T.self == URL.self, let data = item as? Data,
                          let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url as! T)
                } else if T.self == Data.self, let data = item as? Data {
                    continuation.resume(returning: data as! T)
                } else if T.self == Data.self, let url = item as? URL, let data = try? Data(contentsOf: url) {
                    continuation.resume(returning: data as! T)
                } else if T.self == Data.self, let image = item as? UIImage, let data = image.jpegData(compressionQuality: 0.9) {
                    continuation.resume(returning: data as! T)
                } else {
                    continuation.resume(throwing: ShareError.unsupported)
                }
            }
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: nil)
    }

    enum ShareError: Error {
        case unsupported
    }
}

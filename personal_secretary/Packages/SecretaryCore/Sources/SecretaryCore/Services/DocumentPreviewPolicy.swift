import Foundation

/// How `DocumentDetailView` should preview a file.
///
/// PDFKit's `PDFView` uses Metal. On **My Mac (Designed for iPad)** the iOS
/// app uses `MTLResourceStorageModeShared`; Metal API Validation then aborts in
/// `synchronizeResource:` (that API is only valid for Managed storage).
/// Native **SecretaryMac** is the desktop target; this policy keeps the iOS
/// destination from opening a live `PDFView` if it is ever run on a Mac.
public enum DocumentPreviewPolicy: Sendable {
    public enum Kind: String, Equatable, Sendable {
        case missingFile
        case livePDFView
        case softwarePDFPage
        case rasterImage
        case unsupported
    }

    /// - Parameters:
    ///   - pathExtension: File extension (e.g. `pdf`, `png`).
    ///   - isReadable: File exists and is a readable regular file.
    ///   - isIOSAppOnMac: `ProcessInfo.processInfo.isiOSAppOnMac` (always false on native macOS).
    public static func kind(
        pathExtension: String,
        isReadable: Bool,
        isIOSAppOnMac: Bool
    ) -> Kind {
        guard isReadable else { return .missingFile }
        switch pathExtension.lowercased() {
        case "pdf":
            return isIOSAppOnMac ? .softwarePDFPage : .livePDFView
        case "png", "jpg", "jpeg", "heic", "tif", "tiff":
            return .rasterImage
        default:
            return .unsupported
        }
    }

    public static func isReadableFile(at url: URL, fileManager: FileManager = .default) -> Bool {
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            return false
        }
        return fileManager.isReadableFile(atPath: url.path)
    }
}

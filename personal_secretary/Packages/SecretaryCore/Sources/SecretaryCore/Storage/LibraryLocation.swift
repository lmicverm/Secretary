import Foundation

/// Resolves the on-disk library root.
/// Prefer a user-chosen folder (security-scoped bookmark); else iCloud Drive when the
/// container entitlement is present and the container exists; else Application Support.
/// Mac Debug (Personal Team) ships without the iCloud entitlement, so `url(forUbiquityContainerIdentifier:)`
/// returns nil and bootstrap uses the local Application Support library.
public enum LibraryLocation {
    public static let folderName = "Secretary"
    public static let ubiquityContainerIdentifier = "iCloud.be.vermeir.secretary"

    private static let bookmarkKey = "libraryRootBookmark"
    private static let customRootPathKey = "libraryRootPath"

    /// Currently resolved library root.
    public static func resolveRoot(fileManager: FileManager = .default) -> URL {
        if let custom = bookmarkedRootURL() {
            return custom
        }
        if let ubiquity = fileManager.url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier) {
            let docs = ubiquity.appendingPathComponent("Documents", isDirectory: true)
            return docs.appendingPathComponent(folderName, isDirectory: true)
        }
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent(folderName, isDirectory: true)
    }

    public static var isUsingiCloud: Bool {
        guard bookmarkedRootURL() == nil else { return false }
        return FileManager.default.url(forUbiquityContainerIdentifier: ubiquityContainerIdentifier) != nil
    }

    public static var isUsingCustomRoot: Bool {
        bookmarkedRootURL() != nil
    }

    public static var customRootDisplayPath: String? {
        UserDefaults.standard.string(forKey: customRootPathKey)
    }

    /// Persist a user-selected folder. Caller must keep security-scoped access alive while using it.
    public static func setCustomRoot(_ url: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
            throw LocationError.notADirectory
        }

        let data = try url.bookmarkData(
            options: bookmarkCreationOptions,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        UserDefaults.standard.set(data, forKey: bookmarkKey)
        UserDefaults.standard.set(url.path, forKey: customRootPathKey)
    }

    public static func clearCustomRoot() {
        UserDefaults.standard.removeObject(forKey: bookmarkKey)
        UserDefaults.standard.removeObject(forKey: customRootPathKey)
    }

    /// Resolve bookmark and start security-scoped access. Returns URL that must stay accessed.
    public static func beginAccessingCustomRoot() -> URL? {
        guard let url = bookmarkedRootURL(accessing: true) else { return nil }
        return url
    }

    public static func stopAccessing(_ url: URL) {
        url.stopAccessingSecurityScopedResource()
    }

    private static var bookmarkCreationOptions: URL.BookmarkCreationOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        // iOS: security-scoped bookmarks from the document picker use the default options.
        return []
        #endif
    }

    private static var bookmarkResolutionOptions: URL.BookmarkResolutionOptions {
        #if os(macOS)
        return [.withSecurityScope]
        #else
        return []
        #endif
    }

    private static func bookmarkedRootURL(accessing: Bool = false) -> URL? {
        guard let data = UserDefaults.standard.data(forKey: bookmarkKey) else { return nil }
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: bookmarkResolutionOptions,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale {
                if let refreshed = try? url.bookmarkData(
                    options: bookmarkCreationOptions,
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                ) {
                    UserDefaults.standard.set(refreshed, forKey: bookmarkKey)
                    UserDefaults.standard.set(url.path, forKey: customRootPathKey)
                }
            }
            if accessing {
                guard url.startAccessingSecurityScopedResource() else { return nil }
            }
            return url
        } catch {
            return nil
        }
    }

    public enum LocationError: Error, LocalizedError {
        case notADirectory

        public var errorDescription: String? {
            "Please choose an existing folder."
        }
    }
}

/// Coordinates iCloud-aware file reads/writes and placeholder downloads.
public enum CloudFileCoordinator {
    public static func coordinatedWrite(to url: URL, options: NSFileCoordinator.WritingOptions = [], body: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var bodyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(writingItemAt: url, options: options, error: &coordinatorError) { newURL in
            do {
                try body(newURL)
            } catch {
                bodyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let bodyError { throw bodyError }
    }

    public static func coordinatedRead(from url: URL, body: (URL) throws -> Void) throws {
        var coordinatorError: NSError?
        var bodyError: Error?
        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: url, options: [], error: &coordinatorError) { newURL in
            do {
                try body(newURL)
            } catch {
                bodyError = error
            }
        }
        if let coordinatorError { throw coordinatorError }
        if let bodyError { throw bodyError }
    }

    @discardableResult
    public static func ensureDownloaded(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey, .isUbiquitousItemKey])
        if values.isUbiquitousItem == true {
            if values.ubiquitousItemDownloadingStatus == .current {
                return true
            }
            try FileManager.default.startDownloadingUbiquitousItem(at: url)
            return false
        }
        return FileManager.default.fileExists(atPath: url.path)
    }

    public static func pinForOffline(_ url: URL) throws {
        _ = try ensureDownloaded(url)
        var values = URLResourceValues()
        values.isExcludedFromBackup = false
        var mutable = url
        try? mutable.setResourceValues(values)
    }
}

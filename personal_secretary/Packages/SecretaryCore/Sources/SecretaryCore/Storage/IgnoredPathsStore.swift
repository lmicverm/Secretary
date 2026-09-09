import Foundation

/// Paths the user removed from the app. Files on disk are never deleted.
public final class IgnoredPathsStore: @unchecked Sendable {
    private let fileURL: URL
    private let queue = DispatchQueue(label: "be.secretary.IgnoredPathsStore")
    private var paths: Set<String>

    public init(libraryRoot: URL) {
        fileURL = libraryRoot
            .appendingPathComponent(FolderSchema.metaFolder)
            .appendingPathComponent("ignored.json")
        if let data = try? Data(contentsOf: fileURL),
           let list = try? JSONDecoder().decode([String].self, from: data) {
            paths = Set(list)
        } else {
            paths = []
        }
    }

    public func contains(_ relativePath: String) -> Bool {
        queue.sync { paths.contains(relativePath) }
    }

    public func ignore(_ relativePath: String) {
        queue.sync {
            paths.insert(relativePath)
            persistLocked()
        }
    }

    public func unignore(_ relativePath: String) {
        queue.sync {
            paths.remove(relativePath)
            persistLocked()
        }
    }

    public func all() -> [String] {
        queue.sync { paths.sorted() }
    }

    private func persistLocked() {
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(paths.sorted())
            try data.write(to: fileURL, options: .atomic)
        } catch {
            // Best-effort; never throw into classify/remove flows.
        }
    }
}

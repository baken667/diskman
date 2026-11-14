import Foundation

/// The only way anything is removed: items go to the Trash, never deleted outright.
public enum Trash {
    public struct Failure: Identifiable, Sendable {
        public let url: URL
        public let message: String
        public var id: URL { url }
    }

    /// Moves the items to the Trash and returns the ones that could not be moved.
    public static func move(_ urls: [URL]) async -> [Failure] {
        urls.compactMap { url in
            do {
                guard isSafe(url) else { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                return nil
            } catch {
                return Failure(url: url, message: error.localizedDescription)
            }
        }
    }

    /// Last line of defence against a bad caller: never trash a volume root,
    /// a top-level folder (/Library, /Users, ...) or a home folder.
    static func isSafe(_ url: URL) -> Bool {
        let url = url.standardizedFileURL
        return url.pathComponents.count > 2 && url.deletingLastPathComponent().path != "/Users"
    }
}

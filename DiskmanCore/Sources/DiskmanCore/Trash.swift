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

    /// Last line of defence against a bad caller or a bad rule: never trash a volume, a top-level folder
    /// (/Library, /Users, ...), a home folder, or the folders everything else lives in (~/Documents,
    /// ~/Library, ~/Library/Caches, /Library/Application Support, ...). Dot folders in a home are fine.
    static func isSafe(_ url: URL) -> Bool {
        let parts = url.standardizedFileURL.pathComponents   // ["/", "Users", "me", "Library", ...]
        guard parts.count > 2 else { return false }
        switch parts[1] {
        case "Volumes", "Library", "System": return parts.count > 3
        case "Users":
            guard parts.count > 3 else { return false }   // a home folder
            if parts.count == 4 { return parts[3].hasPrefix(".") }
            return parts[3] != "Library" || parts.count > 5
        default: return true
        }
    }
}

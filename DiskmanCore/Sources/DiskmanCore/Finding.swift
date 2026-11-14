import Foundation

/// Something on disk that a scanner proposes to remove.
/// Every feature (uninstaller, cache cleaners, brew, ...) produces findings;
/// frontends preview them and hand the chosen ones to `Trash`.
public struct Finding: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case application, applicationSupport, caches, containers, preferences, logs, savedState, launchItems, plugins, receipts
    }

    public let url: URL
    public let kind: Kind
    public let size: Int64
    /// Whether the item surely belongs to the app. Uncertain items are shown but not preselected:
    /// trashing someone else's file is worse than leaving one behind.
    public let isCertain: Bool
    public var id: URL { url }

    public init(url: URL, kind: Kind, isCertain: Bool = true) {
        self.url = url
        self.kind = kind
        self.isCertain = isCertain
        self.size = url.allocatedSize
    }
}

extension URL {
    /// Disk space taken by a file, or by a folder with everything inside it.
    var allocatedSize: Int64 {
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey]
        func size(_ url: URL) -> Int64 {
            Int64((try? url.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        guard let children = FileManager.default.enumerator(at: self, includingPropertiesForKeys: Array(keys)) else {
            return size(self)
        }
        return children.reduce(size(self)) { $0 + (($1 as? URL).map(size) ?? 0) }
    }
}

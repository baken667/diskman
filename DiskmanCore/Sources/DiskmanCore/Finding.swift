import Darwin
import Foundation

/// Something on disk that a scanner proposes to remove.
/// Every feature (uninstaller, cache cleaners, brew, ...) produces findings;
/// frontends preview them and hand the chosen ones to `Trash`.
public struct Finding: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable, Codable {
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
    /// Disk space taken by a file, or by a folder with everything inside it, like `du -sk`:
    /// allocated blocks, symlinks never followed, other volumes skipped, hard-linked files counted once.
    var allocatedSize: Int64 {
        struct FileID: Hashable { let dev: dev_t, ino: ino_t }
        return withUnsafeFileSystemRepresentation { path -> Int64 in
            guard let path, let fts = fts_open([UnsafeMutablePointer(mutating: path), nil], FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV, nil) else {
                return 0
            }
            defer { fts_close(fts) }
            var total: Int64 = 0
            var seen = Set<FileID>()
            while let entry = fts_read(fts), !Task.isCancelled {
                switch Int32(entry.pointee.fts_info) {
                case FTS_DP, FTS_DC, FTS_ERR, FTS_NS, FTS_NSOK: continue   // already counted, or no stat
                default: break
                }
                let st = entry.pointee.fts_statp.pointee
                if st.st_nlink > 1, st.st_mode & S_IFMT != S_IFDIR, !seen.insert(FileID(dev: st.st_dev, ino: st.st_ino)).inserted {
                    continue
                }
                total += Int64(st.st_blocks) * 512
            }
            return total
        }
    }
}

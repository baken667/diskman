import Darwin
import Foundation

/// A kind of regenerable clutter (a tool's download cache, an app's logs, ...) described by path patterns.
/// The built-in rules live in Resources/cleanup-rules.json; names and descriptions there are English
/// and the frontends localize them by `id`.
public struct CleanupRule: Decodable, Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let description: String
    public let group: String
    public let kind: Finding.Kind
    /// "~/..." patterns. Any component may be an fnmatch glob ("*", "*.log", "*OS DeviceSupport").
    /// Only items strictly inside the literal prefix are found, so a pattern without a glob finds nothing.
    public let paths: [String]
    /// Fully regenerable: checked by default. Otherwise the user opts in.
    public let isSafe: Bool
    /// Apps to quit before cleaning.
    public let appBundleIDs: [String]

    public static let builtIn: [CleanupRule] = {
        let url = Bundle.module.url(forResource: "cleanup-rules", withExtension: "json")!
        return try! JSONDecoder().decode([CleanupRule].self, from: Data(contentsOf: url))
    }()
}

public struct CleanupResult: Identifiable, Sendable {
    public let rule: CleanupRule
    /// Largest first.
    public let findings: [Finding]
    public var size: Int64 { findings.reduce(0) { $0 + $1.size } }
    public var id: String { rule.id }
}

public enum Cleaner {
    /// Rules that found something, in rule order. Each path belongs to the first rule that claims it:
    /// a later rule skips items equal to, inside, or containing an already-claimed path
    /// (so a generic "~/Library/Caches/*" rule doesn't double-count Homebrew's cache).
    public static func scan(_ rules: [CleanupRule] = CleanupRule.builtIn, home: URL = .homeDirectory) async -> [CleanupResult] {
        var byID: [String: CleanupResult] = [:]
        for await result in results(rules, home: home) { byID[result.id] = result }
        return rules.compactMap { byID[$0.id] }.filter { !$0.findings.isEmpty }
    }

    /// Every rule's result, empty ones included, as soon as its sizing finishes (so not in rule order).
    /// Claims work as in `scan`. Cancelling the consuming task stops the scan.
    public static func results(_ rules: [CleanupRule] = CleanupRule.builtIn, home: URL = .homeDirectory) -> AsyncStream<CleanupResult> {
        AsyncStream { continuation in
            let task = Task {
                // Globbing is cheap and claims go in rule order; sizing is slow and runs concurrently.
                var claimed: [String] = []
                var urls = [[URL]](repeating: [], count: rules.count)
                for (index, rule) in rules.enumerated() {
                    for url in rule.paths.flatMap({ expand($0, home: home) }) {
                        let path = url.path
                        guard !claimed.contains(where: { $0 == path || path.hasPrefix($0 + "/") || $0.hasPrefix(path + "/") }) else { continue }
                        claimed.append(path)
                        urls[index].append(url)
                    }
                }
                var pending = urls.map(\.count)
                var found = [[Finding]](repeating: [], count: rules.count)
                func finish(_ index: Int) {
                    continuation.yield(CleanupResult(rule: rules[index], findings: found[index].sorted {
                        $0.size != $1.size ? $0.size > $1.size : $0.url.path < $1.url.path
                    }))
                }
                for index in rules.indices where pending[index] == 0 { finish(index) }
                await withTaskGroup(of: (Int, Finding).self) { group in
                    for (index, rule) in rules.enumerated() {
                        for url in urls[index] {
                            group.addTask { (index, Finding(url: url, kind: rule.kind, isCertain: rule.isSafe)) }
                        }
                    }
                    for await (index, finding) in group {
                        if finding.size > 0 { found[index].append(finding) }   // empty or unreadable: nothing to gain
                        pending[index] -= 1
                        if pending[index] == 0 { finish(index) }
                    }
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Existing items matching a "~/..." pattern. Symlinks are never followed below the literal prefix
    /// nor returned, and nothing outside the literal prefix (or unsafe for `Trash`) is ever returned.
    static func expand(_ pattern: String, home: URL) -> [URL] {
        let parts = pattern.dropFirst(2).split(separator: "/").map(String.init)
        guard pattern.hasPrefix("~/"), !parts.contains(".."), !parts.contains(".") else { return [] }
        func isGlob(_ part: String) -> Bool { part.contains { "*?[".contains($0) } }
        guard let first = parts.firstIndex(where: isGlob) else { return [] }
        let root = parts[..<first].reduce(home) { $0.appending(path: $1) }
        var urls = [root]
        for index in first..<parts.count {
            let part = parts[index], isLast = index == parts.count - 1
            urls = urls.flatMap { folder in
                isGlob(part)
                    // Rebuilt from the folder: listing resolves symlinked parents (/var → /private/var).
                    ? LeftoverFinder.contents(folder).map(\.lastPathComponent).filter { fnmatch(part, $0, FNM_PERIOD) == 0 }
                        .map { folder.appending(path: $0) }
                    : [folder.appending(path: part)]
            }.filter { url in
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                return isLast ? values?.isSymbolicLink == false : values?.isDirectory == true
            }
        }
        return urls.filter { Trash.isSafe($0) && $0.path.hasPrefix(root.path + "/") }
    }
}

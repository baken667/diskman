import Foundation
import Testing
@testable import DiskmanCore

@Test func builtInRulesDecode() {
    let rules = CleanupRule.builtIn
    #expect(rules.count > 20)
    #expect(Set(rules.map(\.id)).count == rules.count)
    #expect(rules.allSatisfy { !$0.paths.isEmpty && $0.paths.allSatisfy { $0.hasPrefix("~/") && $0.contains("*") } })
    // At least two literal folders before the first glob: a rule may empty "~/Library/Caches",
    // never "~/Library" or the home folder itself.
    for path in rules.flatMap(\.paths) {
        let literal = path.dropFirst(2).split(separator: "/").prefix { !$0.contains { "*?[".contains($0) } }
        #expect(literal.count >= 2, "\(path)")
    }
    #expect(rules.last?.id == "system.caches") // generic last
    // A report-only rule is never preselected, and a hint belongs to a rule that explains rather than removes.
    for rule in rules {
        if rule.isReportOnly { #expect(!rule.isSafe, "\(rule.id)") }
        if rule.hint != nil { #expect(rule.isReportOnly, "\(rule.id)") }
    }
}

@Test func reportOnlyRulesAreMeasuredButNeverMoved() async throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fm.removeItem(at: home) }
    for path in ["vm/disk/data", "cache/a/data"] {
        let url = home.appending(path: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: 5000).write(to: url)
    }
    let rules = try JSONDecoder().decode([CleanupRule].self, from: Data("""
        [{"id": "vm", "group": "G", "kind": "applicationSupport", "isSafe": false, "reportOnly": true, "name": "VM",
          "description": "d", "paths": ["~/vm/*"], "appBundleIDs": [], "hint": "tool prune"},
         {"id": "cache", "group": "G", "kind": "caches", "isSafe": true, "name": "Cache", "description": "d",
          "paths": ["~/cache/*"], "appBundleIDs": []}]
        """.utf8))
    let results = await Cleaner.scan(rules, home: home)
    #expect(results.map(\.id) == ["vm", "cache"] && results[0].size > 0)
    #expect(results[0].removable.isEmpty && results[1].removable.count == 1)
    #expect(rules[0].hint == "tool prune" && rules[1].hint == nil && !rules[1].isReportOnly)
    // Asked to move all of it, then nothing, then the report-only disk by name: it stays every time.
    _ = await Cleaner.move([results[0]])
    _ = await Cleaner.move(results, only: [])
    _ = await Cleaner.move(results, only: [results[0].findings[0].url])   // named outright, still not moved
    #expect(fm.fileExists(atPath: home.appending(path: "vm/disk").path) && fm.fileExists(atPath: home.appending(path: "cache/a").path))
}

@Test func scansRulesInOrder() async throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fm.removeItem(at: home) }
    func write(_ path: String, bytes: Int = 5000) throws {
        let url = home.appending(path: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(count: bytes).write(to: url)
    }
    try write("Library/Caches/Tool/a/blob")
    try write("Library/Caches/Tool/b/blob", bytes: 50000)
    try write("Library/Caches/Tool/.hidden")
    try write("Library/Caches/Other/blob")
    try write("Library/Caches/Vendor/Browser/Profile 1/Cache/blob")
    try write("Library/Caches/Vendor/Browser/Profile 1/Prefs")       // mid-path glob picks only Cache
    try write("Library/Logs/old.log")
    try write("Library/Logs/keep.txt")
    try write("Library/Application Support/App/Cache/blob")
    try write("Library/Application Support/App/Data/blob")
    try write("Outside/secret")
    try fm.createDirectory(at: home.appending(path: "Library/Empty/x"), withIntermediateDirectories: true)
    // Symlinks below the literal prefix are neither followed nor returned.
    try fm.createSymbolicLink(at: home.appending(path: "Library/Caches/Link"), withDestinationURL: home.appending(path: "Outside"))
    try fm.createSymbolicLink(at: home.appending(path: "Library/Caches/Vendor/LinkBrowser"), withDestinationURL: home.appending(path: "Outside"))

    let json = """
    [
      {"id": "tool", "name": "Tool", "description": "", "group": "Developer", "kind": "caches", "isSafe": true,
       "paths": ["~/Library/Caches/Tool/*"], "appBundleIDs": []},
      {"id": "browser", "name": "Browser", "description": "", "group": "Browsers", "kind": "caches", "isSafe": true,
       "paths": ["~/Library/Caches/Vendor/*/*/Cache", "~/Library/Caches/Vendor/*/*"], "appBundleIDs": ["com.vendor.browser"]},
      {"id": "app", "name": "App", "description": "", "group": "Apps", "kind": "caches", "isSafe": true,
       "paths": ["~/Library/Application Support/*"], "appBundleIDs": []},
      {"id": "appCache", "name": "App cache", "description": "", "group": "Apps", "kind": "caches", "isSafe": true,
       "paths": ["~/Library/Application Support/*/Cache"], "appBundleIDs": []},
      {"id": "logs", "name": "Logs", "description": "", "group": "System", "kind": "logs", "isSafe": true,
       "paths": ["~/Library/Logs/*.log", "~/Library/Logs", "~/../*", "~/Library/./*", "/tmp/*"], "appBundleIDs": []},
      {"id": "empty", "name": "Empty", "description": "", "group": "System", "kind": "caches", "isSafe": true,
       "paths": ["~/Library/Empty/*", "~/Library/Missing/*"], "appBundleIDs": []},
      {"id": "generic", "name": "Caches", "description": "", "group": "System", "kind": "caches", "isSafe": false,
       "paths": ["~/Library/Caches/*"], "appBundleIDs": []}
    ]
    """
    let rules = try JSONDecoder().decode([CleanupRule].self, from: Data(json.utf8))
    let results = await Cleaner.scan(rules, home: home)

    func paths(_ id: String) -> [String] {
        results.first { $0.id == id }?.findings.map { String($0.url.path.dropFirst(home.path.count + 1)) } ?? []
    }
    #expect(results.map(\.id) == ["tool", "browser", "app", "logs", "generic"])
    #expect(paths("tool") == ["Library/Caches/Tool/b", "Library/Caches/Tool/a"]) // largest first, no dot files
    // Child claimed first: the second pattern's parent "Profile 1" contains it, so it is skipped.
    #expect(paths("browser") == ["Library/Caches/Vendor/Browser/Profile 1/Cache"])
    // Parent claimed first: the later rule's "App/Cache" is inside it, so "appCache" finds nothing.
    #expect(paths("app") == ["Library/Application Support/App"])
    // Literal patterns and escapes out of home find nothing.
    #expect(paths("logs") == ["Library/Logs/old.log"])
    // "Tool" and "Vendor" contain claimed items; symlinks are skipped.
    #expect(paths("generic") == ["Library/Caches/Other"])
    #expect(results.first { $0.id == "generic" }?.findings.first?.isCertain == false)
    #expect(results.allSatisfy { $0.size == $0.findings.reduce(0) { $0 + $1.size } && $0.size > 0 })
}

@Test func expandNeverLeavesTheLiteralPrefix() throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fm.removeItem(at: home) }
    try fm.createDirectory(at: home.appending(path: "Library/Caches/x"), withIntermediateDirectories: true)
    #expect(Cleaner.expand("~/Library/Caches", home: home).isEmpty)
    #expect(Cleaner.expand("~/Library/Caches/../*", home: home).isEmpty)
    #expect(Cleaner.expand("/Library/*", home: home).isEmpty)
    #expect(Cleaner.expand("~/Library/Caches/*", home: home).map(\.lastPathComponent) == ["x"])
    // A home folder itself is never returned, whatever the pattern.
    #expect(Cleaner.expand("~/*", home: URL(filePath: "/Users")).allSatisfy { $0.pathComponents.count > 3 } )
}

@Test func allocatedSizeCountsLikeDu() throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let outside = fm.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fm.removeItem(at: outside) }
    try fm.createDirectory(at: root.appending(path: "a/b/c"), withIntermediateDirectories: true)
    try fm.createDirectory(at: outside, withIntermediateDirectories: true)
    try Data(count: 100_000).write(to: root.appending(path: "a/b/c/deep"))
    try Data(count: 100_000).write(to: outside.appending(path: "big"))
    let base = root.allocatedSize
    #expect(base >= 100_000)                                     // nested folders are walked
    #expect(root.appending(path: "a/b/c/deep").allocatedSize >= 100_000)   // a plain file works too

    try fm.linkItem(at: root.appending(path: "a/b/c/deep"), to: root.appending(path: "a/twin"))
    try fm.createSymbolicLink(at: root.appending(path: "a/link"), withDestinationURL: outside)
    let after = root.allocatedSize
    #expect(after < base + 100_000)                              // hard link counted once, symlink not followed
    #expect(root.appending(path: "a/link").allocatedSize < 100_000)   // not even when it is the root
    #expect(fm.temporaryDirectory.appending(path: "missing-\(UUID())").allocatedSize == 0)
}

@Test func streamYieldsEveryRuleLikeScan() async throws {
    let fm = FileManager.default
    let home = fm.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fm.removeItem(at: home) }
    for path in ["Library/Caches/A/x", "Library/Caches/A/y", "Library/Logs/B/z"] {
        try fm.createDirectory(at: home.appending(path: path), withIntermediateDirectories: true)
        try Data(count: 5000).write(to: home.appending(path: path + "/blob"))
    }
    let json = """
    [
      {"id": "a", "name": "A", "description": "", "group": "G", "kind": "caches", "isSafe": true, "paths": ["~/Library/Caches/A/*"], "appBundleIDs": []},
      {"id": "none", "name": "None", "description": "", "group": "G", "kind": "caches", "isSafe": true, "paths": ["~/Missing/*"], "appBundleIDs": []},
      {"id": "b", "name": "B", "description": "", "group": "G", "kind": "logs", "isSafe": false, "paths": ["~/Library/Logs/*"], "appBundleIDs": []}
    ]
    """
    let rules = try JSONDecoder().decode([CleanupRule].self, from: Data(json.utf8))
    var streamed: [CleanupResult] = []
    for await result in Cleaner.results(rules, home: home) { streamed.append(result) }
    #expect(streamed.map(\.id).sorted() == ["a", "b", "none"])
    #expect(streamed.first { $0.id == "none" }?.findings.isEmpty == true)

    let scanned = await Cleaner.scan(rules, home: home)
    #expect(scanned.map(\.id) == ["a", "b"])
    for result in scanned {
        let match = try #require(streamed.first { $0.id == result.id })
        #expect(match.findings == result.findings)
    }
}

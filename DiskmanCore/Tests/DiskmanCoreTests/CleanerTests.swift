import Foundation
import Testing
@testable import DiskmanCore

@Test func builtInRulesDecode() {
    let rules = CleanupRule.builtIn
    #expect(rules.count > 20)
    #expect(Set(rules.map(\.id)).count == rules.count)
    #expect(rules.allSatisfy { !$0.paths.isEmpty && $0.paths.allSatisfy { $0.hasPrefix("~/") && $0.contains("*") } })
    #expect(rules.last?.id == "system.caches") // generic last
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

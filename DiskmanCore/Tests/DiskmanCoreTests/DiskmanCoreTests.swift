import Foundation
import Testing
@testable import DiskmanCore

@Test func matchesNamesThatBelongToTheApp() {
    func match(_ entry: String, ids: [String] = ["com.fooinc.foo"], names: [String] = ["Foo"], team: String? = nil) -> Bool? {
        LeftoverFinder.match(entry: entry, identifiers: ids, names: names, teamID: team)
    }
    let certain = [
        "com.fooinc.foo", "com.fooinc.foo.plist", "com.fooinc.foo.savedState", "com.fooinc.foo.ShipIt", "com.fooinc.foo.dua",
        "com.fooinc.foo.binarycookies", "com.fooinc.foo.36A3C032-E6E3-5B89-908A-9D3543CCE881.plist", "com.fooinc.foo.bom",
        "ABCDE12345.com.fooinc.foo", "group.com.fooinc.foo", "Foo", "foo.log", "COM.FOOINC.FOO.plist",
        ".com.fooinc.foo.Rf8Vtr", "com.fooinc.foo.5X6jZo",
    ]
    // Shown, but not preselected: another product may share the prefix.
    let uncertain = ["com.fooinc.foo.helper", "group.com.fooinc.foo.shared", "com.fooinc.foo.Shared", "other.com.fooinc.foo"]
    let no = ["com.fooinc.football.plist", "com.fooinc", "Foobar", "com.other.app.plist", "My Foo", "Foo2", "foo.other.vendor"]
    for entry in certain { #expect(match(entry) == true, "\(entry)") }
    for entry in uncertain { #expect(match(entry) == false, "\(entry)") }
    for entry in no { #expect(match(entry) == nil, "\(entry)") }
    // A bundle ID without dots must not swallow other vendors' files.
    #expect(match("foo.other.vendor", ids: ["foo"], names: ["Bar"]) == nil)
    // Helper IDs and alternative names count; spacing, dashes and version suffixes don't matter.
    #expect(match("com.foo.login-helper", ids: ["com.fooinc.foo", "com.foo.login-helper"]) == true)
    #expect(match("com.fooinc.foo.helper.plist", ids: ["com.fooinc.foo", "com.fooinc.foo.helper"]) == true)
    for entry in ["AndroidStudio2026.1", "android-studio", "Android Studio-2026-11-14.ips"] {
        #expect(match(entry, names: ["Android Studio"]) == true, "\(entry)")
    }
    #expect(match("Android Studio Tools", names: ["Android Studio"]) == nil)
    #expect(match("Code", names: ["Code", "Visual Studio Code"]) == true)
    // Chrome for Testing is another product, not a Chrome leftover.
    #expect(match("com.google.chrome.for.testing.plist", ids: ["com.google.Chrome"], names: ["Google Chrome"]) == false)
    #expect(match("com.google.Chrome.plist", ids: ["com.google.Chrome"], names: ["Google Chrome"]) == true)
    // Same signer and vendor, no app ID: maybe a sibling product.
    #expect(match("ABCDE12345.com.fooinc.sync", team: "ABCDE12345") == false)
    #expect(match("ABCDE12345.com.other.sync", team: "ABCDE12345") == nil)
    #expect(match("ZZZZZ99999.com.fooinc.sync", team: "ABCDE12345") == nil)
}

@Test func findsLeftoversEverywhere() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    func write(_ path: String, _ text: String = "data") throws {
        let url = root.appending(path: path)
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
    }
    func plist(_ dict: [String: Any]) throws -> String {
        String(decoding: try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0), as: UTF8.self)
    }
    try write("Apps/Foo.app/Contents/Info.plist", try plist(["CFBundleIdentifier": "com.fooinc.foo", "CFBundleName": "Foo Studio"]))
    let appPath = root.appending(path: "Apps/Foo.app").path
    try write("Library/Caches/com.fooinc.foo/blob")
    try write("Library/Caches/com.fooinc.foo/com.fooinc.foo.plist") // inside a listed folder: not listed again
    try write("Library/Preferences/com.fooinc.foo.plist")
    try write("Library/Preferences/com.fooinc.foo.beta.plist")
    try write("Library/Preferences/com.other.app.plist")
    // Vendor folder, helper embedded in the bundle, and a neighbour that must stay.
    try write("Library/Application Support/Foo Inc/Foo/state")
    try write("Library/Application Support/Foo Inc/Other Product/state")
    try write("Apps/Foo.app/Contents/Library/LaunchAgents/com.fooinc.agent.plist")
    try write("Library/LaunchAgents/com.fooinc.agent.plist")
    // Launch jobs found by what they run, whatever their file is called.
    try write("Library/LaunchAgents/updater.plist", try plist(["Label": "updater", "ProgramArguments": [appPath + "/Contents/MacOS/up"]]))
    try write("Library/LaunchDaemons/svc.plist", try plist(["Label": "svc", "AssociatedBundleIdentifiers": ["com.fooinc.foo"]]))
    try write("Library/LaunchDaemons/other.plist", try plist(["Label": "other", "Program": "/Apps/Foo2.app/x"]))
    // New Library rows.
    try write("Library/QuickLook/Foo.qlgenerator/Contents/Info.plist")
    try write("Library/Audio/Plug-Ins/VST3/Foo.vst3/x")
    try write("Library/Application Support/CrashReporter/Foo Studio_36A3C032-E6E3-5B89-908A-9D3543CCE881.plist")
    // Per-user Darwin cache and temp folders, installer receipts.
    try write("var/C/com.fooinc.foo/x")
    try write("var/T/.com.fooinc.foo.Rf8Vtr")
    try write("var/T/com.other.app/x")
    try write("receipts/com.fooinc.foo.pkg.bom")
    try write("receipts/com.fooinc.foo.pkg.plist")
    try write("receipts/com.fooinc.football.pkg.plist")
    // Home dot and XDG folders: exact names only, never certain.
    try write("home/.foo/x")
    try write("home/.config/foo/x")
    try write("home/.local/share/Foo/x")
    try write("home/.config/foobar/x")
    try write("home/foo/x") // not a dot folder
    // The same Library reached twice through a symlink is listed once.
    try fm.createSymbolicLink(at: root.appending(path: "LibraryLink"), withDestinationURL: root.appending(path: "Library"))

    let apps = await InstalledApp.installed(in: [root.appending(path: "Apps")])
    let app = try #require(apps.first)
    #expect(app.bundleID == "com.fooinc.foo" && app.name == "Foo" && app.teamID == nil)

    let findings = await LeftoverFinder.findings(
        for: app,
        libraries: [root.appending(path: "Library"), root.appending(path: "LibraryLink")],
        systemFolders: [(root.appending(path: "var/C"), .caches), (root.appending(path: "var/T"), .caches), (root.appending(path: "receipts"), .receipts)],
        home: root.appending(path: "home")
    )
    let found = Dictionary(uniqueKeysWithValues: findings.map { ($0.url.path.components(separatedBy: root.lastPathComponent + "/").last!, $0.isCertain) })
    #expect(found == [
        "Apps/Foo.app": true,
        "Library/Caches/com.fooinc.foo": true,
        "Library/Preferences/com.fooinc.foo.plist": true,
        "Library/Preferences/com.fooinc.foo.beta.plist": false,
        "Library/Application Support/Foo Inc/Foo": true,
        "Library/LaunchAgents/com.fooinc.agent.plist": true,
        "Library/LaunchAgents/updater.plist": true,
        "Library/LaunchDaemons/svc.plist": true,
        "Library/QuickLook/Foo.qlgenerator": true,
        "Library/Audio/Plug-Ins/VST3/Foo.vst3": true,
        "Library/Application Support/CrashReporter/Foo Studio_36A3C032-E6E3-5B89-908A-9D3543CCE881.plist": true,
        "var/C/com.fooinc.foo": true,
        "var/T/.com.fooinc.foo.Rf8Vtr": true,
        "receipts/com.fooinc.foo.pkg.bom": true,
        "receipts/com.fooinc.foo.pkg.plist": true,
        "home/.foo": false,
        "home/.config/foo": false,
        "home/.local/share/Foo": false,
    ])
    #expect(findings.count == found.count)
    #expect(findings.first?.kind == .application)
    #expect(findings.allSatisfy { $0.size > 0 })
}

@Test func refusesToTrashDangerousPaths() {
    for path in ["/", "/Library", "/Users", "/Users/someone", "/Applications/"] {
        #expect(!Trash.isSafe(URL(filePath: path)), "\(path)")
    }
    #expect(Trash.isSafe(URL(filePath: "/Applications/Foo.app")))
    #expect(Trash.isSafe(URL(filePath: "/Users/someone/Library/Caches/com.fooinc.foo")))
}

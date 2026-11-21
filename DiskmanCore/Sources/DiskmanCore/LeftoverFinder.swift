import Foundation

/// Finds what an app leaves behind in the Library folders and a few places outside them.
public enum LeftoverFinder {
    /// Where apps keep files, relative to a Library folder. Add a row to cover a new place.
    public static let locations: [(path: String, kind: Finding.Kind)] = [
        ("Application Support", .applicationSupport),
        ("Application Support/CrashReporter", .logs),
        ("Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments", .preferences),
        ("Application Scripts", .containers),
        ("Containers", .containers),
        ("Group Containers", .containers),
        ("Caches", .caches),
        ("HTTPStorages", .caches),
        ("WebKit", .caches),
        ("Cookies", .preferences),
        ("Preferences", .preferences),
        ("Preferences/ByHost", .preferences),
        ("Logs", .logs),
        ("Logs/DiagnosticReports", .logs),
        ("Saved Application State", .savedState),
        ("Autosave Information", .savedState),
        ("LaunchAgents", .launchItems),
        ("LaunchDaemons", .launchItems),
        ("PrivilegedHelperTools", .launchItems),
        ("StartupItems", .launchItems),
        ("Internet Plug-Ins", .plugins),
        ("PreferencePanes", .plugins),
        ("Services", .plugins),
        ("QuickLook", .plugins),
        ("Spotlight", .plugins),
        ("Screen Savers", .plugins),
        ("Input Methods", .plugins),
        ("ColorPickers", .plugins),
        ("Audio/Plug-Ins/Components", .plugins),
        ("Audio/Plug-Ins/HAL", .plugins),
        ("Audio/Plug-Ins/VST", .plugins),
        ("Audio/Plug-Ins/VST3", .plugins),
        ("Mail/Bundles", .plugins),
        ("Extensions", .plugins),
    ]

    public static let defaultLibraries = [
        URL.homeDirectory.appending(path: "Library"),
        URL(filePath: "/Library"),
    ]

    /// Folders outside the Library whose entries are named like Library entries (by bundle ID or package ID).
    public static let defaultSystemFolders: [(url: URL, kind: Finding.Kind)] = [
        (darwinUserDirectory(_CS_DARWIN_USER_CACHE_DIR), .caches), // /private/var/folders/…/C
        (darwinUserDirectory(_CS_DARWIN_USER_TEMP_DIR), .caches), // /private/var/folders/…/T
        (URL(filePath: "/private/var/db/receipts"), .receipts),
    ].compactMap { url, kind in url.map { ($0, kind) } }

    /// Dot and XDG folders in the home folder. Command-line tools share these with apps,
    /// so only exact name matches count, and never as certain.
    public static let homeLocations: [(path: String, kind: Finding.Kind)] = [
        (".", .applicationSupport),
        (".config", .preferences),
        (".cache", .caches),
        (".local/share", .applicationSupport),
        (".local/state", .applicationSupport),
    ]

    /// Name suffixes after a bundle ID that are still the app's own files ("com.foo.app.plist").
    /// Any other suffix ("com.google.chrome.for.testing") may be another product, so it is uncertain.
    static let storageSuffixes: Set<String> = [
        "plist", "savedstate", "binarycookies", "shipit", "dua", "bom", "pkg", "log", "lock", "lockfile",
        "db", "sqlite", "json", "crash", "ips", "diag", "sfl2", "sfl3", "sfl4",
    ]

    /// The app bundle itself, followed by its leftovers.
    public static func findings(
        for app: InstalledApp,
        libraries: [URL] = defaultLibraries,
        systemFolders: [(url: URL, kind: Finding.Kind)] = defaultSystemFolders,
        home: URL = .homeDirectory
    ) async -> [Finding] {
        let teamID = app.teamID
        func match(_ url: URL, names: [String] = app.names) -> Match? {
            LeftoverFinder.matchReason(entry: url.lastPathComponent, identifiers: app.identifiers, names: names, teamID: teamID)
        }
        // "com.google.android.studio" keeps its data in ".../Google/AndroidStudio2026.1",
        // "Google Chrome" in ".../Google/Chrome".
        let vendor = app.bundleID.split(separator: ".").dropFirst().first.map { normalized(String($0)) } ?? ""
        let vendorNames = app.names + app.names.map(normalized)
            .filter { !vendor.isEmpty && $0.hasPrefix(vendor) && $0.count > vendor.count }
            .map { String($0.dropFirst(vendor.count)) }

        var found: [Found] = [(app.url, .application, true, nil)]
        let folders = libraries.flatMap { library in locations.map { (library.appending(path: $0.path), $0.kind) } } + systemFolders
        for (folder, kind) in folders {
            for entry in contents(folder) {
                let byContent = kind == .launchItems ? launchJobMatch(entry, app: app) : nil
                let hits = [match(entry), byContent].compactMap { $0 }
                if let hit = hits.first(where: \.certain) ?? hits.first {
                    found.append((entry, kind, hit.certain, hit.reason))
                } else if !vendor.isEmpty && normalized(entry.lastPathComponent) == vendor {
                    for child in contents(entry) {
                        if let hit = match(child, names: vendorNames) { found.append((child, kind, hit.certain, hit.reason)) }
                    }
                }
            }
        }
        let names = Set(app.names.map(normalized))
        for location in homeLocations {
            for entry in contents(home.appending(path: location.path)) {
                let name = entry.lastPathComponent
                guard location.path != "." || name.hasPrefix(".") else { continue }
                if names.contains(normalized(String(name.drop { $0 == "." }))) { found.append((entry, location.kind, false, .homeFolder)) }
            }
        }
        return deduplicated(found).map { Finding(url: $0.url, kind: $0.kind, isCertain: $0.certain, reason: $0.reason) }
    }

    /// Unreadable folders (no Full Disk Access) are skipped, not fatal.
    static func contents(_ url: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
    }

    /// Whether a file or folder name belongs to the app: nil if not, otherwise whether that is certain.
    // ponytail: name-based matching like AppCleaner; misses data filed under an unrelated name.
    // Upgrade path: per-app rules.
    static func match(entry: String, identifiers: [String], names: [String], teamID: String? = nil) -> Bool? {
        matchReason(entry: entry, identifiers: identifiers, names: names, teamID: teamID)?.certain
    }

    typealias Match = (certain: Bool, reason: Finding.Reason)
    typealias Found = (url: URL, kind: Finding.Kind, certain: Bool, reason: Finding.Reason?)

    /// `match`, with what the name was matched against.
    static func matchReason(entry: String, identifiers: [String], names: [String], teamID: String? = nil) -> Match? {
        let lowered = entry.lowercased()
        var result: Bool?
        // Component-wise only, and only for real reverse-DNS IDs, so "com.foo.app" never claims
        // "com.foo.application" and "foo" never claims "foo.other.vendor".
        for id in identifiers.map({ $0.lowercased() }) where lowered == id || id.contains(".") {
            for range in lowered.ranges(of: id) {
                let prefix = lowered[..<range.lowerBound], suffix = lowered[range.upperBound...]
                guard prefix.isEmpty || prefix.hasSuffix("."), suffix.isEmpty || suffix.hasPrefix(".") else { continue }
                // "TEAMID.com.foo.app" / "group.com.foo.app", then storage suffixes ("com.foo.app.plist").
                let knownPrefix = prefix.isEmpty || prefix == "group." || isTeamID(prefix.dropLast())
                let knownSuffix = suffix.split(separator: ".").allSatisfy { storageSuffixes.contains(String($0)) || isUUID($0) }
                // mkdtemp names from Chromium/Electron: ".com.foo.app.Rf8Vtr" (hidden) or "com.foo.app.5X6jZo".
                let token = suffix.dropFirst()
                let tempName = (prefix.isEmpty || prefix == ".") && token.count == 6
                    && token.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
                    && (prefix == "." || token.contains(where: \.isNumber))
                if (knownPrefix && knownSuffix) || tempName { return (true, .bundleID) }
                result = false
            }
        }
        if let result { return (result, .bundleID) }

        let entry = normalized(entry)
        let byName = names.map(normalized).contains { name in
            guard !name.isEmpty, entry.hasPrefix(name) else { return false }
            let rest = entry.dropFirst(name.count)
            guard let next = rest.first else { return true }
            // "foo.log", or a version/date suffix on a name long enough not to be a coincidence
            // ("androidstudio2026.1"), but never another word ("foobar").
            return (next == "." && !rest.dropFirst().contains(".")) || (name.count >= 4 && !next.isLetter && next != ".")
        }
        if byName { return (true, .name) }

        // "EQHXZ8M8AV.com.google.drivefs": same signer and vendor, but maybe another product.
        let vendorPrefix = identifiers.first?.split(separator: ".").prefix(2).joined(separator: ".").lowercased() ?? ""
        if let teamID, vendorPrefix.contains("."), lowered.hasPrefix(teamID.lowercased() + "." + vendorPrefix + ".") {
            return (false, .developer)
        }
        return nil
    }

    /// Whether a launchd job (by its plist content, whatever the file is called) runs the app or a part of it.
    /// BundleProgram is relative to the bundle named by AssociatedBundleIdentifiers, so that key decides.
    static func launchJobMatch(_ plist: URL, app: InstalledApp) -> Match? {
        guard plist.pathExtension == "plist", let data = try? Data(contentsOf: plist),
              let job = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        else { return nil }
        let ids = Set(app.identifiers.map { $0.lowercased() })
        let associated = (job["AssociatedBundleIdentifiers"] as? [String]) ?? [job["AssociatedBundleIdentifiers"] as? String].compactMap { $0 }
        let paths = ([job["Program"] as? String].compactMap { $0 } + (job["ProgramArguments"] as? [String] ?? []))
            .map { URL(filePath: $0).resolvingSymlinksInPath().path }
        let appPath = app.url.resolvingSymlinksInPath().path
        if associated.contains(where: { ids.contains($0.lowercased()) })
            || paths.contains(where: { $0 == appPath || $0.hasPrefix(appPath + "/") }) {
            return (true, .launchJob)
        }
        // Found through the file's content either way, so that is the reason, whatever the label matched.
        return (job["Label"] as? String).flatMap { match(entry: $0, identifiers: app.identifiers, names: []) }.map { ($0, .launchJob) }
    }

    /// No item twice, and no item inside another listed one. Paths are compared with symlinked folders
    /// resolved (/var → /private/var), but a symlinked entry itself is kept, never followed.
    static func deduplicated(_ found: [Found]) -> [Found] {
        var result: [Found] = []
        for var item in found {
            let parent = item.url.deletingLastPathComponent()
            if let real = realpath(parent.path, nil) {
                item.url = URL(filePath: String(cString: real), directoryHint: .isDirectory).appending(path: item.url.lastPathComponent)
                free(real)
            }
            if let index = result.firstIndex(where: { $0.url.path == item.url.path }) {
                // The certain hit explains the row; two uncertain ones keep the first reason.
                if item.certain && !result[index].certain { result[index].reason = item.reason }
                result[index].certain = result[index].certain || item.certain
            } else {
                result.append(item)
            }
        }
        return result.filter { item in !result.contains { item.url.path.hasPrefix($0.url.path + "/") } }
    }

    static func isTeamID(_ text: Substring) -> Bool {
        text.count == 10 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber) }
    }

    static func isUUID(_ text: Substring) -> Bool {
        UUID(uuidString: String(text)) != nil
    }

    static func darwinUserDirectory(_ name: Int32) -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        guard confstr(name, &buffer, buffer.count) > 0 else { return nil }
        let path = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return URL(filePath: path, directoryHint: .isDirectory)
    }

    /// "Android Studio", "android-studio" and "AndroidStudio" are the same name.
    static func normalized(_ name: String) -> String {
        name.lowercased().filter { !" -_".contains($0) }
    }
}

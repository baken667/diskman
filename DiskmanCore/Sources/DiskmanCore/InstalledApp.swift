import Foundation
import Security

public struct InstalledApp: Identifiable, Hashable, Sendable {
    public let url: URL
    public let name: String
    public let bundleID: String
    public let version: String?
    /// The app's bundle ID plus those of the helpers it embeds (login items, extensions, XPC services).
    public let identifiers: [String]
    /// Names the app may file its data under: the file name and CFBundleName ("Visual Studio Code" / "Code").
    public let names: [String]
    public var id: URL { url }

    /// Folders inside an app bundle that hold helpers with their own bundle IDs.
    private static let helperFolders = [
        "Library/LoginItems", "Library/LaunchServices", "Library/LaunchAgents", "Library/LaunchDaemons",
        "XPCServices", "PlugIns", "Helpers", "Frameworks",
    ]

    public init?(url: URL) {
        guard url.pathExtension == "app", let bundle = Bundle(url: url), let bundleID = bundle.bundleIdentifier else {
            return nil
        }
        self.url = url
        self.name = url.deletingPathExtension().lastPathComponent
        self.bundleID = bundleID
        self.version = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        self.names = Array(Set([name, bundle.infoDictionary?["CFBundleName"] as? String].compactMap { $0 })).sorted()

        // Only helpers from the same vendor ("com.foo."), so an embedded third-party
        // updater never drags another product's files into the list.
        func ids(in folder: URL) -> [String] {
            ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension != "framework" } // shared code, not a helper: its ID may be the vendor's
                .map { Bundle(url: $0)?.bundleIdentifier ?? $0.deletingPathExtension().lastPathComponent }
        }
        let contents = url.appending(path: "Contents")
        let vendorPrefix = bundleID.split(separator: ".").prefix(2).joined(separator: ".").lowercased() + "."
        let helpers = Self.helperFolders.flatMap { ids(in: contents.appending(path: $0)) }
            .filter { vendorPrefix.dropLast().contains(".") && $0.lowercased().hasPrefix(vendorPrefix) }
        // Chromium apps keep their helpers inside their framework, next to a shared updater
        // (GoogleUpdater), so only the app's own sub-IDs count there.
        let frameworkHelpers = ((try? FileManager.default.contentsOfDirectory(at: contents.appending(path: "Frameworks"), includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "framework" }
            .flatMap { ids(in: $0.appending(path: "Helpers").resolvingSymlinksInPath()) } // a symlink into Versions/Current
            .filter { $0.lowercased().hasPrefix(bundleID.lowercased() + ".") }
        self.identifiers = [bundleID] + Set(helpers + frameworkHelpers).subtracting([bundleID]).sorted()
    }

    /// The Team ID the app is signed with, read from its code signature (nil when unsigned or ad hoc).
    public var teamID: String? {
        var code: SecStaticCode?
        var info: CFDictionary?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecCodeCopySigningInformation(code, SecCSFlags(rawValue: kSecCSSigningInformation), &info) == errSecSuccess
        else { return nil }
        return (info as? [String: Any])?[kSecCodeInfoTeamIdentifier as String] as? String
    }

    /// Bought or downloaded from the Mac App Store, so installing it again is free and one click.
    public var isFromAppStore: Bool {
        FileManager.default.fileExists(atPath: url.appending(path: "Contents/_MASReceipt/receipt").path)
    }

    /// Where apps also end up when they are run without being installed. macOS guards these folders,
    /// so they are only worth listing once Full Disk Access is granted (otherwise each one prompts).
    public static let looseDirectories = [
        URL.homeDirectory.appending(path: "Downloads"),
        URL.homeDirectory.appending(path: "Desktop"),
    ]

    public static let defaultDirectories = [
        URL(filePath: "/Applications"),
        URL.homeDirectory.appending(path: "Applications"),
    ]

    /// Apps in the given folders and one level of subfolders (e.g. /Applications/Utilities).
    public static func installed(in directories: [URL] = defaultDirectories) async -> [InstalledApp] {
        let fm = FileManager.default
        func contents(_ url: URL) -> [URL] {
            (try? fm.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)) ?? []
        }
        return directories
            .flatMap { directory -> [URL] in
                let top = contents(directory)
                return top + top.filter { $0.pathExtension != "app" && $0.hasDirectoryPath }.flatMap(contents)
            }
            // A symlink is not an app we can remove: Safari's points into the sealed system volume,
            // others point at a bundle one folder down, which is listed on its own.
            .filter { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true }
            .compactMap(InstalledApp.init(url:))
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

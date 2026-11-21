import Foundation
import Security

/// Finds the newest published version on GitHub Releases and installs it over the running app.
public enum Updates {
    public struct Release: Sendable, Equatable {
        /// "1.2", without the tag's "v".
        public let version: String
        /// The zipped app to install in place; nil when the release has none (then the user downloads it).
        public let archive: URL?
    }

    public enum InstallError: Error { case unpacking, notOurs, notNewer }

    /// Where a person downloads the newest version.
    public static let page = URL(string: "https://github.com/baken667/diskman/releases/latest")!
    public static let api = URL(string: "https://api.github.com/repos/baken667/diskman/releases/latest")!
    /// Release files are only ever fetched from here.
    static let downloads = "https://github.com/baken667/diskman/releases/download/"
    /// What a genuine release is: this bundle ID, signed with this team's Developer ID certificate.
    static let requirement = """
        anchor apple generic and identifier "kz.bkn.diskman" \
        and certificate 1[field.1.2.840.113635.100.6.2.6] exists \
        and certificate leaf[field.1.2.840.113635.100.6.1.13] exists \
        and certificate leaf[subject.OU] = "D2WYW5VN3J"
        """

    /// The newest release, or nil when nothing is published yet.
    /// Drafts and prereleases never count as the latest release.
    public static func latest(session: URLSession = .shared) async throws -> Release? {
        var request = URLRequest(url: api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return try release(from: data)
        case 404: return nil
        default: throw URLError(.badServerResponse)
        }
    }

    static func release(from json: Data) throws -> Release {
        struct Payload: Decodable {
            struct Asset: Decodable { let name: String, browser_download_url: String }
            let tag_name: String
            let assets: [Asset]?
        }
        let payload = try JSONDecoder().decode(Payload.self, from: json)
        let tag = payload.tag_name
        let archive = payload.assets?
            .first { $0.name.hasSuffix("-arm64.zip") && $0.browser_download_url.hasPrefix(downloads) }
            .flatMap { URL(string: $0.browser_download_url) }
        return Release(version: tag.hasPrefix("v") ? String(tag.dropFirst()) : tag, archive: archive)
    }

    /// Compares dotted versions number by number: "1.10" is newer than "1.9", and "1.0" equals "1.0.0".
    public static func isNewer(_ version: String, than current: String) -> Bool {
        func numbers(_ string: String) -> [Int] {
            string.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
        }
        let a = numbers(version), b = numbers(current)
        for index in 0..<max(a.count, b.count) {
            let x = index < a.count ? a[index] : 0, y = index < b.count ? b[index] : 0
            if x != y { return x > y }
        }
        return false
    }

    /// Whether the app at `url` is a genuine release: intact, and signed by us with a Developer ID.
    public static func isGenuine(_ url: URL) -> Bool {
        var code: SecStaticCode?
        var requirement: SecRequirement?
        guard SecStaticCodeCreateWithPath(url as CFURL, [], &code) == errSecSuccess, let code,
              SecRequirementCreateWithString(Self.requirement as CFString, [], &requirement) == errSecSuccess, let requirement
        else { return false }
        let flags = SecCSFlags(rawValue: kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    /// Whether the app at `url` can replace itself: only a genuine release sitting somewhere we may write.
    /// A build from Xcode, or a copy run straight from the disk image, sends the user to the download page.
    public static func canInstall(over url: URL) -> Bool {
        isGenuine(url) && FileManager.default.isWritableFile(atPath: url.deletingLastPathComponent().path)
            && FileManager.default.isWritableFile(atPath: url.path)
    }

    /// Unpacks a downloaded release next to `app` and swaps it in. The archive is trusted only after its
    /// signature checks out and its version is newer, so a tampered or older download is never installed.
    public static func install(archive: URL, over app: URL) async throws {
        let fm = FileManager.default
        let staging = try fm.url(for: .itemReplacementDirectory, in: .userDomainMask, appropriateFor: app, create: true)
        defer { try? fm.removeItem(at: staging) }

        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, staging.path]
        try ditto.run()
        ditto.waitUntilExit()
        let unpacked = staging.appending(path: "diskman.app")   // the archive's name, whatever the installed copy is called
        guard ditto.terminationStatus == 0, fm.fileExists(atPath: unpacked.path) else { throw InstallError.unpacking }

        guard isGenuine(unpacked) else { throw InstallError.notOurs }
        func version(_ bundle: URL) -> String {
            Bundle(url: bundle)?.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        }
        guard isNewer(version(unpacked), than: version(app)) else { throw InstallError.notNewer }

        // Like everything else here, the old version goes to the Trash rather than away for good.
        let previous = "diskman (previous version).app"
        _ = try fm.replaceItemAt(app, withItemAt: unpacked, backupItemName: previous, options: .withoutDeletingBackupItem)
        let backup = app.deletingLastPathComponent().appending(path: previous)
        if (try? fm.trashItem(at: backup, resultingItemURL: nil)) == nil { try? fm.removeItem(at: backup) }
    }
}

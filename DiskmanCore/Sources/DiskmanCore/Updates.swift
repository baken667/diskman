import Foundation

/// Looks up the newest published version on GitHub Releases. Nothing is downloaded or installed:
/// frontends show the version and send the user to the release page.
public enum Updates {
    /// Where a person downloads the newest version.
    public static let page = URL(string: "https://github.com/baken667/diskman/releases/latest")!
    static let api = URL(string: "https://api.github.com/repos/baken667/diskman/releases/latest")!

    /// The newest release's version ("1.2", without the tag's "v"), or nil when nothing is published yet.
    /// Drafts and prereleases never count as the latest release.
    public static func latestVersion(session: URLSession = .shared) async throws -> String? {
        var request = URLRequest(url: api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        switch (response as? HTTPURLResponse)?.statusCode {
        case 200: return try version(fromRelease: data)
        case 404: return nil
        default: throw URLError(.badServerResponse)
        }
    }

    static func version(fromRelease json: Data) throws -> String {
        struct Release: Decodable { let tag_name: String }
        let tag = try JSONDecoder().decode(Release.self, from: json).tag_name
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
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
}

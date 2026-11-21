import Foundation
import Testing
@testable import DiskmanCore

@Test func comparesVersionsNumberByNumber() {
    for (new, old) in [("1.1", "1.0"), ("1.10", "1.9"), ("2.0", "1.99.9"), ("1.0.1", "1.0")] {
        #expect(Updates.isNewer(new, than: old), "\(new) > \(old)")
        #expect(!Updates.isNewer(old, than: new), "\(old) < \(new)")
    }
    #expect(!Updates.isNewer("1.0", than: "1.0.0") && !Updates.isNewer("1.0.0", than: "1.0"))
    #expect(!Updates.isNewer("", than: "1.0") && !Updates.isNewer("garbage", than: "1.0"))
}

@Test func readsAReleaseFromGitHub() throws {
    func release(_ json: String) throws -> Updates.Release { try Updates.release(from: Data(json.utf8)) }
    let base = "https://github.com/baken667/diskman/releases/download/v1.2.3"
    let full = try release("""
        {"tag_name": "v1.2.3", "assets": [
          {"name": "diskman-v1.2.3-arm64.dmg", "browser_download_url": "\(base)/diskman-v1.2.3-arm64.dmg"},
          {"name": "diskman-v1.2.3-arm64.zip", "browser_download_url": "\(base)/diskman-v1.2.3-arm64.zip"}]}
        """)
    #expect(full == Updates.Release(version: "1.2.3", archive: URL(string: "\(base)/diskman-v1.2.3-arm64.zip")))
    // No zip (releases before in-place updates), or no assets at all: the user downloads it instead.
    #expect(try release(#"{"tag_name": "2.0"}"#) == Updates.Release(version: "2.0", archive: nil))
    #expect(try release(#"{"tag_name": "v2.0", "assets": [{"name": "a.dmg", "browser_download_url": "x"}]}"#).archive == nil)
    // An archive hosted anywhere but this repository's releases is ignored.
    #expect(try release(#"{"tag_name": "v2.0", "assets": [{"name": "diskman-v2.0-arm64.zip", "browser_download_url": "https://example.com/diskman-v2.0-arm64.zip"}]}"#).archive == nil)
    #expect(throws: (any Error).self) { try release("{}") }
}

@Test func onlyGenuineReleasesCanBeInstalled() async throws {
    let fm = FileManager.default
    let root = fm.temporaryDirectory.appending(path: UUID().uuidString)
    defer { try? fm.removeItem(at: root) }
    let app = root.appending(path: "diskman.app")
    try fm.createDirectory(at: app.appending(path: "Contents"), withIntermediateDirectories: true)
    try Data("<plist><dict><key>CFBundleIdentifier</key><string>kz.bkn.diskman</string></dict></plist>".utf8)
        .write(to: app.appending(path: "Contents/Info.plist"))
    #expect(!Updates.isGenuine(app) && !Updates.canInstall(over: app))   // right bundle ID, no signature

    // An unsigned app in the archive is refused, and the installed one is left as it was.
    let zip = root.appending(path: "update.zip")
    let ditto = Process()
    ditto.executableURL = URL(filePath: "/usr/bin/ditto")
    ditto.arguments = ["-c", "-k", "--keepParent", app.path, zip.path]
    try ditto.run()
    ditto.waitUntilExit()
    let installed = root.appending(path: "Installed/diskman.app")
    try fm.createDirectory(at: installed, withIntermediateDirectories: true)
    try Data("old".utf8).write(to: installed.appending(path: "marker"))
    await #expect(throws: Updates.InstallError.notOurs) { try await Updates.install(archive: zip, over: installed) }
    #expect(fm.fileExists(atPath: installed.appending(path: "marker").path))
}

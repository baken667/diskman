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

@Test func readsTheVersionFromAReleaseTag() throws {
    #expect(try Updates.version(fromRelease: Data(#"{"tag_name": "v1.2.3", "html_url": "https://example.com"}"#.utf8)) == "1.2.3")
    #expect(try Updates.version(fromRelease: Data(#"{"tag_name": "2.0"}"#.utf8)) == "2.0")
    #expect(throws: (any Error).self) { try Updates.version(fromRelease: Data("{}".utf8)) }
}

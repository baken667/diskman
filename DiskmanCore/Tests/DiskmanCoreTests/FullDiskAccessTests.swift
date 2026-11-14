import Foundation
import Testing
@testable import DiskmanCore

@Test func fullDiskAccessProbe() {
    #expect(FullDiskAccess.isGranted(probing: ["/nonexistent-\(UUID())", NSTemporaryDirectory()]))
    #expect(!FullDiskAccess.isGranted(probing: ["/nonexistent-\(UUID())"]))
    #expect(!FullDiskAccess.isGranted(probing: []))
}

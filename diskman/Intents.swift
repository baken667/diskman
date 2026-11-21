import AppIntents
import DiskmanCore

/// "How much can diskman free?" for Shortcuts and Spotlight. Read-only on purpose: removing anything stays
/// behind the preview in the app's window.
struct ReclaimableSpaceIntent: AppIntent {
    static let title: LocalizedStringResource = "Check What diskman Can Clean"
    static let description = IntentDescription("Measures the caches and logs that are safe to remove. Nothing is removed.")

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        // The same selection the app starts with: safe rules only, and none whose app is running.
        var bytes: Int64 = 0
        for result in await Cleaner.scan() where result.rule.isSafe {
            if await RunningApps.running(of: result.rule.appBundleIDs).isEmpty { bytes += result.removable.reduce(0) { $0 + $1.size } }
        }
        let size = bytes.formatted(.byteCount(style: .file))
        return .result(value: size, dialog: "diskman can move \(size) of caches and logs to the Trash.")
    }
}

struct DiskmanShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: ReclaimableSpaceIntent(), phrases: ["Check what \(.applicationName) can clean"],
                    shortTitle: "Check Cleanable Space", systemImageName: "sparkles")
    }
}

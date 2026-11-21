import AppKit

/// Which of the given apps are open right now. Their data is left alone until they quit.
public enum RunningApps {
    public struct App: Sendable, Hashable {
        public let bundleID: String
        public let name: String
    }

    /// Extensions and XPC services the system starts on its own do not count: the user cannot quit them.
    @MainActor public static func running(of bundleIDs: [String]) -> [App] {
        bundleIDs.compactMap { id in
            NSRunningApplication.runningApplications(withBundleIdentifier: id)
                .first { $0.activationPolicy != .prohibited }
                .map { App(bundleID: id, name: $0.localizedName ?? id) }
        }
    }

    /// Asks the app to quit, as its own Quit command would: it may still ask to save. Never forced.
    @MainActor public static func quit(_ app: App) {
        for instance in NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID) where instance.activationPolicy != .prohibited {
            instance.terminate()
        }
    }
}

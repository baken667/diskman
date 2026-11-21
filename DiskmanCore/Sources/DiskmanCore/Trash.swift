import Foundation

/// The only way anything is removed: items go to the Trash, never deleted outright.
public enum Trash {
    public struct Failure: Identifiable, Sendable {
        public let url: URL
        public let message: String
        public var id: URL { url }
    }

    /// Moves the items to the Trash and returns the ones that could not be moved.
    public static func move(_ urls: [URL]) async -> [Failure] {
        urls.compactMap { url in
            do {
                guard isSafe(url) else { throw CocoaError(.fileWriteNoPermission) }
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                return nil
            } catch {
                return Failure(url: url, message: error.localizedDescription)
            }
        }
    }

    /// For what `move` cannot do as the current user (apps installed by a package, items in /Library):
    /// asks Finder to move the items, and Finder asks for an administrator password, as it does when the
    /// user drags them to the Trash by hand. Returns the items that are still in place afterwards.
    public static func moveWithFinder(_ urls: [URL]) async -> [Failure] {
        let fm = FileManager.default
        // The item itself, link or not: `fileExists` would follow a symlink and call a dangling one gone.
        func isThere(_ url: URL) -> Bool { (try? fm.attributesOfItem(atPath: url.path)) != nil }
        func isLink(_ url: URL) -> Bool { (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true }
        // Finder may resolve a symlink and trash what it points to, which nobody was shown. Those stay.
        let refused = urls.filter { isThere($0) && (!isSafe($0) || isLink($0)) }
            .map { Failure(url: $0, message: CocoaError(.fileWriteNoPermission).localizedDescription) }
        let wanted = urls.filter { isThere($0) && isSafe($0) && !isLink($0) }
        guard !wanted.isEmpty else { return refused }

        // Paths travel as arguments, never inside the script text, so no name can change what it does.
        let script = """
            on run argv
                set theItems to {}
                repeat with thePath in argv
                    set end of theItems to POSIX file (contents of thePath)
                end repeat
                with timeout of 86400 seconds
                    tell application "Finder" to delete theItems
                end timeout
            end run
            """
        let osascript = Process(), errors = Pipe()
        osascript.executableURL = URL(filePath: "/usr/bin/osascript")
        osascript.arguments = ["-e", script] + wanted.map(\.path)
        osascript.standardOutput = FileHandle.nullDevice
        osascript.standardError = errors
        var message = CocoaError(.fileWriteNoPermission).localizedDescription
        do {
            try osascript.run()
            let output = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            osascript.waitUntilExit()
            if osascript.terminationStatus != 0, !output.isEmpty { message = output.trimmingCharacters(in: .whitespacesAndNewlines) }
        } catch {
            message = error.localizedDescription
        }
        // Whatever Finder reported, the truth is what is still there.
        return refused + wanted.filter(isThere).map { Failure(url: $0, message: message) }
    }

    /// Last line of defence against a bad caller or a bad rule: never trash a volume, a top-level folder
    /// (/Library, /Users, ...), a home folder, or the folders everything else lives in (~/Documents,
    /// ~/Library, ~/Library/Caches, /Library/Application Support, ...). Dot folders in a home are fine.
    static func isSafe(_ url: URL) -> Bool {
        let parts = url.standardizedFileURL.pathComponents   // ["/", "Users", "me", "Library", ...]
        guard parts.count > 2 else { return false }
        switch parts[1] {
        case "Volumes", "Library", "System": return parts.count > 3
        case "Users":
            guard parts.count > 3 else { return false }   // a home folder
            if parts.count == 4 { return parts[3].hasPrefix(".") }
            return parts[3] != "Library" || parts.count > 5
        default: return true
        }
    }
}

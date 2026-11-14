import Darwin
import Foundation

/// Full Disk Access detection. Opening a TCC-protected path both tells us whether
/// access is granted and makes macOS list the app under Privacy & Security › Full Disk Access.
public enum FullDiskAccess {
    /// Protected locations present on (nearly) every Mac. TCC.db exists on every install.
    public static var probePaths: [String] {
        let home = NSHomeDirectory()
        return ["\(home)/Library/Application Support/com.apple.TCC/TCC.db",
                "\(home)/Library/Safari",
                "\(home)/Library/Containers/com.apple.stocks",
                "\(home)/Library/Mail"]
    }

    /// True if any probe path can be opened. Missing paths (ENOENT) are skipped; EPERM means denied.
    public static func isGranted(probing paths: [String] = probePaths) -> Bool {
        for path in paths {
            let fd = open(path, O_RDONLY)   // works for files and directories
            if fd >= 0 { close(fd); return true }
        }
        return false
    }
}

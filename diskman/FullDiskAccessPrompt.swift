import AppKit
import DiskmanCore
import SwiftUI

@MainActor @Observable
final class FullDiskAccessModel {
    var isGranted = FullDiskAccess.isGranted()   // probing at launch also lists the app in System Settings
    /// "Continue Without" is an answer, not a pause: it holds across launches. Settings still offers access.
    var isDismissed = UserDefaults.standard.bool(forKey: "fullDiskAccessDismissed") {
        didSet { UserDefaults.standard.set(isDismissed, forKey: "fullDiskAccessDismissed") }
    }

    func refresh() { isGranted = FullDiskAccess.isGranted() }

    func openSettings() {
        let urls = ["x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_AllFiles",
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"]
        for url in urls where NSWorkspace.shared.open(URL(string: url)!) { return }
    }

    /// Full Disk Access often only applies to a freshly launched process.
    func relaunch() { relaunchApp() }
}

/// Non-blocking banner shown above the detail area while access is missing.
struct FullDiskAccessBanner: View {
    var model: FullDiskAccessModel
    /// Opens the window that lists everything the app reads.
    let showWhatIsRead: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "lock.shield").font(.title2).foregroundStyle(.tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text("Allow Full Disk Access").font(.headline)
                Text("Without it, diskman can't see leftovers in protected folders such as other apps' containers. Everything you remove still only goes to the Trash.")
                    .font(.subheadline).foregroundStyle(.secondary)
                HStack {
                    Button("Open System Settings") { model.openSettings() }.buttonStyle(.borderedProminent)
                    Button("Relaunch") { model.relaunch() }
                        .help("Restart diskman after enabling access so it takes effect.")
                    Button("Continue Without") { withAnimation { model.isDismissed = true } }
                    Button("What does diskman read?", action: showWhatIsRead).buttonStyle(.link)
                }
                .controlSize(.small).padding(.top, 4)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
    }
}

/// Settings scene content so the user can come back to Full Disk Access later.
struct SettingsView: View {
    var model: FullDiskAccessModel
    var updates: UpdateModel

    var body: some View {
        Form {
            LabeledContent("Full Disk Access") {
                Label(model.isGranted ? "Allowed" : "Not allowed",
                      systemImage: model.isGranted ? "checkmark.circle.fill" : "xmark.circle")
                    .foregroundStyle(model.isGranted ? .green : .secondary)
            }
            if !model.isGranted {
                Button("Open System Settings") { model.openSettings() }
                Button("Relaunch") { model.relaunch() }
            }
            Text("Lets diskman find leftovers in protected folders. Everything you remove still only goes to the Trash.")
                .font(.callout).foregroundStyle(.secondary)
            UpdateSettings(model: updates)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
}

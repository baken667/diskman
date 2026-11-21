import DiskmanCore
import SwiftUI

/// Asks GitHub whether a newer version is out and, on the user's click, installs it and restarts.
@MainActor @Observable
final class UpdateModel {
    enum State: Equatable { case unknown, checking, upToDate, available(Updates.Release), installing(Updates.Release), failed }

    static let automaticKey = "checksForUpdatesAutomatically"
    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    /// False for a build from Xcode or a copy that cannot be replaced: those get a link to the download page.
    static let canInstall = Updates.canInstall(over: Bundle.main.bundleURL)

    var state = State.unknown
    /// The in-place update did not work out; the banner then offers the download page instead.
    var installFailed = false

    var available: Updates.Release? {
        switch state {
        case .available(let release), .installing(let release): release
        default: nil
        }
    }

    /// The check at launch, unless the user turned it off in Settings.
    func checkAtLaunch() async {
        guard state == .unknown, UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true else { return }
        await check()
    }

    func check() async {
        switch state {
        case .checking, .installing: return
        default: break
        }
        state = .checking
        do {
            let latest = try await Updates.latest()
            state = latest.flatMap { Updates.isNewer($0.version, than: Self.currentVersion) ? .available($0) : nil } ?? .upToDate
        } catch {
            // A window closed mid-check cancels it; the next window tries again.
            state = Task.isCancelled ? .unknown : .failed
        }
    }

    /// Whether the banner's button installs the release itself rather than opening the download page.
    func installsInPlace(_ release: Updates.Release) -> Bool {
        Self.canInstall && release.archive != nil && !installFailed
    }

    /// Downloads the release, checks it is really ours, swaps it in and restarts into it.
    func install(_ release: Updates.Release) {
        guard state == .available(release), let archive = release.archive, installsInPlace(release) else {
            return openDownloadPage()
        }
        state = .installing(release)
        Task {
            do {
                let (file, _) = try await URLSession.shared.download(from: archive)
                defer { try? FileManager.default.removeItem(at: file) }
                try await Updates.install(archive: file, over: Bundle.main.bundleURL)
                relaunchApp()
            } catch {
                installFailed = true
                state = .available(release)
            }
        }
    }

    func openDownloadPage() { NSWorkspace.shared.open(Updates.page) }
}

/// Starts the app again from the same place once this process has quit.
@MainActor func relaunchApp() {
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/bin/sh")
    task.arguments = ["-c", "sleep 0.5; open -n \"$0\"", Bundle.main.bundlePath]
    try? task.run()
    NSApp.terminate(nil)
}

/// Shown under the sidebar while a newer version is out.
struct UpdateBanner: View {
    let release: Updates.Release
    let model: UpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Version \(release.version) is available").font(.subheadline.weight(.medium))
            if model.installFailed {
                Text("It could not be installed automatically.").font(.caption).foregroundStyle(.secondary)
            }
            if model.state == .installing(release) {
                ProgressView { Text("Updating…").font(.caption) }.controlSize(.small)
            } else if model.installsInPlace(release) {
                Button("Update and Restart") { model.install(release) }.controlSize(.small)
            } else {
                Button("Download") { model.openDownloadPage() }.controlSize(.small)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .accessibilityElement(children: .contain)
    }
}

/// The Updates section of the Settings window.
struct UpdateSettings: View {
    let model: UpdateModel
    @AppStorage(UpdateModel.automaticKey) private var isAutomatic = true

    var body: some View {
        Section("Updates") {
            LabeledContent("Version \(UpdateModel.currentVersion)") {
                switch model.state {
                case .unknown: EmptyView()
                case .checking: ProgressView().controlSize(.small)
                case .upToDate: Text("Up to date").foregroundStyle(.secondary)
                case .available(let release): Text("Version \(release.version) is available")
                case .installing: Text("Updating…").foregroundStyle(.secondary)
                case .failed: Text("Could not check").foregroundStyle(.secondary)
                }
            }
            Toggle("Check for updates when diskman opens", isOn: $isAutomatic)
            HStack {
                Button("Check Now") { Task { await model.check() } }.disabled(model.state == .checking)
                if model.available != nil { Button("Download") { model.openDownloadPage() } }
            }
            Text("Asks GitHub for the latest release number. Nothing about you or your disk is sent. An update is installed only when you ask for it.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

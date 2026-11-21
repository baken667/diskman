import DiskmanCore
import SwiftUI

/// Asks GitHub whether a newer version is out. It only ever tells the user; downloading is theirs to do.
// ponytail: no in-place install. Adopt Sparkle if people ask for one-click updates.
@MainActor @Observable
final class UpdateModel {
    enum State: Equatable { case unknown, checking, upToDate, available(String), failed }

    static let automaticKey = "checksForUpdatesAutomatically"
    static let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"

    var state = State.unknown

    var availableVersion: String? {
        if case .available(let version) = state { version } else { nil }
    }

    /// The check at launch, unless the user turned it off in Settings.
    func checkAtLaunch() async {
        guard state == .unknown, UserDefaults.standard.object(forKey: Self.automaticKey) as? Bool ?? true else { return }
        await check()
    }

    func check() async {
        guard state != .checking else { return }
        state = .checking
        do {
            let latest = try await Updates.latestVersion()
            state = latest.flatMap { Updates.isNewer($0, than: Self.currentVersion) ? .available($0) : nil } ?? .upToDate
        } catch {
            // A window closed mid-check cancels it; the next window tries again.
            state = Task.isCancelled ? .unknown : .failed
        }
    }

    func openDownloadPage() { NSWorkspace.shared.open(Updates.page) }
}

/// Shown under the sidebar while a newer version is out.
struct UpdateBanner: View {
    let version: String
    let model: UpdateModel

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Version \(version) is available").font(.subheadline.weight(.medium))
            Button("Download") { model.openDownloadPage() }.controlSize(.small)
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
                case .available(let version): Text("Version \(version) is available")
                case .failed: Text("Could not check").foregroundStyle(.secondary)
                }
            }
            Toggle("Check for updates when diskman opens", isOn: $isAutomatic)
            HStack {
                Button("Check Now") { Task { await model.check() } }.disabled(model.state == .checking)
                if model.availableVersion != nil { Button("Download") { model.openDownloadPage() } }
            }
            Text("Asks GitHub for the latest release number. Nothing about you or your disk is sent.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

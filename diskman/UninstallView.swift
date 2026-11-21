import DiskmanCore
import SwiftUI

/// Preview of everything an app keeps on disk, with a button to move the checked items to the Trash.
struct UninstallView: View {
    let app: InstalledApp
    /// Another copy of this app (same bundle ID) is on the Mac, so its data is not this copy's to take.
    let hasTwin: Bool
    /// Called after every move with the items that stayed behind and what was moved; the parent reloads
    /// and reports both, since this view is dropped as soon as its app is gone.
    let onRemoved: ([Trash.Failure], Receipt?) async -> Void

    @State private var findings: [Finding]?
    @State private var checked: Set<Finding.ID> = []
    /// Items only an administrator can remove (apps installed by a package, most of /Library).
    /// Finder moves those, after asking for a password.
    @State private var locked: Set<Finding.ID> = []
    /// Read from the code signature once the list is up; nil until then and for unsigned apps.
    @State private var teamID: String?
    @State private var running: [RunningApps.App] = []
    @State private var isWorking = false
    @State private var isConfirming = false

    private var isRunning: Bool { !running.isEmpty }
    private var checkedSize: Int64 {
        (findings ?? []).filter { checked.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            identity
            if hasTwin {
                Label("Another copy of this app is on your Mac, so its data is left unticked.", systemImage: "square.on.square")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .padding(.horizontal)
                    .padding(.bottom, 8)
            }
            Divider()
            if let findings {
                List(findings) { finding in
                    Toggle(isOn: binding(for: finding)) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text(finding.kind.label)
                                Text(verbatim: finding.url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                notes(for: finding)
                            }
                            Spacer()
                            Text(finding.size, format: .byteCount(style: .file))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .help(finding.url.path)
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) }
                        Button("Copy Path") { copyToPasteboard(finding.url.path) }
                    }
                }
                .disabled(isWorking)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                VStack(alignment: .leading) {
                    if let blocker = running.first {
                        HStack {
                            Text("Quit \(blocker.name) before removing it.").foregroundStyle(.orange)
                            Button("Quit \(blocker.name)") { RunningApps.quit(blocker) }.controlSize(.small)
                        }
                    }
                    Text("Items are moved to the Trash, nothing is deleted permanently. Empty the Trash to free the space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // No default-action shortcut: Return in the sidebar must never start an uninstall.
                Button("Move \(checkedSize.formatted(.byteCount(style: .file))) to Trash", role: .destructive) { isConfirming = true }
                    .disabled(checked.isEmpty || isRunning || isWorking)
            }
            .padding()
        }
        .navigationTitle(Text(verbatim: app.name))
        .navigationSubtitle(Text(verbatim: app.version ?? ""))
        .task {
            let found = await LeftoverFinder.findings(for: app)
            findings = found
            // For the bundle the question is whether it is writable: its folder is, even when root owns the app.
            let fm = FileManager.default
            locked = Set(found.filter {
                $0.kind == .application ? !fm.isWritableFile(atPath: $0.url.path) : !fm.isDeletableFile(atPath: $0.url.path)
            }.map(\.id))
            // With a twin around, only the bundle is ticked: the leftovers belong to the copy that stays too.
            checked = Set(found.filter { $0.isCertain && (!hasTwin || $0.kind == .application) }.map(\.id))
            teamID = app.teamID
        }
        .task {
            // ponytail: polls once a second; observe NSWorkspace launch/terminate notifications if this ever matters.
            while !Task.isCancelled {
                // Helpers count too: a menu-bar agent or login item keeps writing to the app's data.
                let now = RunningApps.running(of: app.identifiers)
                if now != running { running = now }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog("Move \(checkedSize.formatted(.byteCount(style: .file))) to Trash?", isPresented: $isConfirming) {
            Button("Move to Trash", role: .destructive, action: moveToTrash)
        } message: {
            Text("Items are moved to the Trash, nothing is deleted permanently. Empty the Trash to free the space.")
        }
    }

    /// Who the app is and how easily it comes back, before anything is removed.
    private var identity: some View {
        HStack(spacing: 16) {
            LabeledContent("Bundle ID") { Text(verbatim: app.bundleID).textSelection(.enabled) }
            if let teamID {
                LabeledContent("Team ID") { Text(verbatim: teamID).textSelection(.enabled) }
            }
            if app.isFromAppStore {
                Label("From the App Store: you can install it again there", systemImage: "arrow.down.app")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .labeledContentStyle(.inline)
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    /// Why the row is listed, and anything the user should know before ticking it.
    @ViewBuilder private func notes(for finding: Finding) -> some View {
        HStack(spacing: 6) {
            if let reason = finding.reason { Text(reason.label) }
            if !finding.isCertain { Text("Not sure") }
            if locked.contains(finding.id) { Text("Asks for an administrator password") }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private func binding(for finding: Finding) -> Binding<Bool> {
        Binding {
            checked.contains(finding.id)
        } set: { isOn in
            if isOn { checked.insert(finding.id) } else { checked.remove(finding.id) }
        }
    }

    private func moveToTrash() {
        guard !isWorking, !isRunning else { return }   // the app may have launched while the dialog was up
        let chosen = (findings ?? []).filter { checked.contains($0.id) }
        let bundles = chosen.filter { $0.kind == .application }.map(\.url)
        let leftovers = chosen.filter { $0.kind != .application }.map(\.url)
        isWorking = true
        Task {
            // The app goes first: if it cannot be moved (SIP, a refused password), its data stays where it is.
            var failed = await Self.move(bundles)
            let appStayed = !failed.isEmpty
            if !appStayed { failed = await Self.move(leftovers) }
            let stuck = appStayed ? Set(chosen.map(\.url)) : Set(failed.map(\.url))
            let moved = chosen.filter { !stuck.contains($0.url) }
            findings?.removeAll { finding in moved.contains { $0.url == finding.url } }
            checked.subtract(moved.map(\.id))
            isWorking = false
            await onRemoved(failed, moved.isEmpty ? nil : Receipt(count: moved.count, bytes: moved.reduce(0) { $0 + $1.size }))
        }
    }
}

extension UninstallView {
    /// Moves what the user may move directly, then hands the rest to Finder in one go, so there is at most
    /// one password prompt per step.
    nonisolated static func move(_ urls: [URL]) async -> [Trash.Failure] {
        let failed = await Trash.move(urls)
        return failed.isEmpty ? [] : await Trash.moveWithFinder(failed.map(\.url))
    }
}

/// "Label: value" on one line, for the strip above the list.
private struct InlineLabeledContentStyle: LabeledContentStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 4) {
            configuration.label
            configuration.content.foregroundStyle(.primary)
        }
    }
}

private extension LabeledContentStyle where Self == InlineLabeledContentStyle {
    static var inline: InlineLabeledContentStyle { InlineLabeledContentStyle() }
}

extension Finding.Reason {
    /// User-facing text lives in the app's string catalog; the core stays free of UI text.
    var label: LocalizedStringResource {
        switch self {
        case .bundleID: "Named after the app's ID"
        case .name: "Named after the app"
        case .developer: "Same developer"
        case .launchJob: "Starts this app in the background"
        case .homeFolder: "Folder with the app's name"
        }
    }
}

extension Finding.Kind {
    /// User-facing names live in the app's string catalog; the core stays free of UI text.
    var label: LocalizedStringResource {
        switch self {
        case .application: "Application"
        case .applicationSupport: "Application Support"
        case .caches: "Caches"
        case .containers: "Containers"
        case .preferences: "Preferences"
        case .logs: "Logs"
        case .savedState: "Saved State"
        case .launchItems: "Launch Items"
        case .plugins: "Plug-ins"
        case .receipts: "Installer Receipts"
        }
    }
}

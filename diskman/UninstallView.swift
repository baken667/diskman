import DiskmanCore
import SwiftUI

/// Preview of everything an app keeps on disk, with a button to move the checked items to the Trash.
struct UninstallView: View {
    let app: InstalledApp
    /// Called after every move with the items that stayed behind; the parent reloads and reports them,
    /// since this view is dropped as soon as its app is gone.
    let onRemoved: ([Trash.Failure]) async -> Void

    @State private var findings: [Finding]?
    @State private var checked: Set<Finding.ID> = []
    /// Items only an administrator can remove (most of /Library): never preselected, since moving them would just fail.
    @State private var locked: Set<Finding.ID> = []
    @State private var isRunning = false
    @State private var isWorking = false
    @State private var isConfirming = false

    private var checkedSize: Int64 {
        (findings ?? []).filter { checked.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let findings {
                List(findings) { finding in
                    Toggle(isOn: binding(for: finding)) {
                        HStack {
                            VStack(alignment: .leading) {
                                HStack {
                                    Text(finding.kind.label)
                                    if locked.contains(finding.id) {
                                        Text("Needs administrator rights. Remove it in Finder.").font(.caption).foregroundStyle(.secondary)
                                    } else if !finding.isCertain {
                                        Text("Not sure").font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Text(verbatim: finding.url.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            Spacer()
                            Text(finding.size, format: .byteCount(style: .file))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(locked.contains(finding.id))
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) }
                    }
                }
                .disabled(isWorking)
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                VStack(alignment: .leading) {
                    if isRunning {
                        Text("Quit \(app.name) before removing it.").foregroundStyle(.orange)
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
            // The app bundle is exempt: its folder is writable even when the bundle is root-owned, so the
            // check says nothing about it, and a failed move of the app already leaves everything in place.
            locked = Set(found.filter { $0.kind != .application && !FileManager.default.isDeletableFile(atPath: $0.url.path) }.map(\.id))
            checked = Set(found.filter(\.isCertain).map(\.id)).subtracting(locked)
        }
        .task {
            // ponytail: polls once a second; observe NSWorkspace launch/terminate notifications if this ever matters.
            while !Task.isCancelled {
                // Helpers count too: a menu-bar agent or login item keeps writing to the app's data. Not the
                // ones the user cannot quit, though: extensions and XPC services the system starts on its own.
                isRunning = app.identifiers.contains { id in
                    NSRunningApplication.runningApplications(withBundleIdentifier: id).contains { $0.activationPolicy != .prohibited }
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog("Move \(checkedSize.formatted(.byteCount(style: .file))) to Trash?", isPresented: $isConfirming) {
            Button("Move to Trash", role: .destructive, action: moveToTrash)
        } message: {
            Text("Items are moved to the Trash, nothing is deleted permanently. Empty the Trash to free the space.")
        }
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
            // The app goes first: if it cannot be moved (SIP, root-owned), its data stays where it is.
            var failed = await Trash.move(bundles)
            let appStayed = !failed.isEmpty
            if !appStayed { failed = await Trash.move(leftovers) }
            let stuck = appStayed ? Set(chosen.map(\.url)) : Set(failed.map(\.url))
            let moved = Set(chosen.map(\.url)).subtracting(stuck)
            findings?.removeAll { moved.contains($0.url) }
            checked.subtract(moved)
            isWorking = false
            await onRemoved(failed)
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

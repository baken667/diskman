import DiskmanCore
import SwiftUI

/// Preview of everything an app keeps on disk, with a button to move the checked items to the Trash.
struct UninstallView: View {
    let app: InstalledApp
    let onRemoved: () async -> Void

    @State private var findings: [Finding]?
    @State private var checked: Set<Finding.ID> = []
    @State private var failures: [Trash.Failure] = []
    @State private var isRunning = false

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
                                    if !finding.isCertain {
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
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) }
                    }
                }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                VStack(alignment: .leading) {
                    if isRunning {
                        Text("Quit \(app.name) before removing it.").foregroundStyle(.orange)
                    }
                    Text("Items are moved to the Trash. Nothing is deleted permanently.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Move \(checkedSize.formatted(.byteCount(style: .file))) to Trash", role: .destructive, action: moveToTrash)
                    .disabled(checked.isEmpty || isRunning)
                    .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .navigationTitle(Text(verbatim: app.name))
        .navigationSubtitle(Text(verbatim: app.version ?? ""))
        .task {
            let found = await LeftoverFinder.findings(for: app)
            findings = found
            checked = Set(found.filter(\.isCertain).map(\.id))
        }
        .task {
            // ponytail: polls once a second; observe NSWorkspace launch/terminate notifications if this ever matters.
            while !Task.isCancelled {
                isRunning = !NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).isEmpty
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .alert("Some items could not be moved to the Trash", isPresented: .constant(!failures.isEmpty)) {
            Button("OK") { failures = [] }
        } message: {
            Text(verbatim: failures.map { "\($0.url.path)\n\($0.message)" }.joined(separator: "\n\n"))
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
        let urls = (findings ?? []).filter { checked.contains($0.id) }.map(\.url)
        Task {
            failures = await Trash.move(urls)
            let failed = Set(failures.map(\.url))
            findings?.removeAll { urls.contains($0.url) && !failed.contains($0.url) }
            checked = checked.intersection(failed)
            await onRemoved()
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

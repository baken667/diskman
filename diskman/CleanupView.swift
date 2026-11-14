import DiskmanCore
import SwiftUI

/// Caches, logs and other regenerable data, grouped by rule, with a button to move the checked rules to the Trash.
struct CleanupView: View {
    /// Findings listed per rule; the rest are summarised ("+ N more") so rules with thousands of items stay smooth.
    static let visibleFindings = 50
    /// Totals at or above this ask for confirmation first.
    private static let confirmThreshold: Int64 = 1_000_000_000

    @State private var results: [CleanupResult]?
    @State private var checked: Set<String> = []
    @State private var runningApps: [String: String] = [:]   // rule id -> name of a running app that blocks it
    @State private var failures: [Trash.Failure] = []
    @State private var isConfirming = false
    @State private var isWorking = false

    private var groups: [(name: String, results: [CleanupResult])] {
        var order: [String] = []
        for r in results ?? [] where !order.contains(r.rule.group) { order.append(r.rule.group) }
        return order.map { g in (g, (results ?? []).filter { $0.rule.group == g }) }
    }

    private var removable: [CleanupResult] {
        (results ?? []).filter { checked.contains($0.id) && runningApps[$0.id] == nil }
    }
    private var removableSize: Int64 { removable.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let results {
                if results.isEmpty {
                    ContentUnavailableView("Nothing to Clean", systemImage: "sparkles", description: Text("No caches or logs were found."))
                } else {
                    List {
                        ForEach(groups, id: \.name) { group in
                            Section(LocalizedStringKey(group.name)) {
                                ForEach(group.results) { RuleRow(result: $0, isOn: binding(for: $0.rule), runningApp: runningApps[$0.id]) }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("Scanning…").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Divider()
            HStack {
                Text("Items are moved to the Trash. Nothing is deleted permanently.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Move \(removableSize.formatted(.byteCount(style: .file))) to Trash", role: .destructive) {
                    if removableSize >= Self.confirmThreshold { isConfirming = true } else { moveToTrash() }
                }
                .disabled(removable.isEmpty || isWorking)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .navigationTitle("Caches & Logs")
        .toolbar {
            ToolbarItem {
                Button("Rescan", systemImage: "arrow.clockwise") { Task { await scan() } }
                    .disabled(results == nil || isWorking)
            }
        }
        .task { await scan() }
        .task {
            // ponytail: polls once a second; observe NSWorkspace launch/terminate notifications if this ever matters.
            while !Task.isCancelled {
                refreshRunning()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .confirmationDialog("Move \(removableSize.formatted(.byteCount(style: .file))) to Trash?", isPresented: $isConfirming) {
            Button("Move to Trash", role: .destructive, action: moveToTrash)
        } message: {
            Text("Items are moved to the Trash. Nothing is deleted permanently.")
        }
        .alert("Some items could not be moved to the Trash", isPresented: .constant(!failures.isEmpty)) {
            Button("OK") { failures = [] }
        } message: {
            Text(verbatim: failures.map { "\($0.url.path)\n\($0.message)" }.joined(separator: "\n\n"))
        }
    }

    private func binding(for rule: CleanupRule) -> Binding<Bool> {
        Binding {
            checked.contains(rule.id)
        } set: { isOn in
            if isOn { checked.insert(rule.id) } else { checked.remove(rule.id) }
        }
    }

    private func scan() async {
        results = nil
        let found = await Cleaner.scan()
        checked = Set(found.filter(\.rule.isSafe).map(\.id))
        results = found
        refreshRunning()
    }

    private func refreshRunning() {
        var running: [String: String] = [:]
        for r in results ?? [] {
            for id in r.rule.appBundleIDs {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                    running[r.id] = app.localizedName ?? id
                    break
                }
            }
        }
        if running != runningApps { runningApps = running }
    }

    private func moveToTrash() {
        let urls = removable.flatMap { $0.findings.map(\.url) }
        isWorking = true
        Task {
            failures = await Trash.move(urls)
            await scan()
            isWorking = false
        }
    }
}

private struct RuleRow: View {
    let result: CleanupResult
    @Binding var isOn: Bool
    let runningApp: String?

    var body: some View {
        DisclosureGroup {
            ForEach(result.findings.prefix(CleanupView.visibleFindings)) { FindingRow(finding: $0) }
            if result.findings.count > CleanupView.visibleFindings {
                Text("+ \(result.findings.count - CleanupView.visibleFindings) more")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            HStack {
                Toggle(isOn: $isOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(result.rule.name))
                        Text(LocalizedStringKey(result.rule.description))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let runningApp {
                            Text("Quit \(runningApp) first").font(.caption).foregroundStyle(.orange)
                        } else if !result.rule.isSafe {
                            Text("Review before removing").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .accessibilityLabel(Text(LocalizedStringKey(result.rule.name)))
                Spacer()
                Text(result.size, format: .byteCount(style: .file))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(Text("Size \(result.size.formatted(.byteCount(style: .file)))"))
            }
        }
    }
}

/// One path with its size and a "Show in Finder" context menu.
private struct FindingRow: View {
    let finding: Finding

    var body: some View {
        HStack {
            Text(verbatim: finding.url.path)
                .font(.caption)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer()
            Text(finding.size, format: .byteCount(style: .file))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) }
        }
    }
}

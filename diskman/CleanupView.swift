import DiskmanCore
import SwiftUI

/// The scan and the user's choices. Owned by ContentView so they survive a visit to another sidebar
/// item: sizing every rule walks DerivedData and the Caches folder, which is too slow to redo each time.
@MainActor @Observable
final class CleanupModel {
    static let rules = CleanupRule.builtIn

    var found: [String: CleanupResult] = [:]   // rule id -> result with findings
    var scanned = 0                            // rules sized so far, found or not
    /// Checkboxes the user changed. Everything else follows `isSafe`, so a rescan never undoes a choice.
    var overrides: [String: Bool] = [:]
    var isWorking = false                      // a move to the Trash is running
    var failures: [Trash.Failure] = []
    private var task: Task<Void, Never>?

    var isScanning: Bool { scanned < Self.rules.count }

    func isChecked(_ rule: CleanupRule) -> Bool { overrides[rule.id] ?? rule.isSafe }

    func scanIfNeeded() { if task == nil { scan() } }

    /// (Re)starts the scan, cancelling a running one.
    func scan() {
        task?.cancel()
        found = [:]
        scanned = 0
        task = Task {
            for await result in Cleaner.results(Self.rules) {
                guard !Task.isCancelled else { return }   // a newer scan owns the state now
                scanned += 1
                if !result.findings.isEmpty { found[result.id] = result }
            }
        }
    }

    /// Moves everything the rules found to the Trash, then rescans. Lives here, not in the view,
    /// so leaving the screen mid-move can neither start a second move nor lose the failures.
    func trash(_ results: [CleanupResult]) {
        let urls = results.flatMap { $0.findings.map(\.url) }
        guard !urls.isEmpty, !isWorking, !isScanning else { return }
        isWorking = true
        Task {
            failures = await Trash.move(urls)
            // Opting in to a "review first" rule covers this one cleanup, not whatever it finds next time.
            for result in results where !result.rule.isSafe { overrides[result.id] = nil }
            isWorking = false
            scan()
        }
    }
}

/// Caches, logs and other regenerable data, grouped by rule, with a button to move the checked rules to the Trash.
struct CleanupView: View {
    var model: CleanupModel

    /// Findings listed per rule; the rest are summarised ("+ N more") so rules with thousands of items stay smooth.
    static let visibleFindings = 50
    /// Totals at or above this ask for confirmation first.
    private static let confirmThreshold: Int64 = 1_000_000_000

    private static let rules = CleanupModel.rules

    @State private var expanded: Set<String> = []
    @State private var runningApps: [String: String] = [:]   // rule id -> name of a running app that blocks it
    @State private var isConfirming = false

    private var isScanning: Bool { model.isScanning }
    /// Rules that found something, in rule order.
    private var results: [CleanupResult] { Self.rules.compactMap { model.found[$0.id] } }

    private var groups: [(name: String, results: [CleanupResult])] {
        var order: [String] = []
        for r in results where !order.contains(r.rule.group) { order.append(r.rule.group) }
        return order.map { g in (g, results.filter { $0.rule.group == g }) }
    }

    private var removable: [CleanupResult] {
        results.filter { model.isChecked($0.rule) && runningApps[$0.id] == nil }
    }
    private var removableSize: Int64 { removable.reduce(0) { $0 + $1.size } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                if isScanning {
                    progress.frame(maxWidth: 260).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ContentUnavailableView("Nothing to Clean", systemImage: "sparkles", description: Text("No caches or logs were found."))
                }
            } else {
                // Not a List: NSTableView-backed rows get wrong heights for multi-line text,
                // so rows overlapped and the last rules could not be scrolled to.
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(groups, id: \.name) { group in
                            Section {
                                ForEach(group.results) { result in
                                    RuleRow(result: result, isOn: binding(for: result.rule), isExpanded: expansion(for: result.id), runningApp: runningApps[result.id])
                                        .padding(.vertical, 8)
                                    if expanded.contains(result.id) {
                                        ForEach(result.findings.prefix(Self.visibleFindings)) { FindingRow(finding: $0).padding(.vertical, 3) }
                                        if result.findings.count > Self.visibleFindings {
                                            Text("+ \(result.findings.count - Self.visibleFindings) more")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                                .padding(.leading, FindingRow.indent)
                                                .padding(.vertical, 3)
                                        }
                                    }
                                    Divider()
                                }
                            } header: {
                                Text(LocalizedStringKey(group.name))
                                    .font(.headline)
                                    .foregroundStyle(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.top, 14)
                                    .padding(.bottom, 6)
                                    .background(.background)
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
                }
            }

            Divider()
            HStack {
                if isScanning && !results.isEmpty {
                    progress.controlSize(.small).frame(maxWidth: 240)
                } else {
                    Text("Items are moved to the Trash, nothing is deleted permanently. Empty the Trash to free the space.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Move \(removableSize.formatted(.byteCount(style: .file))) to Trash", role: .destructive) {
                    if removableSize >= Self.confirmThreshold { isConfirming = true } else { moveToTrash() }
                }
                .disabled(removable.isEmpty || model.isWorking || isScanning)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .navigationTitle("Caches & Logs")
        .toolbar {
            ToolbarItem {
                Button("Rescan", systemImage: "arrow.clockwise") { model.scan() }
                    .disabled(model.isWorking)
            }
        }
        .task { model.scanIfNeeded() }
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
            Text("Items are moved to the Trash, nothing is deleted permanently. Empty the Trash to free the space.")
        }
        .alert("Some items could not be moved to the Trash", isPresented: .constant(!model.failures.isEmpty)) {
            Button("OK") { model.failures = [] }
        } message: {
            Text(verbatim: model.failures.map { "\($0.url.path)\n\($0.message)" }.joined(separator: "\n\n"))
        }
    }

    private var progress: some View {
        ProgressView(value: Double(model.scanned), total: Double(Self.rules.count)) {
            Text("Scanning \(model.scanned) of \(Self.rules.count)…")
        }
    }

    /// A blocked rule shows unchecked; the user's choice comes back once the app quits.
    private func binding(for rule: CleanupRule) -> Binding<Bool> {
        Binding {
            model.isChecked(rule) && runningApps[rule.id] == nil
        } set: { isOn in
            model.overrides[rule.id] = isOn
        }
    }

    private func expansion(for id: String) -> Binding<Bool> {
        Binding {
            expanded.contains(id)
        } set: { isOn in
            if isOn { expanded.insert(id) } else { expanded.remove(id) }
        }
    }

    private func refreshRunning() {
        var running: [String: String] = [:]
        for rule in Self.rules {
            for id in rule.appBundleIDs {
                if let app = NSRunningApplication.runningApplications(withBundleIdentifier: id).first {
                    running[rule.id] = app.localizedName ?? id
                    break
                }
            }
        }
        if running != runningApps { runningApps = running }
    }

    private func moveToTrash() {
        refreshRunning()   // an app may have launched while the confirmation was up
        model.trash(removable)
    }
}

/// A rule's checkbox (its text toggles it too), size, and a chevron that shows its items as rows below.
private struct RuleRow: View {
    let result: CleanupResult
    @Binding var isOn: Bool
    @Binding var isExpanded: Bool
    let runningApp: String?

    var body: some View {
        HStack {
            Button {
                withAnimation { isExpanded.toggle() }
            } label: {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    .frame(width: 16, height: 16)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .accessibilityLabel(isExpanded ? Text("Hide Items") : Text("Show Items"))

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
            .disabled(runningApp != nil)
            .accessibilityLabel(Text(LocalizedStringKey(result.rule.name)))
            Spacer()
            Text(result.size, format: .byteCount(style: .file))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Size \(result.size.formatted(.byteCount(style: .file)))"))
        }
    }
}

/// One path with its size and a "Show in Finder" context menu.
private struct FindingRow: View {
    /// Lines items up under their rule's text.
    static let indent: CGFloat = 46
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
        .padding(.leading, Self.indent)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) }
        }
    }
}

import DiskmanCore
import SwiftUI

/// What the last move to the Trash amounted to. ContentView shows it for both screens.
struct Receipt: Equatable {
    let count: Int
    let bytes: Int64
}

func copyToPasteboard(_ text: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(text, forType: .string)
}

/// The scan and the user's choices. Owned by ContentView so they survive a visit to another sidebar
/// item: sizing every rule walks DerivedData and the Caches folder, which is too slow to redo each time.
@MainActor @Observable
final class CleanupModel {
    static let rules = CleanupRule.builtIn

    var found: [String: CleanupResult] = [:]   // rule id -> result with findings
    var scanned = 0                            // rules sized so far, found or not
    /// Checkboxes the user changed. Everything else follows `isSafe`, so a rescan never undoes a choice.
    var overrides: [String: Bool] = [:]
    /// Single items ticked differently from their rule: keep today's project, or pick two models out of thirty.
    var itemOverrides: [URL: Bool] = [:]
    var isWorking = false                      // a move to the Trash is running
    var failures: [Trash.Failure] = []
    var receipt: Receipt?
    private var task: Task<Void, Never>?

    var isScanning: Bool { scanned < Self.rules.count }

    func isChecked(_ rule: CleanupRule) -> Bool { !rule.isReportOnly && (overrides[rule.id] ?? rule.isSafe) }

    func isChecked(_ finding: Finding, of rule: CleanupRule) -> Bool {
        !rule.isReportOnly && (itemOverrides[finding.url] ?? isChecked(rule))
    }

    /// Ticking a rule is a decision about all of it, so it replaces the per-item choices made before.
    func setChecked(_ isOn: Bool, rule: CleanupRule) {
        overrides[rule.id] = isOn
        for finding in found[rule.id]?.findings ?? [] { itemOverrides[finding.url] = nil }
    }

    /// The items of this result that would be moved right now.
    func chosen(in result: CleanupResult) -> [Finding] {
        result.removable.filter { isChecked($0, of: result.rule) }
    }

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

    /// Moves what is chosen in these results to the Trash, then rescans. Lives here, not in the view,
    /// so leaving the screen mid-move can neither start a second move nor lose the failures.
    func trash(_ results: [CleanupResult]) {
        let chosen = results.flatMap(chosen(in:))
        guard !chosen.isEmpty, !isWorking, !isScanning else { return }
        isWorking = true
        Task {
            failures = await Cleaner.move(results, only: Set(chosen.map(\.url)))
            // Counted from what is really gone: the core may have skipped a rule whose app just launched.
            let moved = chosen.filter { (try? FileManager.default.attributesOfItem(atPath: $0.url.path)) == nil }
            if !moved.isEmpty { receipt = Receipt(count: moved.count, bytes: moved.reduce(0) { $0 + $1.size }) }
            // Opting in to a "review first" rule or item covers this one cleanup, not whatever is found next time.
            for result in results where !result.rule.isSafe { overrides[result.id] = nil }
            for finding in chosen { itemOverrides[finding.url] = nil }
            isWorking = false
            scan()
        }
    }
}

/// Caches, logs and other regenerable data, grouped by rule, with a button to move the checked rules to the Trash.
struct CleanupView: View {
    var model: CleanupModel

    /// Findings listed per rule until the user asks for all of them, so rules with thousands of items stay smooth.
    static let visibleFindings = 50
    /// Totals at or above this ask for confirmation first.
    private static let confirmThreshold: Int64 = 1_000_000_000

    private static let rules = CleanupModel.rules

    @State private var expanded: Set<String> = []
    @State private var showsAll: Set<String> = []                       // rules listing every finding
    @State private var runningApps: [String: [RunningApps.App]] = [:]   // rule id -> running apps that block it
    @State private var isConfirming = false
    /// What the button offered when it was clicked. The move may shrink it (an app launched), never grow it:
    /// a rule that became free while the confirmation was up was not part of what the user agreed to.
    @State private var pending: [CleanupResult] = []

    private var isScanning: Bool { model.isScanning }
    /// Rules that found something, in rule order.
    private var results: [CleanupResult] { Self.rules.compactMap { model.found[$0.id] } }

    private var groups: [(name: String, results: [CleanupResult])] {
        var order: [String] = []
        for r in results where !order.contains(r.rule.group) { order.append(r.rule.group) }
        return order.map { g in (g, results.filter { $0.rule.group == g }) }
    }

    private var removable: [CleanupResult] {
        results.filter { runningApps[$0.id] == nil && !model.chosen(in: $0).isEmpty }
    }
    private var removableSize: Int64 { removable.flatMap(model.chosen(in:)).reduce(0) { $0 + $1.size } }

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
                                    rows(for: result)
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
                    pending = removable
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

    /// A rule and, when expanded, its items, each with its own checkbox.
    @ViewBuilder private func rows(for result: CleanupResult) -> some View {
        let rule = result.rule, blockers = runningApps[result.id] ?? []
        RuleRow(result: result, isOn: binding(for: rule), isExpanded: expansion(for: result.id),
                blocker: blockers.first, chosen: model.chosen(in: result).count)
            .padding(.vertical, 8)
        if expanded.contains(result.id) {
            let all = showsAll.contains(result.id) || result.findings.count <= Self.visibleFindings
            ForEach(all ? result.findings : Array(result.findings.prefix(Self.visibleFindings))) { finding in
                FindingRow(finding: finding, isOn: rule.isReportOnly ? nil : binding(for: finding, of: rule))
                    .disabled(!blockers.isEmpty)
                    .padding(.vertical, 3)
            }
            if !all {
                Button("Show all \(result.findings.count) items") { showsAll.insert(result.id) }
                    .buttonStyle(.link)
                    .font(.caption)
                    .padding(.leading, FindingRow.indent)
                    .padding(.vertical, 3)
            }
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
            model.setChecked(isOn, rule: rule)
        }
    }

    private func binding(for finding: Finding, of rule: CleanupRule) -> Binding<Bool> {
        Binding {
            model.isChecked(finding, of: rule) && runningApps[rule.id] == nil
        } set: { isOn in
            model.itemOverrides[finding.url] = isOn == model.isChecked(rule) ? nil : isOn
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
        var running: [String: [RunningApps.App]] = [:]
        for rule in Self.rules where !rule.appBundleIDs.isEmpty {
            let apps = RunningApps.running(of: rule.appBundleIDs)
            if !apps.isEmpty { running[rule.id] = apps }
        }
        if running != runningApps { runningApps = running }
    }

    private func moveToTrash() {
        refreshRunning()   // an app may have launched while the confirmation was up
        model.trash(pending.filter { runningApps[$0.id] == nil })
        pending = []
    }
}

/// A rule's checkbox (its text toggles it too), size, and a chevron that shows its items as rows below.
/// A report-only rule has no checkbox: it is there to be read.
private struct RuleRow: View {
    let result: CleanupResult
    @Binding var isOn: Bool
    @Binding var isExpanded: Bool
    /// A running app that has to quit first. With several, they are named one after another.
    let blocker: RunningApps.App?
    /// How many of the rule's items would be moved now.
    let chosen: Int

    private var rule: CleanupRule { result.rule }

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

            if rule.isReportOnly {
                HStack(alignment: .firstTextBaseline) {
                    Image(systemName: "info.circle").foregroundStyle(.secondary).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        texts
                        Text("Shown for information. diskman does not remove this.").font(.caption).foregroundStyle(.secondary)
                        if let hint = rule.hint {
                            HStack {
                                Text(verbatim: hint).font(.caption.monospaced()).textSelection(.enabled)
                                Button("Copy") { copyToPasteboard(hint) }.controlSize(.small)
                            }
                            .padding(.top, 2)
                        }
                    }
                }
            } else {
                Toggle(isOn: $isOn) {
                    VStack(alignment: .leading, spacing: 2) {
                        texts
                        if let blocker {
                            Text("Quit \(blocker.name) first").font(.caption).foregroundStyle(.orange)
                        } else if chosen != (isOn ? result.findings.count : 0) {
                            // Whenever the items disagree with the checkbox, say what will really be moved.
                            Text("\(chosen) of \(result.findings.count) items selected").font(.caption).foregroundStyle(.secondary)
                        } else if !rule.isSafe {
                            Text("Review before removing").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .disabled(blocker != nil)
                .accessibilityLabel(Text(LocalizedStringKey(rule.name)))
            }
            Spacer()
            // Outside the disabled checkbox, so it stays clickable.
            if let blocker, !rule.isReportOnly {
                Button("Quit \(blocker.name)") { RunningApps.quit(blocker) }.controlSize(.small)
            }
            Text(result.size, format: .byteCount(style: .file))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("Size \(result.size.formatted(.byteCount(style: .file)))"))
        }
    }

    @ViewBuilder private var texts: some View {
        Text(LocalizedStringKey(rule.name))
        Text(LocalizedStringKey(rule.description))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

/// One path with its size, its own checkbox unless its rule is report-only, and a context menu.
private struct FindingRow: View {
    /// Lines items up under their rule's text.
    static let indent: CGFloat = 46
    let finding: Finding
    let isOn: Binding<Bool>?

    var body: some View {
        HStack {
            if let isOn {
                Toggle(isOn: isOn) { path }.controlSize(.small)
            } else {
                path
            }
            Spacer()
            Text(finding.size, format: .byteCount(style: .file))
                .font(.caption)
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.leading, Self.indent)
        .help(finding.url.path)
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([finding.url]) }
            Button("Copy Path") { copyToPasteboard(finding.url.path) }
        }
    }

    private var path: some View {
        Text(verbatim: finding.url.path)
            .font(.caption)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

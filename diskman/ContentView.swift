import DiskmanCore
import SwiftUI

struct ContentView: View {
    enum Selection: Hashable {
        case cleanup
        case app(InstalledApp)
    }

    var fda: FullDiskAccessModel
    var updates: UpdateModel
    @State private var apps: [InstalledApp] = []
    @State private var selection: Selection? = .cleanup
    @State private var search = ""
    @State private var failures: [Trash.Failure] = []
    @State private var cleanup = CleanupModel()

    @Environment(\.openWindow) private var openWindow

    /// By name or by any of its bundle IDs ("com.microsoft" finds every Microsoft app).
    private var filtered: [InstalledApp] {
        search.isEmpty ? apps : apps.filter { app in
            app.name.localizedCaseInsensitiveContains(search) || app.identifiers.contains { $0.localizedCaseInsensitiveContains(search) }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Cleanup") {
                    Label("Caches & Logs", systemImage: "sparkles").tag(Selection.cleanup)
                }
                Section("Applications") {
                    ForEach(filtered) { app in
                        Label {
                            Text(verbatim: app.name)
                        } icon: {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                        }
                        .tag(Selection.app(app))
                    }
                }
            }
            // Pinned above the list, like System Settings' sidebar search. `.searchable(placement: .sidebar)`
            // puts the field inside the list's scroll view, so it scrolled away; `.toolbar` would put it
            // over the detail column, away from the list it filters. A safe-area bar keeps it in place and
            // gets the system scroll edge effect, so rows no longer run bare under the title bar.
            .safeAreaBar(edge: .top) {
                SidebarSearchField(text: $search).padding(.horizontal, 10).padding(.bottom, 6)
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let release = updates.available { UpdateBanner(release: release, model: updates) }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            Group {
                switch selection {
                case .cleanup:
                    CleanupView(model: cleanup)
                case .app(let app):
                    UninstallView(app: app, hasTwin: apps.contains { $0.url != app.url && $0.bundleID == app.bundleID }) { failed, receipt in
                        failures = failed
                        if let receipt { cleanup.receipt = receipt }
                        await reload()
                    }
                        .id(app)
                        .id(fda.isGranted)   // rescan once access changes
                case nil:
                    ContentUnavailableView("Select an App", systemImage: "trash", description: Text("Choose an app to see everything it keeps on your disk."))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .safeAreaInset(edge: .top, spacing: 0) {
                if !fda.isGranted && !fda.isDismissed {
                    FullDiskAccessBanner(model: fda) { openWindow(id: TransparencyView.windowID) }
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if let receipt = cleanup.receipt { ReceiptBar(receipt: receipt) { cleanup.receipt = nil } }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in fda.refresh() }
        .task { await reload() }
        .task { await updates.checkAtLaunch() }
        .onChange(of: fda.isGranted) {   // rescan once access changes
            cleanup.scan()
            Task { await reload() }
        }
        // Lives here, not in UninstallView: that view goes away with the app it just removed.
        .alert("Some items could not be moved to the Trash", isPresented: .constant(!failures.isEmpty)) {
            Button("OK") { failures = [] }
        } message: {
            Text(verbatim: failures.map { "\($0.url.path)\n\($0.message)" }.joined(separator: "\n\n"))
        }
    }

    private func reload() async {
        // Downloads and Desktop only with Full Disk Access: without it, looking there makes macOS ask for each.
        apps = await InstalledApp.installed(in: InstalledApp.defaultDirectories + (fda.isGranted ? InstalledApp.looseDirectories : []))
        if case .app(let app) = selection, !apps.contains(app) { selection = nil }
    }
}

/// What the last move amounted to, and the one thing the user still has to do to get the space back.
private struct ReceiptBar: View {
    let receipt: Receipt
    let dismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityHidden(true)
            Text("Moved \(receipt.bytes.formatted(.byteCount(style: .file))) to the Trash (^[\(receipt.count) items](inflect: true)). The space is freed when you empty the Trash.")
                .font(.callout)
            Spacer()
            Button("Open Trash") { NSWorkspace.shared.open(URL.homeDirectory.appending(path: ".Trash")) }.controlSize(.small)
            Button("Dismiss", systemImage: "xmark", action: dismiss).labelStyle(.iconOnly).buttonStyle(.borderless)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
    }
}

/// The system search field (magnifier, clear button, Esc to clear), filtering as you type.
private struct SidebarSearchField: NSViewRepresentable {
    @Binding var text: String

    func makeNSView(context: Context) -> NSSearchField {
        let field = NSSearchField()
        field.target = context.coordinator
        field.action = #selector(Coordinator.changed)   // sent on every keystroke and on clear
        return field
    }

    func updateNSView(_ field: NSSearchField, context: Context) {
        if field.stringValue != text { field.stringValue = text }
        context.coordinator.text = $text
    }

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    final class Coordinator: NSObject {
        var text: Binding<String>
        init(text: Binding<String>) { self.text = text }
        @objc func changed(_ field: NSSearchField) { text.wrappedValue = field.stringValue }
    }
}

#Preview {
    ContentView(fda: FullDiskAccessModel(), updates: UpdateModel())
}

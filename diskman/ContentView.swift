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

    private var filtered: [InstalledApp] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
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
                if let version = updates.availableVersion { UpdateBanner(version: version, model: updates) }
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            Group {
                switch selection {
                case .cleanup:
                    CleanupView(model: cleanup)
                case .app(let app):
                    UninstallView(app: app) { failed in
                        failures = failed
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
                if !fda.isGranted && !fda.isDismissed { FullDiskAccessBanner(model: fda) }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in fda.refresh() }
        .task { await reload() }
        .task { await updates.checkAtLaunch() }
        .onChange(of: fda.isGranted) { cleanup.scan() }   // rescan once access changes
        // Lives here, not in UninstallView: that view goes away with the app it just removed.
        .alert("Some items could not be moved to the Trash", isPresented: .constant(!failures.isEmpty)) {
            Button("OK") { failures = [] }
        } message: {
            Text(verbatim: failures.map { "\($0.url.path)\n\($0.message)" }.joined(separator: "\n\n"))
        }
    }

    private func reload() async {
        apps = await InstalledApp.installed()
        if case .app(let app) = selection, !apps.contains(app) { selection = nil }
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

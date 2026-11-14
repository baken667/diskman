import DiskmanCore
import SwiftUI

struct ContentView: View {
    enum Selection: Hashable {
        case cleanup
        case app(InstalledApp)
    }

    var fda: FullDiskAccessModel
    @State private var apps: [InstalledApp] = []
    @State private var selection: Selection? = .cleanup
    @State private var search = ""

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
            .searchable(text: $search, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            Group {
                switch selection {
                case .cleanup:
                    CleanupView().id(fda.isGranted)
                case .app(let app):
                    UninstallView(app: app) { await reload() }
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
    }

    private func reload() async {
        apps = await InstalledApp.installed()
        if case .app(let app) = selection, !apps.contains(app) { selection = nil }
    }
}

#Preview {
    ContentView(fda: FullDiskAccessModel())
}

import DiskmanCore
import SwiftUI

struct ContentView: View {
    var fda: FullDiskAccessModel
    @State private var apps: [InstalledApp] = []
    @State private var selection: InstalledApp?
    @State private var search = ""

    private var filtered: [InstalledApp] {
        search.isEmpty ? apps : apps.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        NavigationSplitView {
            List(filtered, selection: $selection) { app in
                Label {
                    Text(verbatim: app.name)
                } icon: {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path))
                }
                .tag(app)
            }
            .searchable(text: $search, placement: .sidebar)
            .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        } detail: {
            Group {
                if let selection {
                    UninstallView(app: selection) { await reload() }
                        .id(selection)
                        .id(fda.isGranted)   // rescan once access changes
                } else {
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
        if let selection, !apps.contains(selection) { self.selection = nil }
    }
}

#Preview {
    ContentView(fda: FullDiskAccessModel())
}

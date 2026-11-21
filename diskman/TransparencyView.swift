import DiskmanCore
import SwiftUI

/// Everything the app looks at, built from the same tables the scanners use, so it cannot drift from the code.
struct TransparencyView: View {
    static let windowID = "what-diskman-reads"

    var body: some View {
        List {
            Section {
                Text("diskman reads names and sizes in the places below, and the contents of two kinds of file: each app's Info.plist and signature, and the background-job files in LaunchAgents and LaunchDaemons. It never opens your documents, and it removes nothing until you press the button; then it only moves items to the Trash.")
                    .font(.callout)
            }
            Section("The list of apps") {
                Text("Apps in these folders and in the folders directly inside them:").font(.callout).foregroundStyle(.secondary)
                ForEach(InstalledApp.defaultDirectories, id: \.self) { Text(verbatim: $0.path).font(.callout.monospaced()) }
                Text("Only with Full Disk Access, the same for:").font(.callout).foregroundStyle(.secondary)
                ForEach(InstalledApp.looseDirectories, id: \.self) { Text(verbatim: $0.path).font(.callout.monospaced()) }
            }
            Section("When you pick an app") {
                Text("Entries named after the app, in each of these folders of your Library and of the Mac's Library:")
                    .font(.callout).foregroundStyle(.secondary)
                ForEach(LeftoverFinder.locations, id: \.path) { Text(verbatim: "Library/\($0.path)").font(.callout.monospaced()) }
                Text("The same in these system folders:").font(.callout).foregroundStyle(.secondary)
                ForEach(LeftoverFinder.defaultSystemFolders, id: \.url) { Text(verbatim: $0.url.path).font(.callout.monospaced()) }
                Text("And in your home folder, only folders with exactly the app's name:").font(.callout).foregroundStyle(.secondary)
                ForEach(LeftoverFinder.homeLocations, id: \.path) { location in
                    Text(verbatim: location.path == "." ? "~/.name" : "~/\(location.path)/name").font(.callout.monospaced())
                }
            }
            Section("Caches & Logs") {
                ForEach(CleanupRule.builtIn) { rule in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(LocalizedStringKey(rule.name))
                        ForEach(rule.paths, id: \.self) { Text(verbatim: $0).font(.caption.monospaced()).foregroundStyle(.secondary) }
                    }
                }
            }
            Section("Network") {
                Text("One request when the app opens, to ask for the number of the latest release. It carries nothing about you or your disk, and you can turn it off in Settings.")
                    .font(.callout)
                Text(verbatim: Updates.api.absoluteString).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                Text("A download of that release, only when you click Update and Restart.").font(.callout)
            }
            Section("Full Disk Access") {
                Text("macOS hides other apps' containers and a few Library folders from every app. With access diskman can see leftovers there; without it, it works with what it can see. To check whether access is granted, it tries to open one of these:")
                    .font(.callout)
                ForEach(FullDiskAccess.probePaths, id: \.self) { Text(verbatim: $0).font(.caption.monospaced()).foregroundStyle(.secondary) }
            }
        }
        .frame(minWidth: 520, minHeight: 480)
        .navigationTitle("What diskman Reads")
    }
}

//
//  diskmanApp.swift
//  diskman
//
//  Created by Bauyrzhan on 14.11.2026.
//

import SwiftUI

@main
struct diskmanApp: App {
    @State private var fda = FullDiskAccessModel()
    @State private var updates = UpdateModel()

    var body: some Scene {
        WindowGroup {
            ContentView(fda: fda, updates: updates)
        }
        .commands {
            CommandGroup(replacing: .help) {
                TransparencyCommand()
            }
        }
        Window("What diskman Reads", id: TransparencyView.windowID) { TransparencyView() }
        Settings { SettingsView(model: fda, updates: updates) }
    }
}

/// A menu item has to be a view to reach `openWindow`.
private struct TransparencyCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("What diskman Reads") { openWindow(id: TransparencyView.windowID) }
    }
}

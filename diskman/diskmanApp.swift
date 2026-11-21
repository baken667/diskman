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
        Settings { SettingsView(model: fda, updates: updates) }
    }
}

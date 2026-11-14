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

    var body: some Scene {
        WindowGroup {
            ContentView(fda: fda)
        }
        Settings { SettingsView(model: fda) }
    }
}

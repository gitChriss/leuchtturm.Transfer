//
//  TransferApp.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import SwiftUI

@main
struct TransferApp: App {

    @State private var settingsStore = SettingsStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settingsStore)
                .frame(minWidth: AppConstants.windowMinWidth,
                       minHeight: AppConstants.windowMinHeight)
                .tint(Color.accentColor)
        }

        Settings {
            SettingsView(store: settingsStore)
                .frame(width: 520, height: 380)
        }
    }
}

//
//  TransferApp.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import SwiftUI
import AppKit

@main
struct TransferApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
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
                .environment(settingsStore)
                .frame(width: AppConstants.settingsWindowWidth,
                       height: AppConstants.settingsWindowHeight)
        }
    }
}

//
//  TransferApp.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import SwiftUI

@main
struct TransferApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: AppConstants.windowMinWidth,
                       minHeight: AppConstants.windowMinHeight)
                .tint(Color.accentColor)
        }
    }
}

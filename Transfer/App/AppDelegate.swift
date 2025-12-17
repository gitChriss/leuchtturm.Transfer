//
//  AppDelegate.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    static let openFilesNotification = Notification.Name("transfer.openFileURLs")

    func application(_ application: NSApplication, open urls: [URL]) {
        handle(urls: urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        handle(urls: [URL(fileURLWithPath: filename)])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        handle(urls: filenames.map { URL(fileURLWithPath: $0) })
        sender.reply(toOpenOrPrint: .success)
    }

    // MARK: - Core handler

    private func handle(urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL }
        guard fileURLs.isEmpty == false else { return }

        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first?.makeKeyAndOrderFront(nil)

        NotificationCenter.default.post(
            name: Self.openFilesNotification,
            object: fileURLs
        )
    }
}

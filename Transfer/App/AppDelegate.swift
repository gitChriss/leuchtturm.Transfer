//
//  AppDelegate.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import AppKit
import Foundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    private let openFilesNotification = Notification.Name("transfer.openFileURLs")

    func application(_ application: NSApplication, open urls: [URL]) {
        postOpenFiles(urls)
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        let url = URL(fileURLWithPath: filename)
        postOpenFiles([url])
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        postOpenFiles(urls)
        sender.reply(toOpenOrPrint: .success)
    }

    private func postOpenFiles(_ urls: [URL]) {
        let fileURLs = urls.filter { $0.isFileURL }
        guard fileURLs.isEmpty == false else { return }

        NotificationCenter.default.post(
            name: openFilesNotification,
            object: fileURLs
        )
    }
}

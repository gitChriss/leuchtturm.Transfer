//
//  Log.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import Foundation
import OSLog

enum Log {

    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.leuchtturm.Transfer"
    private static let logger = Logger(subsystem: subsystem, category: "Transfer")

    static func info(_ message: String) {
        #if DEBUG
        logger.info("\(message, privacy: .public)")
        #endif
    }

    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    // Guardrail: niemals Secrets loggen
    static func redacted(_ label: String, _ value: String?) -> String {
        guard let value, value.isEmpty == false else { return "\(label)=<empty>" }
        return "\(label)=<redacted:\(value.count) chars>"
    }
}

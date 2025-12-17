//
//  BuildInfo.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import Foundation

enum BuildInfo {

    static var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
    }

    static var fullVersionString: String {
        "v\(appVersion) (\(buildNumber))"
    }
}

//
//  SettingsStore.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import Foundation
import Observation

@Observable
final class SettingsStore {

    enum DefaultsKeys {
        static let sftpHost = "settings.sftp.host"
        static let sftpPort = "settings.sftp.port"
        static let sftpUsername = "settings.sftp.username"
        static let apiBaseURL = "settings.api.baseURL"
    }

    enum KeychainKeys {
        static let sftpPassword = "secrets.sftp.password"
        static let uploadToken  = "secrets.api.uploadToken"
    }

    enum ConnectionStatus: Equatable {
        case unknown
        case checking
        case ok
        case failed(message: String)
    }

    // FTP
    var sftpHost: String = AppConstants.defaultSFTPHost
    var sftpPort: Int = AppConstants.defaultSFTPPort
    var sftpUsername: String = ""

    // Secrets
    var sftpPassword: String = ""
    var uploadToken: String = ""

    // API
    var apiBaseURLString: String = AppConstants.defaultAPIBaseURLString

    // Status
    var sftpStatus: ConnectionStatus = .unknown

    var lastSaveMessage: String? = nil

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        reload()
    }

    func reload() {
        let host = defaults.string(forKey: DefaultsKeys.sftpHost)
        let port = defaults.object(forKey: DefaultsKeys.sftpPort) as? Int
        let user = defaults.string(forKey: DefaultsKeys.sftpUsername)
        let api  = defaults.string(forKey: DefaultsKeys.apiBaseURL)

        sftpHost = host?.isEmpty == false ? host! : AppConstants.defaultSFTPHost
        sftpPort = port ?? AppConstants.defaultSFTPPort
        sftpUsername = user ?? ""
        apiBaseURLString = api?.isEmpty == false ? api! : AppConstants.defaultAPIBaseURLString

        sftpPassword = KeychainService.readString(key: KeychainKeys.sftpPassword) ?? ""
        uploadToken  = KeychainService.readString(key: KeychainKeys.uploadToken) ?? ""

        sftpStatus = .unknown
    }

    @discardableResult
    func save() -> Bool {
        defaults.set(sftpHost, forKey: DefaultsKeys.sftpHost)
        defaults.set(sftpPort, forKey: DefaultsKeys.sftpPort)
        defaults.set(sftpUsername, forKey: DefaultsKeys.sftpUsername)
        defaults.set(apiBaseURLString, forKey: DefaultsKeys.apiBaseURL)

        let ok1 = KeychainService.writeString(key: KeychainKeys.sftpPassword, value: sftpPassword)
        let ok2 = KeychainService.writeString(key: KeychainKeys.uploadToken, value: uploadToken)

        let ok = ok1 && ok2
        lastSaveMessage = ok ? "Gespeichert" : "Speichern fehlgeschlagen"

        sftpStatus = .unknown
        return ok
    }

    func clearAll() {
        defaults.removeObject(forKey: DefaultsKeys.sftpHost)
        defaults.removeObject(forKey: DefaultsKeys.sftpPort)
        defaults.removeObject(forKey: DefaultsKeys.sftpUsername)
        defaults.removeObject(forKey: DefaultsKeys.apiBaseURL)

        _ = KeychainService.delete(key: KeychainKeys.sftpPassword)
        _ = KeychainService.delete(key: KeychainKeys.uploadToken)

        sftpHost = AppConstants.defaultSFTPHost
        sftpPort = AppConstants.defaultSFTPPort
        sftpUsername = ""
        apiBaseURLString = AppConstants.defaultAPIBaseURLString

        sftpPassword = ""
        uploadToken = ""

        sftpStatus = .unknown
        lastSaveMessage = "Gelöscht"
    }

    var hasMinimumCredentials: Bool {
        sftpHost.isEmpty == false &&
        sftpPort > 0 &&
        sftpUsername.isEmpty == false &&
        sftpPassword.isEmpty == false &&
        apiBaseURLString.isEmpty == false &&
        uploadToken.isEmpty == false
    }

    @MainActor
    func checkSFTPConnection() async {
        sftpStatus = .checking

        let creds = SFTPService.Credentials(
            host: sftpHost,
            port: sftpPort,
            username: sftpUsername,
            password: sftpPassword
        )

        do {
            try await SFTPService.testConnection(credentials: creds)
            sftpStatus = .ok
        } catch {
            let msg: String
            if let e = error as? LocalizedError, let d = e.errorDescription, d.isEmpty == false {
                msg = d
            } else {
                msg = error.localizedDescription
            }
            sftpStatus = .failed(message: msg)
        }
    }

    func resetSFTPStatus() {
        sftpStatus = .unknown
    }
}

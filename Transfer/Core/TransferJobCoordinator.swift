//
//  TransferJobCoordinator.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import Foundation
import Observation

@Observable
final class TransferJobCoordinator {

    enum Phase: String, Equatable {
        case cleaning
        case uploading
        case triggering
        case polling
    }

    enum State: Equatable {
        case idle
        case ready(fileURL: URL)
        case running(phase: Phase, progress: Double, filename: String)
        case done(resultURL: URL)
        case failed(message: String)
    }

    struct SettingsSnapshot: Sendable {
        let sftpHost: String
        let sftpPort: Int
        let sftpUsername: String
        let sftpPassword: String

        let apiBaseURLString: String
        let uploadToken: String
    }

    private(set) var state: State = .idle
    private(set) var statusLines: [String] = []

    private var jobTask: Task<Void, Never>?
    private var lastFileURL: URL?
    private var lastSettings: SettingsSnapshot?

    var isBusy: Bool {
        if case .running = state { return true }
        return false
    }

    func pushStatus(_ line: String) {
        statusLines.append(line)
    }

    func acceptDroppedFile(_ url: URL) -> Bool {
        guard isBusy == false else {
            pushStatus("Drop ignoriert. Job läuft bereits.")
            return false
        }

        lastFileURL = url
        state = .ready(fileURL: url)
        pushStatus("Datei ausgewählt: \(url.lastPathComponent)")
        return true
    }

    func resetToIdle() {
        cancel()
        state = .idle
        pushStatus("Zurückgesetzt")
    }

    func cancel() {
        jobTask?.cancel()
        jobTask = nil
    }

    func retryIfPossible(settings: SettingsSnapshot) {
        guard let lastFileURL else {
            pushStatus("Retry nicht möglich. Keine Datei vorhanden.")
            state = .idle
            return
        }
        start(fileURL: lastFileURL, settings: settings)
    }

    func start(fileURL: URL, settings: SettingsSnapshot) {
        guard isBusy == false else {
            pushStatus("Start ignoriert. Job läuft bereits.")
            return
        }

        cancel()

        let filename = fileURL.lastPathComponent
        lastFileURL = fileURL
        lastSettings = settings

        pushStatus("Start: \(filename)")
        state = .running(phase: .cleaning, progress: 0.0, filename: filename)

        jobTask = Task { @MainActor in
            do {
                try Task.checkCancellation()

                pushStatus("Remote Cleanup: starte")
                try await performRemoteCleanup(filename: filename, settings: settings)
                pushStatus("Remote Cleanup: fertig")

                try Task.checkCancellation()

                pushStatus("Upload: starte")
                try await performUpload(fileURL: fileURL, filename: filename, settings: settings)
                pushStatus("Upload: fertig")

                try Task.checkCancellation()

                pushStatus("API Start: starte")
                try await simulateStep(phase: .triggering, filename: filename, from: 0.85, to: 0.90, msPerTick: 60)
                pushStatus("API Start: ok")

                try Task.checkCancellation()

                pushStatus("Status: polling")
                try await simulateStep(phase: .polling, filename: filename, from: 0.90, to: 1.00, msPerTick: 70)
                pushStatus("Status: done")

                let finalURL = URL(string: "https://transfer.fotostudio-sichtweisen.de/\(filename)")!
                state = .done(resultURL: finalURL)
                pushStatus("Done: \(finalURL.absoluteString)")
                jobTask = nil

            } catch {
                if Task.isCancelled {
                    pushStatus("Abgebrochen")
                    state = .idle
                    jobTask = nil
                    return
                }

                let msg = userFacingErrorMessage(error)
                state = .failed(message: msg)
                pushStatus("Fehler: \(msg)")
                jobTask = nil
            }
        }
    }

    @MainActor
    private func performRemoteCleanup(filename: String, settings: SettingsSnapshot) async throws {
        let creds = SFTPService.Credentials(
            host: settings.sftpHost,
            port: settings.sftpPort,
            username: settings.sftpUsername,
            password: settings.sftpPassword
        )

        try await SFTPService.cleanupRemoteRoot(credentials: creds, remotePath: "/") { [weak self] deleted, total in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let baseStart = 0.00
                let baseEnd = 0.10

                let ratio: Double
                if total <= 0 {
                    ratio = 1.0
                } else {
                    ratio = Double(deleted) / Double(total)
                }

                let p = baseStart + ratio * (baseEnd - baseStart)
                self.state = .running(phase: .cleaning, progress: p, filename: filename)

                if total > 0 {
                    self.pushStatus("Remote Cleanup: \(deleted)/\(total)")
                } else {
                    self.pushStatus("Remote Cleanup: nichts zu löschen")
                }
            }
        }

        state = .running(phase: .cleaning, progress: 0.10, filename: filename)
    }

    @MainActor
    private func performUpload(fileURL: URL, filename: String, settings: SettingsSnapshot) async throws {
        let creds = SFTPService.Credentials(
            host: settings.sftpHost,
            port: settings.sftpPort,
            username: settings.sftpUsername,
            password: settings.sftpPassword
        )

        let baseStart = 0.10
        let baseEnd = 0.85

        try await SFTPService.uploadFileToRemoteRoot(
            credentials: creds,
            localFileURL: fileURL,
            remoteFilename: filename
        ) { [weak self] sent, total in
            Task { @MainActor [weak self] in
                guard let self else { return }

                let ratio: Double
                if total == 0 {
                    ratio = 1.0
                } else {
                    ratio = Double(sent) / Double(total)
                }

                let p = baseStart + max(0, min(1, ratio)) * (baseEnd - baseStart)
                self.state = .running(phase: .uploading, progress: p, filename: filename)
            }
        }

        state = .running(phase: .uploading, progress: 0.85, filename: filename)
    }

    private func userFacingErrorMessage(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription, d.isEmpty == false {
            return d
        }
        return "Unerwarteter Fehler. \(error.localizedDescription)"
    }

    @MainActor
    private func simulateStep(
        phase: Phase,
        filename: String,
        from start: Double,
        to end: Double,
        msPerTick: UInt64
    ) async throws {
        let clampedStart = max(0, min(1, start))
        let clampedEnd = max(0, min(1, end))
        let ticks = max(1, Int((clampedEnd - clampedStart) * 100))

        for i in 0...ticks {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: msPerTick * 1_000_000)

            let p = clampedStart + (Double(i) / Double(ticks)) * (clampedEnd - clampedStart)
            state = .running(phase: phase, progress: p, filename: filename)
        }
    }
}

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
                let startResult = try await performAPIStart(filename: filename, settings: settings)
                pushStatus("API Start: ok (jobId: \(startResult.jobId))")

                try Task.checkCancellation()

                pushStatus("Status: polling")
                let finalURL = try await pollStatusUntilDone(
                    filename: filename,
                    settings: settings,
                    jobId: startResult.jobId,
                    statusURLString: startResult.statusUrl
                )

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

    // MARK: - API

    private struct APIStartResponse: Decodable {
        let jobId: String
        let statusUrl: String
    }

    private enum APIStatusState: String, Decodable {
        case processing
        case done
        case error
    }

    private struct APIStatusResponse: Decodable {
        let state: APIStatusState
        let url: String?
        let message: String?
    }

    private enum APIError: LocalizedError {
        case invalidBaseURL
        case invalidStatusURL
        case invalidResponse
        case httpError(code: Int)
        case decodingFailed
        case serverError(message: String?)
        case doneMissingURL

        var errorDescription: String? {
            switch self {
            case .invalidBaseURL:
                return "API Base URL ist ungültig."
            case .invalidStatusURL:
                return "Status URL ist ungültig."
            case .invalidResponse:
                return "Ungültige API Antwort."
            case .httpError(let code):
                return "API Fehler. HTTP \(code)."
            case .decodingFailed:
                return "API Antwort konnte nicht gelesen werden."
            case .serverError(let message):
                if let message, message.isEmpty == false {
                    return "API Fehler. \(message)"
                }
                return "API Fehler."
            case .doneMissingURL:
                return "API meldet done, aber ohne Ergebnis-URL."
            }
        }
    }

    @MainActor
    private func performAPIStart(filename: String, settings: SettingsSnapshot) async throws -> APIStartResponse {
        state = .running(phase: .triggering, progress: 0.85, filename: filename)

        let baseURL = try apiBaseURL(from: settings.apiBaseURLString)
        let url = baseURL.appendingPathComponent("upload/start")

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue(settings.uploadToken, forHTTPHeaderField: "X-Upload-Token")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Annahme: API braucht den Filename. Wenn der Server das nicht braucht, wird er es ignorieren.
        let body = ["filename": filename]
        req.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw APIError.httpError(code: http.statusCode) }

        let decoded: APIStartResponse
        do {
            decoded = try JSONDecoder().decode(APIStartResponse.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }

        state = .running(phase: .triggering, progress: 0.90, filename: filename)
        return decoded
    }

    @MainActor
    private func pollStatusUntilDone(
        filename: String,
        settings: SettingsSnapshot,
        jobId: String,
        statusURLString: String
    ) async throws -> URL {

        state = .running(phase: .polling, progress: 0.90, filename: filename)

        let statusURL = try makeStatusURL(settings: settings, jobId: jobId, statusURLString: statusURLString)

        // Simple polling. Kein Feature-Creep: konstantes Intervall, klare Abbruchbedingung.
        let pollIntervalNs: UInt64 = 1_000_000_000 // 1s
        let maxAttempts = 600 // 10 Minuten

        var progress = 0.90

        for attempt in 1...maxAttempts {
            try Task.checkCancellation()

            let status = try await fetchStatus(url: statusURL, settings: settings)

            switch status.state {
            case .processing:
                // Soft progress bis 0.99, damit der Ring "lebt".
                let target = 0.99
                let step = (target - 0.90) / Double(maxAttempts)
                progress = min(target, progress + step)

                state = .running(phase: .polling, progress: progress, filename: filename)
                pushStatus("Status: processing (\(attempt))")

                try await Task.sleep(nanoseconds: pollIntervalNs)

            case .done:
                guard let urlStr = status.url, let finalURL = URL(string: urlStr) else {
                    throw APIError.doneMissingURL
                }
                state = .running(phase: .polling, progress: 1.0, filename: filename)
                pushStatus("Status: done")
                return finalURL

            case .error:
                throw APIError.serverError(message: status.message)
            }
        }

        throw APIError.serverError(message: "Timeout")
    }

    private func fetchStatus(url: URL, settings: SettingsSnapshot) async throws -> APIStatusResponse {
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(settings.uploadToken, forHTTPHeaderField: "X-Upload-Token")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
        guard (200...299).contains(http.statusCode) else { throw APIError.httpError(code: http.statusCode) }

        do {
            return try JSONDecoder().decode(APIStatusResponse.self, from: data)
        } catch {
            throw APIError.decodingFailed
        }
    }

    private func apiBaseURL(from raw: String) throws -> URL {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.isEmpty == false else { throw APIError.invalidBaseURL }

        let initialURL: URL
        if s.contains("://") == false {
            guard let url = URL(string: "https://\(s)") else { throw APIError.invalidBaseURL }
            initialURL = url
        } else {
            guard let url = URL(string: s) else { throw APIError.invalidBaseURL }
            initialURL = url
        }

        // Robust: falls jemand "…/upload" als Base URL einträgt, entfernen wir das.
        guard var comps = URLComponents(url: initialURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidBaseURL
        }

        let path = comps.path

        if path == "/upload" || path == "/upload/" {
            comps.path = ""
            comps.query = nil
            comps.fragment = nil
        }

        guard let normalized = comps.url else { throw APIError.invalidBaseURL }
        return normalized
    }

    private func makeStatusURL(settings: SettingsSnapshot, jobId: String, statusURLString: String) throws -> URL {
        let trimmed = statusURLString.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.isEmpty == false, let url = URL(string: trimmed) {
            return url
        }

        let baseURL = try apiBaseURL(from: settings.apiBaseURLString)
        return baseURL.appendingPathComponent("upload/status").appendingPathComponent(jobId)
    }

    // MARK: - Errors

    private func userFacingErrorMessage(_ error: Error) -> String {
        if let e = error as? LocalizedError, let d = e.errorDescription, d.isEmpty == false {
            return d
        }
        return "Unerwarteter Fehler. \(error.localizedDescription)"
    }
}

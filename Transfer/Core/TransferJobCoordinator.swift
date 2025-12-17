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

    private(set) var state: State = .idle
    private(set) var statusLines: [String] = []

    private var jobTask: Task<Void, Never>?
    private var lastFileURL: URL?

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

    func retryIfPossible() {
        guard let lastFileURL else {
            pushStatus("Retry nicht möglich. Keine Datei vorhanden.")
            state = .idle
            return
        }
        start(fileURL: lastFileURL)
    }

    func start(fileURL: URL) {
        guard isBusy == false else {
            pushStatus("Start ignoriert. Job läuft bereits.")
            return
        }

        cancel()

        let filename = fileURL.lastPathComponent
        lastFileURL = fileURL

        pushStatus("Start: \(filename)")
        state = .running(phase: .cleaning, progress: 0.0, filename: filename)

        jobTask = Task { @MainActor in
            do {
                try Task.checkCancellation()

                // Phase 1: cleaning (placeholder)
                pushStatus("Remote Cleanup: starte")
                try await simulateStep(phase: .cleaning, filename: filename, from: 0.0, to: 0.10, msPerTick: 35)
                pushStatus("Remote Cleanup: fertig")

                try Task.checkCancellation()

                // Phase 2: uploading (placeholder)
                pushStatus("Upload: starte")
                try await simulateStep(phase: .uploading, filename: filename, from: 0.10, to: 0.85, msPerTick: 25)
                pushStatus("Upload: fertig")

                try Task.checkCancellation()

                // Phase 3: triggering (placeholder)
                pushStatus("API Start: starte")
                try await simulateStep(phase: .triggering, filename: filename, from: 0.85, to: 0.90, msPerTick: 60)
                pushStatus("API Start: ok")

                try Task.checkCancellation()

                // Phase 4: polling (placeholder)
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

                let msg = "Unerwarteter Fehler. \(error.localizedDescription)"
                state = .failed(message: msg)
                pushStatus("Fehler: \(msg)")
                jobTask = nil
            }
        }
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

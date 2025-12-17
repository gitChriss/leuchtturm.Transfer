//
//  ContentView.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct ContentView: View {

    @Environment(SettingsStore.self) private var settingsStore

    @State private var isDropTargeted: Bool = false
    @State private var job = TransferJobCoordinator()

    var body: some View {
        VStack(spacing: 16) {

            header

            dropZone

            statusArea

            footer
        }
        .padding(24)
        .onAppear {
            Log.info("App launched \(BuildInfo.fullVersionString)")
            job.pushStatus("Bereit")
        }
    }

    // MARK: - UI Blocks

    private var header: some View {
        VStack(spacing: 10) {
            Image(systemName: headerSymbolName)
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("Transfer")
                    .font(.title2.weight(.semibold))

                Text(headerSubtitle)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 460)
            }
        }
    }

    private var dropZone: some View {
        VStack(spacing: 12) {

            if case .running(_, let progress, _) = job.state {
                CircularProgressRing(progress: progress)
                    .frame(width: 72, height: 72)
                    .accessibilityLabel("Fortschritt")
                    .accessibilityValue("\(Int(progress * 100)) Prozent")
            } else {
                Image(systemName: "arrow.down.doc")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Text(dropZoneTitle)
                .font(.headline)

            if let detail = dropZoneDetailText {
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            actionRow
        }
        .frame(maxWidth: 520)
        .padding(18)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(borderColor, lineWidth: 2)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
    }

    private var actionRow: some View {
        HStack(spacing: 10) {
            switch job.state {

            case .ready(let fileURL):
                Button("Start") { startJob(fileURL: fileURL) }
                    .buttonStyle(.borderedProminent)
                    .disabled(settingsStore.hasMinimumCredentials == false)

                Button("Zurücksetzen") { job.resetToIdle() }
                    .buttonStyle(.bordered)

            case .running:
                Button("Abbrechen") { job.cancel(); job.resetToIdle() }
                    .buttonStyle(.bordered)

            case .done(let resultURL):
                Button("Copy") { copyToClipboard(resultURL.absoluteString) }
                    .buttonStyle(.bordered)

                Button("Open") { openURL(resultURL) }
                    .buttonStyle(.borderedProminent)

                Button("Neue Datei") { job.resetToIdle() }
                    .buttonStyle(.bordered)

            case .failed:
                Button("Retry") { retryWithLatestSettings() }
                    .buttonStyle(.borderedProminent)
                    .disabled(settingsStore.hasMinimumCredentials == false)

                Button("Zurücksetzen") { job.resetToIdle() }
                    .buttonStyle(.bordered)

            default:
                EmptyView()
            }
        }
        .animation(.snappy, value: job.state)
    }

    private var statusArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.top, 6)

            HStack {
                Text("Status")
                    .font(.headline)

                Spacer()

                if settingsStore.hasMinimumCredentials == false {
                    Text("Settings fehlen")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(job.statusLines.indices.reversed(), id: \.self) { idx in
                        Text(job.statusLines[idx])
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxWidth: 520, maxHeight: 120)
        }
        .frame(maxWidth: 520)
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Text(BuildInfo.fullVersionString)
                .font(.footnote)
                .foregroundStyle(.secondary)

            Spacer()

            Text("macOS 15")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 520)
    }

    // MARK: - Derived UI text

    private var headerSymbolName: String {
        switch job.state {
        case .done: return "checkmark.seal"
        case .failed: return "exclamationmark.triangle"
        case .running: return "arrow.up.doc"
        default: return "arrow.up.doc"
        }
    }

    private var headerSubtitle: String {
        switch job.state {
        case .idle:
            return "Zieh eine Datei in dieses Fenster, um den Upload zu starten."
        case .ready:
            if settingsStore.hasMinimumCredentials == false {
                return "Datei erkannt. Bitte zuerst Settings vervollständigen."
            }
            return "Datei erkannt. Du kannst jetzt den Upload starten."
        case .running(let phase, _, _):
            return subtitleForPhase(phase)
        case .done:
            return "Fertig. Link ist bereit."
        case .failed(let message):
            return message
        }
    }

    private func subtitleForPhase(_ phase: TransferJobCoordinator.Phase) -> String {
        switch phase {
        case .cleaning:
            return "Remote wird geleert."
        case .uploading:
            return "Upload läuft."
        case .triggering:
            return "API wird gestartet."
        case .polling:
            return "Verarbeitung läuft."
        }
    }

    private var dropZoneTitle: String {
        switch job.state {
        case .idle:
            return isDropTargeted ? "Loslassen zum Auswählen" : "Datei hier ablegen"
        case .ready:
            return "Bereit zum Start"
        case .running:
            return "Bitte warten"
        case .done:
            return "Ergebnis"
        case .failed:
            return "Fehler"
        }
    }

    private var dropZoneDetailText: String? {
        switch job.state {
        case .ready(let fileURL):
            return fileURL.lastPathComponent
        case .running(_, let progress, _):
            return "\(Int(progress * 100)) %"
        case .done(let url):
            return url.absoluteString
        case .failed(let message):
            return message
        default:
            return "Nur eine Datei. Ein Job zur Zeit."
        }
    }

    private var borderColor: Color {
        if case .running = job.state { return .secondary.opacity(0.6) }
        if case .done = job.state { return .green.opacity(0.7) }
        if case .failed = job.state { return .red.opacity(0.7) }
        return isDropTargeted ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.35)
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard job.isBusy == false else {
            job.pushStatus("Drop ignoriert. Job läuft bereits.")
            return false
        }

        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            job.pushStatus("Drop fehlgeschlagen. Keine Datei-URL.")
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            DispatchQueue.main.async {
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    job.pushStatus("Fehler beim Lesen der Datei.")
                    job.resetToIdle()
                    return
                }

                _ = job.acceptDroppedFile(url)
            }
        }

        return true
    }

    // MARK: - Actions

    private func startJob(fileURL: URL) {
        guard settingsStore.hasMinimumCredentials else {
            job.pushStatus("Start blockiert. Bitte Settings vervollständigen.")
            return
        }

        let snapshot = currentSettingsSnapshot()
        job.start(fileURL: fileURL, settings: snapshot)
    }

    private func retryWithLatestSettings() {
        guard settingsStore.hasMinimumCredentials else {
            job.pushStatus("Retry blockiert. Bitte Settings vervollständigen.")
            return
        }

        let snapshot = currentSettingsSnapshot()
        job.retryIfPossible(settings: snapshot)
    }

    private func currentSettingsSnapshot() -> TransferJobCoordinator.SettingsSnapshot {
        TransferJobCoordinator.SettingsSnapshot(
            sftpHost: settingsStore.sftpHost,
            sftpPort: settingsStore.sftpPort,
            sftpUsername: settingsStore.sftpUsername,
            sftpPassword: settingsStore.sftpPassword,
            apiBaseURLString: settingsStore.apiBaseURLString,
            uploadToken: settingsStore.uploadToken
        )
    }

    // MARK: - Helpers

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        job.pushStatus("Link kopiert")
    }

    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
        job.pushStatus("Link geöffnet")
    }
}

private struct CircularProgressRing: View {

    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.25), lineWidth: 8)

            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(.primary, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text("\(Int(max(0, min(1, progress)) * 100))")
                .font(.headline.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .animation(.snappy, value: progress)
    }
}

#Preview {
    ContentView()
        .frame(width: 620, height: 520)
}

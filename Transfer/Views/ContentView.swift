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

    @State private var toast: ToastModel? = nil
    @State private var lastAutoCopiedURL: String? = nil

    private let openFilesNotification = Notification.Name("transfer.openFileURLs")

    var body: some View {
        ZStack {
            Color(nsColor: .windowBackgroundColor)
                .ignoresSafeArea()

            // Subtiles Drag-Highlight, kein Rahmen
            if isDropTargeted {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
                    .padding(10)
                    .transition(.opacity)
            }

            content
                .padding(28)
        }
        .contentShape(Rectangle())
        .onDrop(of: [UTType.fileURL], isTargeted: $isDropTargeted) { providers in
            handleDrop(providers)
        }
        .onReceive(NotificationCenter.default.publisher(for: openFilesNotification)) { note in
            guard let urls = note.object as? [URL], let first = urls.first else { return }
            acceptAndMaybeStart(first)
        }
        .onChange(of: job.state) { _, newValue in
            if case .done(let url) = newValue {
                autoCopyIfNeeded(url)
                showToast("Link kopiert")
            }
        }
        .toast($toast)
        .onAppear {
            Log.info("App launched \(BuildInfo.fullVersionString)")
        }
    }

    private var content: some View {
        VStack(spacing: 14) {

            Image(systemName: headerSymbolName)
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            Text("Transfer")
                .font(.title2.weight(.semibold))

            Text(subtitleText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            mainBlock

            actionRow
        }
    }

    @ViewBuilder
    private var mainBlock: some View {
        switch job.state {

        case .running(_, let progress, _):
            CircularProgressRing(progress: progress)
                .frame(width: 96, height: 96)
                .accessibilityLabel("Fortschritt")
                .accessibilityValue("\(Int(progress * 100)) Prozent")
                .padding(.top, 6)

        case .done(let url):
            Text(url.absoluteString)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.top, 4)

        case .failed(let message):
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.tail)
                .padding(.top, 4)

        case .ready(let fileURL):
            Text(fileURL.lastPathComponent)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .truncationMode(.middle)
                .padding(.top, 4)

        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var actionRow: some View {
        switch job.state {

        case .done(let resultURL):
            HStack(spacing: 10) {
                iconButton(help: "Copy", systemName: "doc.on.doc") {
                    copyToClipboard(resultURL.absoluteString)
                    showToast("Kopiert")
                }

                iconButton(help: "Open", systemName: "arrow.up.right.square") {
                    NSWorkspace.shared.open(resultURL)
                    showToast("Geöffnet")
                }
                .buttonStyle(.borderedProminent)

                iconButton(help: "Neue Datei", systemName: "plus") {
                    lastAutoCopiedURL = nil
                    job.resetToIdle()
                }
            }
            .controlSize(.large)
            .padding(.top, 10)

        case .failed:
            HStack(spacing: 10) {
                iconButton(help: "Retry", systemName: "arrow.clockwise") {
                    retryWithLatestSettings()
                }
                .buttonStyle(.borderedProminent)
                .disabled(settingsStore.hasMinimumCredentials == false)

                iconButton(help: "Reset", systemName: "xmark") {
                    lastAutoCopiedURL = nil
                    job.resetToIdle()
                }
            }
            .controlSize(.large)
            .padding(.top, 10)

        default:
            EmptyView()
        }
    }

    private func iconButton(help: String, systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 36, height: 30)
        }
        .help(help)
        .buttonStyle(.bordered)
    }

    private var headerSymbolName: String {
        switch job.state {
        case .done: return "checkmark.seal"
        case .failed: return "exclamationmark.triangle"
        case .running: return "arrow.up.doc"
        default: return "arrow.up.doc"
        }
    }

    private var subtitleText: String {
        switch job.state {
        case .idle:
            if settingsStore.hasMinimumCredentials == false {
                return "Settings fehlen. ⌘, öffnen. Dann Datei ablegen."
            }
            return isDropTargeted ? "Loslassen zum Starten." : "Datei hier ablegen."
        case .ready:
            if settingsStore.hasMinimumCredentials == false {
                return "Settings fehlen. Upload kann nicht starten."
            }
            return "Starte …"
        case .running(let phase, _, _):
            return subtitleForPhase(phase)
        case .done:
            return "Fertig. Link ist bereit."
        case .failed:
            return "Upload fehlgeschlagen."
        }
    }

    private func subtitleForPhase(_ phase: TransferJobCoordinator.Phase) -> String {
        switch phase {
        case .cleaning: return "Remote wird geleert."
        case .uploading: return "Upload läuft."
        case .triggering: return "API wird gestartet."
        case .polling: return "Verarbeitung läuft."
        }
    }

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard job.isBusy == false else { return false }

        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            DispatchQueue.main.async {
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    return
                }
                acceptAndMaybeStart(url)
            }
        }

        return true
    }

    private func acceptAndMaybeStart(_ url: URL) {
        guard job.isBusy == false else { return }

        _ = job.acceptDroppedFile(url)

        guard settingsStore.hasMinimumCredentials else {
            showToast("Settings fehlen")
            return
        }

        let snapshot = currentSettingsSnapshot()
        job.start(fileURL: url, settings: snapshot)
    }

    private func retryWithLatestSettings() {
        guard settingsStore.hasMinimumCredentials else {
            showToast("Settings fehlen")
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

    private func autoCopyIfNeeded(_ url: URL) {
        let s = url.absoluteString
        guard lastAutoCopiedURL != s else { return }
        copyToClipboard(s)
        lastAutoCopiedURL = s
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func showToast(_ message: String) {
        toast = ToastModel(message: message)
    }
}

private struct CircularProgressRing: View {

    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(.secondary.opacity(0.20), lineWidth: 10)

            Circle()
                .trim(from: 0, to: max(0, min(1, progress)))
                .stroke(.primary, style: StrokeStyle(lineWidth: 10, lineCap: .round))
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
        .environment(SettingsStore())
        .frame(width: 440, height: 440)
}

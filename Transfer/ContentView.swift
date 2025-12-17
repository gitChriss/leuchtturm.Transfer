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

    enum JobState: Equatable {
        case idle
        case ready(fileURL: URL)
        case running(progress: Double, filename: String)
        case done(resultURL: URL)
        case error(message: String)
    }

    @State private var isDropTargeted: Bool = false
    @State private var state: JobState = .idle
    @State private var statusLines: [String] = []

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
            pushStatus("Bereit")
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

            if case .running(let progress, _) = state {
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
            switch state {
            case .ready:
                Button("Start") { startDummyRun() }
                    .buttonStyle(.borderedProminent)

                Button("Zurücksetzen") { resetToIdle() }
                    .buttonStyle(.bordered)

            case .running:
                Button("Abbrechen") { cancelDummyRun() }
                    .buttonStyle(.bordered)

            case .done(let resultURL):
                Button("Copy") { copyToClipboard(resultURL.absoluteString) }
                    .buttonStyle(.bordered)

                Button("Open") { openURL(resultURL) }
                    .buttonStyle(.borderedProminent)

                Button("Neue Datei") { resetToIdle() }
                    .buttonStyle(.bordered)

            case .error:
                Button("Retry") { resetToIdle() }
                    .buttonStyle(.borderedProminent)

            default:
                EmptyView()
            }
        }
        .animation(.snappy, value: state)
    }

    private var statusArea: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider()
                .padding(.top, 6)

            Text("Status")
                .font(.headline)

            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(statusLines.indices.reversed(), id: \.self) { idx in
                        Text(statusLines[idx])
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
        switch state {
        case .done: return "checkmark.seal"
        case .error: return "exclamationmark.triangle"
        case .running: return "arrow.up.doc"
        default: return "arrow.up.doc"
        }
    }

    private var headerSubtitle: String {
        switch state {
        case .idle:
            return "Zieh eine Datei in dieses Fenster, um den Upload zu starten."
        case .ready:
            return "Datei erkannt. Du kannst jetzt den Upload starten."
        case .running:
            return "Upload und Verarbeitung laufen."
        case .done:
            return "Fertig. Link ist bereit."
        case .error(let message):
            return message
        }
    }

    private var dropZoneTitle: String {
        switch state {
        case .idle:
            return isDropTargeted ? "Loslassen zum Auswählen" : "Datei hier ablegen"
        case .ready:
            return "Bereit zum Start"
        case .running:
            return "Bitte warten"
        case .done:
            return "Ergebnis"
        case .error:
            return "Fehler"
        }
    }

    private var dropZoneDetailText: String? {
        switch state {
        case .ready(let fileURL):
            return fileURL.lastPathComponent
        case .running(let progress, _):
            return "\(Int(progress * 100)) %"
        case .done(let url):
            return url.absoluteString
        case .error(let message):
            return message
        default:
            return "Nur eine Datei. Ein Job zur Zeit."
        }
    }

    private var borderColor: Color {
        if case .running = state { return .secondary.opacity(0.6) }
        if case .done = state { return .green.opacity(0.7) }
        if case .error = state { return .red.opacity(0.7) }
        return isDropTargeted ? Color.accentColor.opacity(0.9) : Color.secondary.opacity(0.35)
    }

    private var isBusy: Bool {
        if case .running = state { return true }
        return false
    }

    // MARK: - Drop handling

    private func handleDrop(_ providers: [NSItemProvider]) -> Bool {
        guard isBusy == false else {
            pushStatus("Drop ignoriert. Job läuft bereits.")
            return false
        }

        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }) else {
            pushStatus("Drop fehlgeschlagen. Keine Datei-URL.")
            return false
        }

        provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
            DispatchQueue.main.async {
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else {
                    state = .error(message: "Datei konnte nicht gelesen werden.")
                    pushStatus("Fehler beim Lesen der Datei.")
                    return
                }

                state = .ready(fileURL: url)
                pushStatus("Datei ausgewählt: \(url.lastPathComponent)")
            }
        }

        return true
    }

    // MARK: - Actions (dummy for Chunk 2)

    private func startDummyRun() {
        guard case .ready(let fileURL) = state else { return }

        let filename = fileURL.lastPathComponent

        pushStatus("Start: \(filename)")
        pushStatus("Hinweis: Upload und API kommen in späteren Chunks.")

        state = .running(progress: 0.0, filename: filename)

        Task { @MainActor in
            for step in 1...100 {
                try? await Task.sleep(nanoseconds: 30_000_000) // 0.03s

                if case .running(_, let keepFilename) = state {
                    state = .running(progress: Double(step) / 100.0, filename: keepFilename)
                } else {
                    return
                }
            }

            if case .running(_, let finalFilename) = state {
                let demo = URL(string: "https://transfer.fotostudio-sichtweisen.de/\(finalFilename)")!
                state = .done(resultURL: demo)
                pushStatus("Done: \(demo.absoluteString)")
            }
        }
    }

    private func cancelDummyRun() {
        pushStatus("Abgebrochen")
        resetToIdle()
    }

    private func resetToIdle() {
        state = .idle
        pushStatus("Zurückgesetzt")
    }

    // MARK: - Helpers

    private func pushStatus(_ line: String) {
        statusLines.append(line)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        pushStatus("Link kopiert")
    }

    private func openURL(_ url: URL) {
        NSWorkspace.shared.open(url)
        pushStatus("Link geöffnet")
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

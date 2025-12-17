//
//  SettingsView.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import SwiftUI

struct SettingsView: View {

    @Bindable var store: SettingsStore
    @State private var toast: ToastModel? = nil

    var body: some View {
        VStack(spacing: 14) {

            header

            Form {
                Section {
                    TextField("Host", text: $store.sftpHost, prompt: Text(AppConstants.defaultSFTPHost))
                        .textContentType(.URL)
                        .onChange(of: store.sftpHost) { _, _ in store.resetSFTPStatus() }

                    TextField("Port", value: $store.sftpPort, format: .number)
                        .monospacedDigit()
                        .onChange(of: store.sftpPort) { _, _ in store.resetSFTPStatus() }

                    TextField("User", text: $store.sftpUsername, prompt: Text("fotostrm_3"))
                        .textContentType(.username)
                        .onChange(of: store.sftpUsername) { _, _ in store.resetSFTPStatus() }

                    SecureField("Passwort", text: $store.sftpPassword)
                        .textContentType(.password)
                        .onChange(of: store.sftpPassword) { _, _ in store.resetSFTPStatus() }

                } header: {
                    sftpHeader
                }

                Section("API") {
                    TextField("URL", text: $store.apiBaseURLString, prompt: Text(AppConstants.defaultAPIBaseURLString))
                        .textContentType(.URL)

                    SecureField("Token", text: $store.uploadToken)
                }
            }
            .formStyle(.grouped)

            footerBar
        }
        .padding(18)
        .toast($toast)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Einstellungen")
                    .font(.title2.weight(.semibold))
            }

            Spacer()

            Image(systemName: store.hasMinimumCredentials ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(store.hasMinimumCredentials ? .green : .orange)
                .help(store.hasMinimumCredentials ? "Einstellungen vollständig" : "Einstellungen unvollständig")
        }
        .padding(.bottom, 4)
    }

    private var sftpHeader: some View {
        HStack(spacing: 10) {
            Text("SFTP")

            Spacer()

            sftpStatusBadge

            Button {
                Task {
                    await store.checkSFTPConnection()
                    switch store.sftpStatus {
                    case .ok:
                        toast = ToastModel(message: "SFTP Verbindung ok")
                    case .failed(let message):
                        toast = ToastModel(message: message)
                    default:
                        break
                    }
                }
            } label: {
                Text("Prüfen")
            }
            .buttonStyle(.borderless)
            .disabled(store.sftpStatus == .checking)
        }
    }

    @ViewBuilder
    private var sftpStatusBadge: some View {
        switch store.sftpStatus {
        case .unknown:
            EmptyView()

        case .checking:
            ProgressView()
                .controlSize(.small)
                .help("SFTP Verbindung wird geprüft")

        case .ok:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .help("SFTP Verbindung ok")

        case .failed:
            Image(systemName: "xmark.circle.fill")
                .foregroundStyle(.red)
                .help("SFTP Verbindung fehlgeschlagen")
        }
    }

    private var footerBar: some View {
        HStack(spacing: 10) {

            Button {
                _ = store.save()
                toast = ToastModel(message: "Gespeichert")
            } label: {
                Label("Speichern", systemImage: "checkmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 34, height: 28)
            }
            .help("Speichern")
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Button {
                store.reload()
                toast = ToastModel(message: "Neu geladen")
            } label: {
                Label("Neu laden", systemImage: "arrow.clockwise")
                    .labelStyle(.iconOnly)
                    .frame(width: 34, height: 28)
            }
            .help("Neu laden")
            .buttonStyle(.bordered)
            .controlSize(.large)

            Spacer()

            Button(role: .destructive) {
                store.clearAll()
                toast = ToastModel(message: "Gelöscht")
            } label: {
                Label("Löschen", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(width: 34, height: 28)
            }
            .help("Löschen")
            .buttonStyle(.bordered)
            .controlSize(.large)
        }
        .padding(.top, 2)
    }
}

#Preview {
    SettingsView(store: SettingsStore())
        .frame(width: AppConstants.settingsWindowWidth, height: AppConstants.settingsWindowHeight)
}

//
//  SettingsView.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import SwiftUI

struct SettingsView: View {

    @Bindable var store: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {

            Text("Settings")
                .font(.title2.weight(.semibold))

            Form {
                Section("FTP") {
                    TextField("Host", text: $store.sftpHost)

                    TextField("Port", value: $store.sftpPort, format: .number)

                    TextField("User", text: $store.sftpUsername)

                    SecureField("Passwort", text: $store.sftpPassword)
                }

                Section("API") {
                    TextField("URL", text: $store.apiBaseURLString)

                    SecureField("Token", text: $store.uploadToken)
                }
            }

            HStack(spacing: 10) {
                Button("Save") {
                    _ = store.save()
                }
                .buttonStyle(.borderedProminent)

                Button("Reload") {
                    store.reload()
                }
                .buttonStyle(.bordered)

                Spacer()

                Button("Clear") {
                    store.clearAll()
                }
                .buttonStyle(.bordered)
                .tint(.red)

                if let msg = store.lastSaveMessage {
                    Text(msg)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
    }
}

#Preview {
    SettingsView(store: SettingsStore())
        .frame(width: 520, height: 380)
}

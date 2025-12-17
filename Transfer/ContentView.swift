//
//  ContentView.swift
//  Transfer
//
//  Created by Christian Ruppelt on 17.12.25.
//

import SwiftUI

struct ContentView: View {

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.up.doc")
                .font(.system(size: 44, weight: .semibold))
                .symbolRenderingMode(.hierarchical)

            VStack(spacing: 6) {
                Text("Transfer")
                    .font(.title2.weight(.semibold))

                Text("Zieh eine Datei in dieses Fenster, um den Upload zu starten.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 420)
            }

            Divider()
                .padding(.vertical, 8)

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
        .padding(24)
        .onAppear {
            Log.info("App launched \(BuildInfo.fullVersionString)")
        }
    }
}

#Preview {
    ContentView()
        .frame(width: 620, height: 420)
}

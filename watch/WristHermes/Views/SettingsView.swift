import SwiftUI

/// Settings screen — manually configure Bridge URL, trigger Bonjour scan,
/// and see connection status.
struct SettingsView: View {
    @ObservedObject var bridgeClient: BridgeClient
    @ObservedObject var bonjour: BonjourBrowser

    var currentURL: URL?

    @State private var urlText: String = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                // Connection status
                Section("Status") {
                    HStack {
                        Circle()
                            .fill(bridgeClient.isConnected ? Color.green : Color.red)
                            .frame(width: 8, height: 8)
                        Text(bridgeClient.isConnected ? "Connected" : "Disconnected")
                            .font(.caption)
                    }
                }

                // Manual URL
                Section("Bridge URL") {
                    TextField("http://192.168.1.x:3847", text: $urlText)
                        .font(.caption2)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)

                    Button("Connect") {
                        guard let url = URL(string: urlText) else { return }
                        bridgeClient.updateBaseURL(url)
                        Task {
                            bridgeClient.isConnected = await bridgeClient.checkHealth()
                            if bridgeClient.isConnected { dismiss() }
                        }
                    }
                    .disabled(urlText.isEmpty)
                }

                // Bonjour
                Section("Bonjour") {
                    if bonjour.isScanning {
                        HStack {
                            ProgressView()
                                .scaleEffect(0.7)
                            Text("Scanning…")
                                .font(.caption)
                        }
                    }

                    ForEach(bonjour.discoveredURLs, id: \.absoluteString) { url in
                        Button {
                            bridgeClient.updateBaseURL(url)
                            Task {
                                bridgeClient.isConnected = await bridgeClient.checkHealth()
                                if bridgeClient.isConnected { dismiss() }
                            }
                        } label: {
                            HStack {
                                Image(systemName: "wifi")
                                    .font(.caption)
                                Text(url.absoluteString)
                                    .font(.caption2)
                                    .lineLimit(1)
                            }
                        }
                    }

                    if bonjour.discoveredURLs.isEmpty && !bonjour.isScanning {
                        Button("Rescan") {
                            bonjour.startBrowsing()
                        }
                    }
                }

                // About
                Section("About") {
                    Text("WristHermes v0.1.0")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
            .onAppear {
                urlText = currentURL?.absoluteString ?? ""
                bonjour.startBrowsing()
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

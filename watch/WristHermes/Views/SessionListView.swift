import SwiftUI

struct SessionListView: View {
    @ObservedObject var bridgeClient: BridgeClient
    @ObservedObject var sessionStore: SessionStore
    @Binding var currentSessionId: String?

    /// Called when the user picks a session to load its history
    let onSelect: (String) -> Void

    @State private var remoteSessions: [SessionInfo] = []
    @State private var isLoading = false

    var body: some View {
        List {
            // New chat
            Section {
                Button {
                    currentSessionId = nil
                    onSelect("")
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.green)
                        Text("New Chat")
                            .font(.caption)
                    }
                }
            }

            // Sessions from Bridge
            Section("Recent") {
                if isLoading {
                    ProgressView()
                        .padding(.vertical, 8)
                } else if remoteSessions.isEmpty {
                    Text("No sessions yet")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    ForEach(remoteSessions) { session in
                        Button {
                            currentSessionId = session.id
                            onSelect(session.id)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(session.title ?? "Untitled")
                                        .font(.caption)
                                        .lineLimit(1)
                                    if let updated = session.updatedAt {
                                        Text(formatDate(updated))
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                Spacer()
                                if session.id == currentSessionId {
                                    Image(systemName: "checkmark")
                                        .font(.caption)
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Sessions")
        .task { await loadSessions() }
    }

    private func loadSessions() async {
        isLoading = true
        do {
            remoteSessions = try await bridgeClient.listSessions()
        } catch {
            print("Failed to load sessions: \(error)")
        }
        isLoading = false
    }

    private func formatDate(_ iso: String) -> String {
        // ISO 8601 → "MM-dd HH:mm"
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso)
            ?? ISO8601DateFormatter().date(from: iso)
        else { return String(iso.prefix(10)) }

        let df = DateFormatter()
        df.dateFormat = "MM-dd HH:mm"
        return df.string(from: date)
    }
}

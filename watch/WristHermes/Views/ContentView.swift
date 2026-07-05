import SwiftUI

/// Main chat screen — message list + input bar.
/// Detects WristHermes Bridge via Bonjour or falls back to manual URL.
struct ContentView: View {
    @StateObject private var bridgeClient = BridgeClient()
    @StateObject private var bonjour = BonjourBrowser()
    @StateObject private var sessionStore = SessionStore()

    @State private var messages: [Message] = []
    @State private var inputText = ""
    @State private var isLoading = false
    @State private var currentSessionId: String? = nil
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Connection status banner
                if !bonjour.discoveredURLs.isEmpty && !bridgeClient.isConnected {
                    HStack {
                        Image(systemName: "wifi")
                            .font(.caption2)
                        Text("Found Bridge — tap to connect")
                            .font(.caption2)
                    }
                    .padding(.vertical, 2)
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.2))
                    .onTapGesture { connectFirstDiscovered() }
                }

                // Messages
                ScrollViewReader { proxy in
                    List {
                        if messages.isEmpty {
                            Text("Ask anything…")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .listRowBackground(Color.clear)
                        }
                        ForEach(messages) { msg in
                            MessageBubble(message: msg)
                                .id(msg.id)
                                .listRowInsets(EdgeInsets(top: 2, leading: 0, bottom: 2, trailing: 0))
                        }
                    }
                    .listStyle(.plain)
                    .onChange(of: messages.count) { _, _ in
                        if let last = messages.last {
                            withAnimation {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }

                // Input bar
                InputView(
                    text: $inputText,
                    isLoading: isLoading,
                    onSend: sendMessage
                )
            }
            .navigationTitle("Hermes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SessionListView(
                            bridgeClient: bridgeClient,
                            sessionStore: sessionStore,
                            currentSessionId: $currentSessionId,
                            onSelect: loadSession
                        )
                    } label: {
                        Image(systemName: "list.bullet.rectangle")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showSettings = true } label: {
                        Image(systemName: "gearshape")
                    }
                }
            }
            .sheet(isPresented: $showSettings) {
                SettingsView(
                    bridgeClient: bridgeClient,
                    bonjour: bonjour,
                    currentURL: bridgeClient.baseURL
                )
            }
            .onAppear {
                bonjour.startBrowsing()
            }
            .onDisappear {
                bonjour.stopBrowsing()
            }
        }
    }

    private func connectFirstDiscovered() {
        guard let url = bonjour.discoveredURLs.first else { return }
        bridgeClient.updateBaseURL(url)
        Task { bridgeClient.isConnected = await bridgeClient.checkHealth() }
    }

    private func sendMessage() {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isLoading else { return }

        let userMsg = Message(role: .user, content: text)
        messages.append(userMsg)
        inputText = ""
        isLoading = true

        Task {
            do {
                let response = try await bridgeClient.sendMessage(text, sessionId: currentSessionId)
                if let sid = response.sessionId, currentSessionId == nil {
                    currentSessionId = sid
                }
                let reply = response.output ?? "(empty)"
                let assistantMsg = Message(role: .assistant, content: reply)
                await MainActor.run {
                    messages.append(assistantMsg)
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    messages.append(Message(role: .assistant, content: "Error: \(error.localizedDescription)"))
                    isLoading = false
                }
            }
        }
    }

    private func loadSession(_ sessionId: String) {
        currentSessionId = sessionId
        messages = []
        // TODO v0.2: fetch session history from Bridge
    }
}

#Preview {
    ContentView()
}

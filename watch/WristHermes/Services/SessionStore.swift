import Foundation

/// Lightweight local cache of recent sessions so the session list loads
/// instantly even without a network round-trip.
class SessionStore: ObservableObject {
    @Published var sessions: [ChatSession] = []
    private let defaults = UserDefaults.standard
    private let key = "wristhermes_sessions"

    init() {
        load()
    }

    func save(_ sessions: [ChatSession]) {
        self.sessions = sessions
        guard let data = try? JSONEncoder().encode(sessions) else { return }
        defaults.set(data, forKey: key)
    }

    private func load() {
        guard let data = defaults.data(forKey: key),
              let decoded = try? JSONDecoder().decode([ChatSession].self, from: data)
        else { return }
        self.sessions = decoded
    }
}

import Foundation

// MARK: - Bridge HTTP Client

class BridgeClient: ObservableObject {
    private(set) var baseURL: URL
    @Published var isConnected = false

    init(baseURL: URL = URL(string: "http://localhost:3847")!) {
        self.baseURL = baseURL
    }

    func updateBaseURL(_ url: URL) {
        self.baseURL = url
    }

    /// POST /api/chat — send a message and wait for the full reply
    func sendMessage(_ input: String, sessionId: String? = nil) async throws -> ChatResponse {
        var body: [String: Any] = ["input": input]
        if let sid = sessionId { body["session_id"] = sid }

        var request = URLRequest(url: baseURL.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        request.timeoutInterval = 300 // 5 min for long replies

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            throw BridgeError.serverError(status: (response as? HTTPURLResponse)?.statusCode ?? 0)
        }
        return try JSONDecoder().decode(ChatResponse.self, from: data)
    }

    /// GET /api/sessions — list recent sessions
    func listSessions() async throws -> [SessionInfo] {
        let request = URLRequest(url: baseURL.appendingPathComponent("api/sessions"))
        let (data, _) = try await URLSession.shared.data(for: request)
        return try JSONDecoder().decode([SessionInfo].self, from: data)
    }

    /// GET /health — check bridge connectivity
    func checkHealth() async -> Bool {
        do {
            let request = URLRequest(url: baseURL.appendingPathComponent("health"))
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }
}

// MARK: - Response Types

struct ChatResponse: Codable {
    let ok: Bool
    let status: String
    let sessionId: String?
    let runId: String?
    let output: String?
    let reasoning: String?

    enum CodingKeys: String, CodingKey {
        case ok, status, output, reasoning
        case sessionId = "session_id"
        case runId = "run_id"
    }
}

struct SessionInfo: Codable, Identifiable {
    let id: String
    let title: String?
    let source: String?
    let createdAt: String?
    let updatedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, title, source
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

enum BridgeError: Error {
    case serverError(status: Int)
    case notFound
}

import Foundation

struct ChatSession: Identifiable, Codable {
    let id: String
    var title: String
    let createdAt: Date
    var updatedAt: Date

    init(id: String, title: String = "New Chat", createdAt: Date = Date(), updatedAt: Date = Date()) {
        self.id = id
        self.title = title
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

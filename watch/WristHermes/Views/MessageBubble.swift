import SwiftUI

struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.role == .user { Spacer(minLength: 20) }

            Text(message.content)
                .font(.caption)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(message.role == .user ? Color.blue : Color.gray.opacity(0.3))
                .foregroundColor(message.role == .user ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 12))

            if message.role == .assistant { Spacer(minLength: 20) }
        }
    }
}

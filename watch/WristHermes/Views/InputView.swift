import SwiftUI

struct InputView: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    @State private var isDictating = false

    var body: some View {
        HStack(spacing: 4) {
            // Dictation button (watchOS uses the built-in dictation)
            Button {
                isDictating.toggle()
                // watchOS automatically invokes dictation when TextField is focused;
                // this button is a visual hint. Real voice input uses `.dictation` on TextField.
            } label: {
                Image(systemName: isDictating ? "mic.fill" : "mic")
                    .font(.caption)
                    .foregroundColor(isDictating ? .red : .secondary)
            }
            .buttonStyle(.plain)

            // Text input
            TextField("Message...", text: $text)
                .textFieldStyle(.plain)
                .font(.caption2)

            // Send button
            Button(action: onSend) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundColor(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .gray : .blue)
                }
            }
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isLoading)
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial)
    }
}

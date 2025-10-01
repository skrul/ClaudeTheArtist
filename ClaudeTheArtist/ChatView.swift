//
//  ChatView.swift
//  ClaudeTheArtist
//
//  Chat interface for interacting with Claude
//

import SwiftUI

struct ChatView: View {
    var service: ClaudeWrapperService
    @State private var inputText = ""
    @State private var isProcessing = false

    var body: some View {
        VStack(spacing: 0) {
            // Messages area
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(service.messages) { message in
                            MessageRow(message: message)
                                .id(message.id)
                        }
                    }
                    .padding()
                }
                .onChange(of: service.messages.count) { _ in
                    // Auto-scroll to bottom when new messages arrive
                    if let lastMessage = service.messages.last {
                        withAnimation {
                            proxy.scrollTo(lastMessage.id, anchor: .bottom)
                        }
                    }
                }
            }

            Divider()

            // Input area
            HStack(spacing: 8) {
                TextField("Type a message...", text: $inputText, axis: .vertical)
                    .textFieldStyle(.plain)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
                    .cornerRadius(8)
                    .lineLimit(1...5)
                    .disabled(isProcessing || !service.isConnected)
                    .onSubmit {
                        sendMessage()
                    }

                Button(action: sendMessage) {
                    Image(systemName: "paperplane.fill")
                        .foregroundColor(canSend ? .blue : .gray)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
    }

    private var canSend: Bool {
        !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isProcessing
            && service.isConnected
    }

    private func sendMessage() {
        guard canSend else { return }

        let message = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        inputText = ""
        isProcessing = true

        Task {
            do {
                try await service.sendQuery(message)
            } catch {
                print("Error sending message: \(error)")
            }
            isProcessing = false
        }
    }
}

struct MessageRow: View {
    let message: ChatMessage

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            // Icon
            Image(systemName: iconName)
                .foregroundColor(iconColor)
                .frame(width: 20)

            // Message content
            VStack(alignment: .leading, spacing: 4) {
                Text(message.text)
                    .textSelection(.enabled)
                    .font(.system(size: 13))

                Text(message.timestamp, style: .time)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private var iconName: String {
        switch message.role {
        case .user:
            return "person.circle.fill"
        case .assistant:
            return "sparkles"
        case .system:
            return "info.circle"
        }
    }

    private var iconColor: Color {
        switch message.role {
        case .user:
            return .blue
        case .assistant:
            return .purple
        case .system:
            return .gray
        }
    }
}

#Preview {
    ChatView(service: ClaudeWrapperService())
        .frame(width: 300, height: 600)
}

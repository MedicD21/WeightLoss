import SwiftUI
import SwiftData

/// Chat interface with Logged AI assistant
struct ChatView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \ChatMessage.timestamp) private var messages: [ChatMessage]

    @StateObject private var viewModel = ChatViewModel()
    @State private var inputText = ""
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: Theme.Spacing.md) {
                            ForEach(filteredMessages) { message in
                                ChatBubble(message: message)
                                    .id(message.id)
                            }

                            if viewModel.isLoading {
                                TypingIndicator()
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.md)
                        .padding(.vertical, Theme.Spacing.lg)
                    }
                    .onChange(of: filteredMessages.count) { _, _ in
                        withAnimation {
                            proxy.scrollTo(filteredMessages.last?.id, anchor: .bottom)
                        }
                    }
                }

                Divider()
                    .background(Theme.Colors.border)

                // Input
                ChatInputBar(
                    text: $inputText,
                    isLoading: viewModel.isLoading,
                    onSend: sendMessage
                )
                .focused($isInputFocused)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Logged")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Done") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button {
                            // Clear conversation
                        } label: {
                            Label("New Conversation", systemImage: "plus.message")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            }
        }
        .onAppear {
            addWelcomeMessageIfNeeded()
        }
    }

    private var filteredMessages: [ChatMessage] {
        messages.filter { $0.role != .tool && $0.role != .system }
    }

    private func sendMessage() {
        guard !inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        let text = inputText
        inputText = ""

        Task {
            await viewModel.sendMessage(text, modelContext: modelContext)
        }
    }

    private func addWelcomeMessageIfNeeded() {
        guard messages.isEmpty else { return }

        // Get user ID from profile
        let descriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? modelContext.fetch(descriptor).first else { return }

        let welcomeMessage = ChatMessage(
            userId: profile.id,
            role: .assistant,
            content: "Hi! I'm Logged, your fitness assistant. I can help you:\n\n• Log meals and snacks\n• Track water intake\n• Record workouts\n• Answer nutrition questions\n\nJust tell me what you ate or did, and I'll take care of the rest!"
        )
        modelContext.insert(welcomeMessage)
    }
}

// MARK: - Chat Bubble

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        HStack {
            if message.isFromUser {
                Spacer(minLength: 60)
            }

            VStack(alignment: message.isFromUser ? .trailing : .leading, spacing: Theme.Spacing.xxs) {
                Text(message.content)
                    .font(Theme.Typography.body)
                    .foregroundColor(message.isFromUser ? .white : Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.sm)
                    .background(
                        message.isFromUser
                            ? Theme.Colors.accent
                            : Theme.Colors.surface
                    )
                    .cornerRadius(Theme.Radius.large)

                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(Theme.Typography.caption2)
                    .foregroundColor(Theme.Colors.textTertiary)
            }

            if !message.isFromUser {
                Spacer(minLength: 60)
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicator: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Theme.Colors.textSecondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(
                            .easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(Theme.Colors.surface)
            .cornerRadius(Theme.Radius.large)

            Spacer()
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Chat Input Bar

struct ChatInputBar: View {
    @Binding var text: String
    let isLoading: Bool
    let onSend: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            // Photo button
            Button {
                // Open camera/photo picker
            } label: {
                Image(systemName: "camera.fill")
                    .font(.system(size: 20))
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            // Text field
            TextField("Message Logged...", text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textPrimary)
                .padding(.horizontal, Theme.Spacing.sm)
                .padding(.vertical, Theme.Spacing.xs)
                .background(Theme.Colors.surface)
                .cornerRadius(Theme.Radius.large)
                .lineLimit(1...5)
                .onSubmit {
                    if !text.isEmpty {
                        onSend()
                    }
                }

            // Send button
            Button {
                onSend()
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(
                        text.isEmpty || isLoading
                            ? Theme.Colors.textTertiary
                            : Theme.Colors.accent
                    )
            }
            .disabled(text.isEmpty || isLoading)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.sm)
        .background(Theme.Colors.background)
    }
}

#Preview {
    ChatView()
        .environmentObject(AppState())
        .modelContainer(for: [ChatMessage.self, UserProfile.self])
}

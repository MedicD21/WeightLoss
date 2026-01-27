import Foundation
import SwiftData
import Combine

/// View model for chat interface
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var conversationId: String?

    private let apiService = APIService.shared

    func sendMessage(_ text: String, modelContext: ModelContext) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isLoading = true
        defer { isLoading = false }

        // Get user profile
        let descriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? modelContext.fetch(descriptor).first else {
            error = ChatError.noUserProfile
            return
        }

        // Save user message locally
        let userMessage = ChatMessage(
            userId: profile.id,
            role: .user,
            content: text,
            conversationId: conversationId
        )
        modelContext.insert(userMessage)

        do {
            // Send to API
            let response = try await apiService.sendChatMessage(
                message: text,
                conversationId: conversationId
            )

            // Update conversation ID
            conversationId = response.conversationId

            // Save assistant response
            let assistantMessage = ChatMessage(
                userId: profile.id,
                role: .assistant,
                content: response.message,
                conversationId: conversationId
            )

            // Store tool calls if any
            if let toolCalls = response.toolCalls {
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(toolCalls),
                   let json = String(data: data, encoding: .utf8) {
                    assistantMessage.toolCallsJSON = json
                }
            }

            assistantMessage.modelUsed = response.modelUsed
            assistantMessage.tokensUsed = response.tokensUsed
            modelContext.insert(assistantMessage)

            // Handle created entries (meals, workouts, water, etc.)
            if let createdEntries = response.createdEntries {
                await processCreatedEntries(createdEntries, profile: profile, modelContext: modelContext)
            }

        } catch {
            self.error = error

            // Save error message
            let errorMessage = ChatMessage(
                userId: profile.id,
                role: .assistant,
                content: "Sorry, I couldn't process that request. Please try again.",
                conversationId: conversationId
            )
            modelContext.insert(errorMessage)
        }
    }

    func analyzeImage(_ imageData: Data, modelContext: ModelContext) async -> VisionAnalyzeResponse? {
        isLoading = true
        defer { isLoading = false }

        let base64 = imageData.base64EncodedString()

        do {
            return try await apiService.analyzeFood(imageBase64: base64)
        } catch {
            self.error = error
            return nil
        }
    }

    private func processCreatedEntries(
        _ entries: [[String: AnyCodable]],
        profile: UserProfile,
        modelContext: ModelContext
    ) async {
        for entry in entries {
            guard let type = entry["type"]?.value as? String,
                  let data = entry["data"]?.value as? [String: Any] else {
                continue
            }

            switch type {
            case "add_meal":
                if let name = data["name"] as? String,
                   let calories = data["total_calories"] as? Int {
                    // Meal was created on backend, we could sync or just show confirmation
                    print("Meal logged: \(name) - \(calories) calories")
                }

            case "add_water":
                if let amount = data["amount_ml"] as? Int {
                    let entry = WaterEntry(
                        userId: profile.id,
                        amountMl: amount
                    )
                    modelContext.insert(entry)
                }

            case "add_weight":
                if let weight = data["weight_kg"] as? Double {
                    let entry = BodyWeightEntry(
                        userId: profile.id,
                        weightKg: weight
                    )
                    modelContext.insert(entry)
                    profile.currentWeightKg = weight
                }

            case "add_workout":
                if let name = data["name"] as? String,
                   let duration = data["duration_min"] as? Int {
                    print("Workout logged: \(name) - \(duration) min")
                }

            default:
                break
            }
        }
    }
}

enum ChatError: LocalizedError {
    case noUserProfile
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .noUserProfile:
            return "User profile not found"
        case .sendFailed:
            return "Failed to send message"
        }
    }
}

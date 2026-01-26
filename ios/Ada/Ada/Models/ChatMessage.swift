import Foundation
import SwiftData

/// Chat message role
enum MessageRole: String, Codable {
    case user
    case assistant
    case system
    case tool
}

/// Chat message in conversation with AI assistant
@Model
final class ChatMessage {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var localId: String?

    // Message content
    var role: MessageRole
    var content: String
    var timestamp: Date

    // Conversation grouping
    var conversationId: String?

    // Tool calls (stored as JSON)
    var toolCallsJSON: String?

    // Metadata
    var modelUsed: String?
    var tokensUsed: Int?

    // Sync
    var isSynced: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        role: MessageRole,
        content: String,
        timestamp: Date = Date(),
        conversationId: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.localId = UUID().uuidString
        self.role = role
        self.content = content
        self.timestamp = timestamp
        self.conversationId = conversationId
        self.isSynced = false
        self.createdAt = Date()
    }

    var isFromUser: Bool {
        role == .user
    }

    var isFromAssistant: Bool {
        role == .assistant
    }

    var toolCalls: [ToolCall]? {
        guard let json = toolCallsJSON,
              let data = json.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode([ToolCall].self, from: data)
    }
}

/// Tool/function call from AI
struct ToolCall: Codable, Identifiable {
    let id: String
    let name: String
    let arguments: [String: AnyCodable]
}

/// Type-erased Codable wrapper
struct AnyCodable: Codable {
    let value: Any

    init(_ value: Any) {
        self.value = value
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            value = intValue
        } else if let doubleValue = try? container.decode(Double.self) {
            value = doubleValue
        } else if let stringValue = try? container.decode(String.self) {
            value = stringValue
        } else if let boolValue = try? container.decode(Bool.self) {
            value = boolValue
        } else if let arrayValue = try? container.decode([AnyCodable].self) {
            value = arrayValue.map { $0.value }
        } else if let dictValue = try? container.decode([String: AnyCodable].self) {
            value = dictValue.mapValues { $0.value }
        } else {
            value = NSNull()
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch value {
        case let intValue as Int:
            try container.encode(intValue)
        case let doubleValue as Double:
            try container.encode(doubleValue)
        case let stringValue as String:
            try container.encode(stringValue)
        case let boolValue as Bool:
            try container.encode(boolValue)
        case let arrayValue as [Any]:
            try container.encode(arrayValue.map { AnyCodable($0) })
        case let dictValue as [String: Any]:
            try container.encode(dictValue.mapValues { AnyCodable($0) })
        default:
            try container.encodeNil()
        }
    }
}

/// AI chat response
struct ChatResponse: Decodable {
    let message: String
    let role: MessageRole
    let toolCalls: [ToolCall]?
    let conversationId: String
    let modelUsed: String
    let tokensUsed: Int?
    let createdEntries: [[String: AnyCodable]]?

    enum CodingKeys: String, CodingKey {
        case message, role, conversationId, modelUsed, tokensUsed
        case toolCalls = "tool_calls"
        case createdEntries = "created_entries"
    }
}

/// Vision analysis response
struct VisionAnalyzeResponse: Decodable {
    let items: [VisionFoodItem]
    let totals: MacroTotals
    let confidence: Double
    let description: String
    let disclaimer: String
    let modelUsed: String

    enum CodingKeys: String, CodingKey {
        case items, totals, confidence, description, disclaimer
        case modelUsed = "model_used"
    }
}

struct VisionFoodItem: Decodable, Identifiable {
    var id = UUID()
    let name: String
    let portionDescription: String
    let gramsEstimate: Double
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let confidence: Double

    enum CodingKeys: String, CodingKey {
        case name, calories, confidence
        case portionDescription = "portion_description"
        case gramsEstimate = "grams_estimate"
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }

    // Implement custom init for id generation
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.portionDescription = try container.decode(String.self, forKey: .portionDescription)
        self.gramsEstimate = try container.decode(Double.self, forKey: .gramsEstimate)
        self.calories = try container.decode(Int.self, forKey: .calories)
        self.proteinG = try container.decode(Double.self, forKey: .proteinG)
        self.carbsG = try container.decode(Double.self, forKey: .carbsG)
        self.fatG = try container.decode(Double.self, forKey: .fatG)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
    }

    init(
        name: String,
        portionDescription: String,
        gramsEstimate: Double,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        confidence: Double
    ) {
        self.id = UUID()
        self.name = name
        self.portionDescription = portionDescription
        self.gramsEstimate = gramsEstimate
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.confidence = confidence
    }

    func toFoodItem() -> FoodItem {
        FoodItem(
            name: name,
            source: .vision,
            grams: gramsEstimate,
            calories: calories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            confidence: confidence,
            portionDescription: portionDescription
        )
    }
}

struct MacroTotals: Decodable {
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double

    enum CodingKeys: String, CodingKey {
        case calories
        case proteinG = "protein_g"
        case carbsG = "carbs_g"
        case fatG = "fat_g"
    }
}

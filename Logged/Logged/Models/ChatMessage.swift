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

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        print("[TOOLCALL DECODE] Decoding ToolCall...")

        do {
            id = try container.decode(String.self, forKey: .id)
            print("[TOOLCALL DECODE] ✓ id: \(id)")
        } catch {
            print("[TOOLCALL DECODE] ✗ id failed: \(error)")
            throw error
        }

        do {
            name = try container.decode(String.self, forKey: .name)
            print("[TOOLCALL DECODE] ✓ name: \(name)")
        } catch {
            print("[TOOLCALL DECODE] ✗ name failed: \(error)")
            throw error
        }

        do {
            arguments = try container.decode([String: AnyCodable].self, forKey: .arguments)
            print("[TOOLCALL DECODE] ✓ arguments decoded: \(arguments.keys.count) keys")
        } catch {
            print("[TOOLCALL DECODE] ✗ arguments failed: \(error)")
            throw error
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, arguments
    }
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

/// Tool execution result
struct ToolResult: Decodable {
    let toolCallId: String
    let result: AnyCodable?
    let success: Bool
    let error: String?

    enum CodingKeys: String, CodingKey {
        case success, result, error
        case toolCallId = "tool_call_id"
    }
}

/// AI chat response
struct ChatResponse: Decodable {
    let message: String
    let role: MessageRole
    let toolCalls: [ToolCall]?
    let toolResults: [ToolResult]?
    let conversationId: String
    let modelUsed: String
    let tokensUsed: Int?
    let createdEntries: [[String: AnyCodable]]?

    enum CodingKeys: String, CodingKey {
        case message, role, conversationId, modelUsed, tokensUsed
        case toolCalls = "tool_calls"
        case toolResults = "tool_results"
        case createdEntries = "created_entries"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        print("[DECODE] Starting ChatResponse decode")

        message = try container.decode(String.self, forKey: .message)
        print("[DECODE] ✓ message decoded")

        role = try container.decode(MessageRole.self, forKey: .role)
        print("[DECODE] ✓ role decoded")

        conversationId = try container.decode(String.self, forKey: .conversationId)
        print("[DECODE] ✓ conversationId decoded")

        modelUsed = try container.decode(String.self, forKey: .modelUsed)
        print("[DECODE] ✓ modelUsed decoded")

        tokensUsed = try? container.decode(Int.self, forKey: .tokensUsed)
        print("[DECODE] ✓ tokensUsed decoded: \(tokensUsed as Any)")

        // Try to decode toolCalls
        do {
            if container.contains(.toolCalls) {
                print("[DECODE] toolCalls key exists, attempting decode...")
                toolCalls = try container.decode([ToolCall].self, forKey: .toolCalls)
                print("[DECODE] ✓ toolCalls decoded: \(toolCalls?.count ?? 0) items")
            } else {
                print("[DECODE] toolCalls key NOT found in JSON")
                toolCalls = nil
            }
        } catch {
            print("[DECODE] ✗ toolCalls decode FAILED: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .typeMismatch(let type, let context):
                    print("[DECODE] Type mismatch: expected \(type), path: \(context.codingPath)")
                case .keyNotFound(let key, let context):
                    print("[DECODE] Key not found: \(key), path: \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("[DECODE] Value not found for \(type), path: \(context.codingPath)")
                case .dataCorrupted(let context):
                    print("[DECODE] Data corrupted: \(context.debugDescription)")
                @unknown default:
                    break
                }
            }
            toolCalls = nil
        }

        // Try to decode toolResults
        do {
            toolResults = try container.decodeIfPresent([ToolResult].self, forKey: .toolResults)
            print("[DECODE] ✓ toolResults decoded: \(toolResults?.count ?? 0) items")
        } catch {
            print("[DECODE] ✗ toolResults decode FAILED: \(error)")
            toolResults = nil
        }

        // Try to decode createdEntries
        do {
            if container.contains(.createdEntries) {
                print("[DECODE] createdEntries key exists, attempting decode...")
                createdEntries = try container.decode([[String: AnyCodable]].self, forKey: .createdEntries)
                print("[DECODE] ✓ createdEntries decoded: \(createdEntries?.count ?? 0) items")
            } else {
                print("[DECODE] createdEntries key NOT found in JSON")
                createdEntries = nil
            }
        } catch {
            print("[DECODE] ✗ createdEntries decode FAILED: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .typeMismatch(let type, let context):
                    print("[DECODE] Type mismatch: expected \(type), path: \(context.codingPath)")
                case .keyNotFound(let key, let context):
                    print("[DECODE] Key not found: \(key), path: \(context.codingPath)")
                case .valueNotFound(let type, let context):
                    print("[DECODE] Value not found for \(type), path: \(context.codingPath)")
                case .dataCorrupted(let context):
                    print("[DECODE] Data corrupted: \(context.debugDescription)")
                @unknown default:
                    break
                }
            }
            createdEntries = nil
        }

        print("[DECODE] ChatResponse decode complete")
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
    let calories: Double
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
        self.calories = try container.decode(Double.self, forKey: .calories)
        self.proteinG = try container.decode(Double.self, forKey: .proteinG)
        self.carbsG = try container.decode(Double.self, forKey: .carbsG)
        self.fatG = try container.decode(Double.self, forKey: .fatG)
        self.confidence = try container.decode(Double.self, forKey: .confidence)
    }

    init(
        name: String,
        portionDescription: String,
        gramsEstimate: Double,
        calories: Double,
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
            calories: Int(round(calories)),
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            confidence: confidence,
            portionDescription: portionDescription
        )
    }
}

struct MacroTotals: Decodable {
    let calories: Double
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

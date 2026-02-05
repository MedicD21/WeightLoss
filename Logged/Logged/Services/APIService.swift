import Foundation
import Combine

private enum DateParsers {
    static let iso8601WithFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    static let iso8601NoFraction: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}

/// API service for backend communication
@MainActor
final class APIService: ObservableObject {
    static let shared = APIService()

    private let baseURL = URL(string: Constants.API.baseURL)!
    private let session: URLSession
    private var cancellables = Set<AnyCancellable>()

    @Published var isLoading = false
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = Constants.API.timeout
        config.timeoutIntervalForResource = Constants.API.timeout
        session = URLSession(configuration: config)
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateString = try container.decode(String.self)
            if let date = DateParsers.iso8601WithFraction.date(from: dateString) {
                return date
            }
            if let date = DateParsers.iso8601NoFraction.date(from: dateString) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(dateString)"
            )
        }
        return decoder
    }

    private func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            let dateString = DateParsers.iso8601WithFraction.string(from: date)
            try container.encode(dateString)
        }
        return encoder
    }

    // MARK: - Generic Request

    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        queryItems: [URLQueryItem]? = nil,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth header if required
        if requiresAuth, let token = KeychainService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add body if present
        if let body = body {
            request.httpBody = try makeEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        // Handle auth errors
        if httpResponse.statusCode == 401 {
            // Try to refresh token
            if requiresAuth, let _ = KeychainService.shared.getRefreshToken() {
                try await refreshToken()
                // Retry the request
                return try await self.request(
                    endpoint: endpoint,
                    method: method,
                    queryItems: queryItems,
                    body: body,
                    requiresAuth: requiresAuth
                )
            }
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        // Debug: log raw JSON for chat responses
        if endpoint.contains("ai/chat") {
            if let jsonString = String(data: data, encoding: .utf8) {
                print("[iOS DEBUG] Raw JSON response: \(jsonString)")
            }
        }

        do {
            let decoded = try makeDecoder().decode(T.self, from: data)
            return decoded
        } catch {
            print("[iOS ERROR] Decoding failed: \(error)")
            if let decodingError = error as? DecodingError {
                switch decodingError {
                case .keyNotFound(let key, let context):
                    print("[iOS ERROR] Key '\(key.stringValue)' not found: \(context.debugDescription)")
                case .typeMismatch(let type, let context):
                    print("[iOS ERROR] Type mismatch for type \(type): \(context.debugDescription)")
                case .valueNotFound(let type, let context):
                    print("[iOS ERROR] Value not found for type \(type): \(context.debugDescription)")
                case .dataCorrupted(let context):
                    print("[iOS ERROR] Data corrupted: \(context.debugDescription)")
                @unknown default:
                    print("[iOS ERROR] Unknown decoding error")
                }
            }
            throw error
        }
    }

    func requestVoid(
        endpoint: String,
        method: HTTPMethod = .GET,
        queryItems: [URLQueryItem]? = nil,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws {
        var components = URLComponents(url: baseURL.appendingPathComponent(endpoint), resolvingAgainstBaseURL: false)
        components?.queryItems = queryItems
        guard let url = components?.url else {
            throw APIError.invalidResponse
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth, let token = KeychainService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = body {
            request.httpBody = try makeEncoder().encode(body)
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if httpResponse.statusCode == 401 {
            if requiresAuth, let _ = KeychainService.shared.getRefreshToken() {
                try await refreshToken()
                return try await self.requestVoid(
                    endpoint: endpoint,
                    method: method,
                    queryItems: queryItems,
                    body: body,
                    requiresAuth: requiresAuth
                )
            }
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }
    }

    // MARK: - Upload

    func uploadImage(
        endpoint: String,
        imageData: Data,
        filename: String = "image.jpg",
        additionalFields: [String: String] = [:]
    ) async throws -> VisionAnalyzeResponse {
        let boundary = UUID().uuidString
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        if let token = KeychainService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        var body = Data()

        // Add image
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"image\"; filename=\"\(filename)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: image/jpeg\r\n\r\n".data(using: .utf8)!)
        body.append(imageData)
        body.append("\r\n".data(using: .utf8)!)

        // Add additional fields
        for (key, value) in additionalFields {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n".data(using: .utf8)!)
            body.append("\(value)\r\n".data(using: .utf8)!)
        }

        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        request.httpBody = body

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            throw APIError.invalidResponse
        }

        return try makeDecoder().decode(VisionAnalyzeResponse.self, from: data)
    }

    // MARK: - Auth

    func requestMagicLink(email: String) async throws -> MagicLinkResponse {
        struct Request: Encodable {
            let email: String
        }

        return try await request(
            endpoint: "auth/magic-link",
            method: .POST,
            body: Request(email: email),
            requiresAuth: false
        )
    }

    func verifyMagicLink(token: String) async throws -> TokenResponse {
        struct Request: Encodable {
            let token: String
        }

        return try await request(
            endpoint: "auth/verify",
            method: .POST,
            body: Request(token: token),
            requiresAuth: false
        )
    }

    func refreshToken() async throws {
        guard let refreshToken = KeychainService.shared.getRefreshToken() else {
            throw APIError.unauthorized
        }

        struct Request: Encodable {
            let refreshToken: String
        }

        let response: TokenResponse = try await request(
            endpoint: "auth/refresh",
            method: .POST,
            body: Request(refreshToken: refreshToken),
            requiresAuth: false
        )

        KeychainService.shared.saveToken(response.accessToken)
        KeychainService.shared.saveRefreshToken(response.refreshToken)
    }

    func validateToken() async throws -> Bool {
        struct ValidationResponse: Decodable {
            let valid: Bool
            let userId: UUID?
        }

        do {
            let response: ValidationResponse = try await request(
                endpoint: "auth/validate",
                method: .GET,
                requiresAuth: true
            )
            return response.valid
        } catch APIError.unauthorized {
            // Token is invalid/expired
            return false
        } catch {
            // Network error, assume token might be valid (offline mode)
            return true
        }
    }

    // MARK: - Chat

    func sendChatMessage(message: String, conversationId: String? = nil) async throws -> ChatResponse {
        struct Request: Encodable {
            let message: String
            let conversationId: String?
            let includeContext: Bool
        }

        return try await request(
            endpoint: "ai/chat",
            method: .POST,
            body: Request(message: message, conversationId: conversationId, includeContext: true)
        )
    }

    func analyzeFood(imageBase64: String, prompt: String? = nil) async throws -> VisionAnalyzeResponse {
        struct Request: Encodable {
            let imageBase64: String
            let prompt: String?
        }

        return try await request(
            endpoint: "ai/vision/analyze",
            method: .POST,
            body: Request(imageBase64: imageBase64, prompt: prompt)
        )
    }

    // MARK: - Meals

    func createMeal(request mealRequest: MealCreateRequestDTO) async throws -> MealResponseDTO {
        try await request(endpoint: "nutrition/meals", method: .POST, body: mealRequest)
    }

    func updateMeal(id: UUID, request mealUpdate: MealUpdateRequestDTO) async throws -> MealResponseDTO {
        try await request(endpoint: "nutrition/meals/\(id.uuidString)", method: .PUT, body: mealUpdate)
    }

    func deleteMeal(id: UUID) async throws {
        try await requestVoid(endpoint: "nutrition/meals/\(id.uuidString)", method: .DELETE)
    }

    func listMealSummaries(startDate: Date, endDate: Date) async throws -> [MealSummaryDTO] {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        let start = formatter.string(from: startDate)
        let end = formatter.string(from: endDate)
        return try await request(
            endpoint: "nutrition/meals",
            method: .GET,
            queryItems: [
                URLQueryItem(name: "start_date", value: start),
                URLQueryItem(name: "end_date", value: end),
                URLQueryItem(name: "limit", value: "100")
            ]
        )
    }

    // MARK: - Sync Helpers

    func fetchMeal(id: UUID) async throws -> MealResponseDTO {
        try await request(endpoint: "nutrition/meals/\(id.uuidString)")
    }

    func updateFoodItem(mealId: UUID, itemId: UUID, request itemUpdate: FoodItemUpdateRequestDTO) async throws -> MealResponseDTO {
        try await request(
            endpoint: "nutrition/meals/\(mealId.uuidString)/items/\(itemId.uuidString)",
            method: .PUT,
            body: itemUpdate
        )
    }

    func deleteFoodItem(mealId: UUID, itemId: UUID) async throws -> MealResponseDTO {
        try await request(endpoint: "nutrition/meals/\(mealId.uuidString)/items/\(itemId.uuidString)", method: .DELETE)
    }

    func deleteWaterEntry(id: UUID) async throws {
        try await requestVoid(endpoint: "tracking/water/\(id.uuidString)", method: .DELETE)
    }

    func deleteWeightEntry(id: UUID) async throws {
        try await requestVoid(endpoint: "tracking/weight/\(id.uuidString)", method: .DELETE)
    }

    func deleteWorkoutLog(id: UUID) async throws {
        try await requestVoid(endpoint: "workouts/logs/\(id.uuidString)", method: .DELETE)
    }

    func fetchWorkoutLog(id: UUID) async throws -> WorkoutLogResponseDTO {
        try await request(endpoint: "workouts/logs/\(id.uuidString)")
    }

    func fetchWorkoutPlan(id: UUID) async throws -> WorkoutPlanResponseDTO {
        try await request(endpoint: "workouts/plans/\(id.uuidString)")
    }

    func fetchMacroTargets() async throws -> MacroTargetsResponseDTO? {
        try await request(endpoint: "user/targets")
    }
}

// MARK: - HTTP Methods

enum HTTPMethod: String {
    case GET
    case POST
    case PUT
    case PATCH
    case DELETE
}

// MARK: - Errors

enum APIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case httpError(statusCode: Int, data: Data)
    case decodingError(Error)
    case networkError(Error)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid response from server"
        case .unauthorized:
            return "Authentication required"
        case .httpError(let code, _):
            return "Server error: \(code)"
        case .decodingError(let error):
            return "Failed to decode response: \(error.localizedDescription)"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        }
    }
}

// MARK: - Response Types

struct MagicLinkResponse: Decodable {
    let message: String
    let debugLink: String?
}

struct TokenResponse: Decodable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let expiresIn: Int
    let userId: String
}

struct FoodItemResponseDTO: Decodable {
    let id: UUID
    let mealId: UUID
    let name: String
    let source: FoodSource
    let grams: Double
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double?
    let sodiumMg: Double?
    let sugarG: Double?
    let saturatedFatG: Double?
    let servingSize: Double?
    let servingUnit: String?
    let servings: Double
    let barcode: String?
    let nutriScoreGrade: String?
    let confidence: Double?
    let portionDescription: String?
    let createdAt: Date
}

struct MealResponseDTO: Decodable {
    let id: UUID
    let userId: UUID
    let name: String
    let mealType: MealType
    let timestamp: Date
    let notes: String?
    let totalCalories: Int
    let totalProteinG: Double
    let totalCarbsG: Double
    let totalFatG: Double
    let totalFiberG: Double?
    let items: [FoodItemResponseDTO]
    let createdAt: Date
    let updatedAt: Date
}

struct MealSummaryDTO: Decodable {
    let id: UUID
    let name: String
    let mealType: MealType
    let timestamp: Date
    let totalCalories: Int
    let totalProteinG: Double
    let itemsCount: Int
}

struct FoodItemCreateRequestDTO: Encodable {
    let name: String
    let grams: Double
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double?
    let source: FoodSource?
    let servingSize: Double?
    let servingUnit: String?
    let servings: Double?
    let barcode: String?
    let offProductId: String?
    let nutriScoreGrade: String?
    let confidence: Double?
    let portionDescription: String?
}

struct MealCreateRequestDTO: Encodable {
    let name: String
    let mealType: MealType
    let timestamp: Date
    let notes: String?
    let photoUrl: String?
    let items: [FoodItemCreateRequestDTO]
    let localId: String?
}

struct MealUpdateRequestDTO: Encodable {
    let name: String?
    let mealType: MealType?
    let timestamp: Date?
    let notes: String?
    let photoUrl: String?
}

struct FoodItemUpdateRequestDTO: Encodable {
    let name: String?
    let grams: Double?
    let calories: Int?
    let proteinG: Double?
    let carbsG: Double?
    let fatG: Double?
    let fiberG: Double?
    let sodiumMg: Double?
    let sugarG: Double?
    let saturatedFatG: Double?
    let servingSize: Double?
    let servingUnit: String?
    let servings: Double?
    let barcode: String?
    let offProductId: String?
    let nutriScoreGrade: String?
    let confidence: Double?
    let portionDescription: String?
}

struct WorkoutSetLogResponseDTO: Decodable {
    let id: UUID
    let logId: UUID
    let exerciseName: String
    let setNumber: Int
    let reps: Int?
    let weightKg: Double?
    let durationSec: Int?
    let distanceM: Double?
    let completed: Bool
    let isWarmup: Bool
    let isDropset: Bool
    let rpe: Int?
    let orderIndex: Int
    let notes: String?
    let createdAt: Date
}

struct WorkoutLogResponseDTO: Decodable {
    let id: UUID
    let userId: UUID
    let planId: UUID?
    let name: String
    let workoutType: WorkoutType
    let startTime: Date
    let endTime: Date?
    let durationMin: Int
    let caloriesBurned: Int?
    let avgHeartRate: Int?
    let maxHeartRate: Int?
    let distanceKm: Double?
    let notes: String?
    let rating: Int?
    let source: LogSource
    let healthKitId: String?
    let sets: [WorkoutSetLogResponseDTO]
    let createdAt: Date
    let updatedAt: Date
}

struct WorkoutExerciseResponseDTO: Decodable {
    let id: UUID
    let planId: UUID
    let name: String
    let muscleGroup: MuscleGroup?
    let equipment: String?
    let notes: String?
    let sets: Int
    let repsMin: Int?
    let repsMax: Int?
    let durationSec: Int?
    let restSec: Int
    let supersetGroup: Int?
    let orderIndex: Int
    let createdAt: Date
}

struct WorkoutPlanResponseDTO: Decodable {
    let id: UUID
    let userId: UUID
    let name: String
    let description: String?
    let workoutType: WorkoutType
    let scheduledDays: [Int]?
    let estimatedDurationMin: Int?
    let isActive: Bool
    let orderIndex: Int
    let exercises: [WorkoutExerciseResponseDTO]
    let createdAt: Date
    let updatedAt: Date
}

struct MacroTargetsResponseDTO: Decodable {
    let id: UUID
    let userId: UUID
    let calories: Int
    let proteinG: Double
    let carbsG: Double
    let fatG: Double
    let fiberG: Double?
    let bmr: Int?
    let tdee: Int?
    let calculatedAt: Date
}

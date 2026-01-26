import Foundation
import Combine

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

    // MARK: - Generic Request

    func request<T: Decodable>(
        endpoint: String,
        method: HTTPMethod = .GET,
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        var url = baseURL.appendingPathComponent(endpoint)
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // Add auth header if required
        if requiresAuth, let token = KeychainService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        // Add body if present
        if let body = body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            request.httpBody = try encoder.encode(body)
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
                return try await self.request(endpoint: endpoint, method: method, body: body, requiresAuth: requiresAuth)
            }
            throw APIError.unauthorized
        }

        guard (200...299).contains(httpResponse.statusCode) else {
            throw APIError.httpError(statusCode: httpResponse.statusCode, data: data)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        return try decoder.decode(T.self, from: data)
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

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(VisionAnalyzeResponse.self, from: data)
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

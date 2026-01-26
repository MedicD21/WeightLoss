import Foundation

enum WatchAPIError: Error {
    case invalidResponse
    case unauthorized
    case httpError(Int)
}

struct WatchAPIService {
    static let shared = WatchAPIService()

    private let baseURL = URL(string: WatchConstants.API.baseURL)!
    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = WatchConstants.API.timeout
        config.timeoutIntervalForResource = WatchConstants.API.timeout
        session = URLSession(configuration: config)
    }

    func request<T: Decodable>(
        endpoint: String,
        method: String = "GET",
        body: Encodable? = nil,
        requiresAuth: Bool = true
    ) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if requiresAuth, let token = WatchKeychainService.shared.getToken() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(AnyEncodable(body))
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw WatchAPIError.invalidResponse
        }
        if httpResponse.statusCode == 401 {
            throw WatchAPIError.unauthorized
        }
        guard (200...299).contains(httpResponse.statusCode) else {
            throw WatchAPIError.httpError(httpResponse.statusCode)
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(T.self, from: data)
    }
}

struct AnyEncodable: Encodable {
    private let encodeFunc: (Encoder) throws -> Void

    init(_ encodable: Encodable) {
        self.encodeFunc = encodable.encode
    }

    func encode(to encoder: Encoder) throws {
        try encodeFunc(encoder)
    }
}

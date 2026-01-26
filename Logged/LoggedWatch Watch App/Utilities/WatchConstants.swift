import Foundation

enum WatchConstants {
    enum API {
        static let baseURL: String = {
            if let override = Bundle.main.object(forInfoDictionaryKey: "API_BASE_URL") as? String,
               !override.isEmpty {
                return override
            }
            #if DEBUG
            return "http://localhost:8000"
            #else
            return "https://api.logged.app"
            #endif
        }()

        static let timeout: TimeInterval = 20
    }

    enum Keychain {
        static let serviceName = "com.logged.fitness.watch"
        static let accessTokenKey = "access_token"
        static let refreshTokenKey = "refresh_token"
    }

    enum Defaults {
        static let quickWaterOptions: [Int] = [250, 500, 750]
    }
}

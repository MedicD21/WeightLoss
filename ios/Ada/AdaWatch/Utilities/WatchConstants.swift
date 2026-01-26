import Foundation

enum WatchConstants {
    enum API {
        #if DEBUG
        static let baseURL = "http://localhost:8000"
        #else
        static let baseURL = "https://api.logged.app"
        #endif

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

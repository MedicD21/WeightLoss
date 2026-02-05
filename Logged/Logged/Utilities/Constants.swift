import Foundation

/// App-wide constants
enum Constants {
    // MARK: - API

    enum API {
        #if DEBUG
        #if targetEnvironment(simulator)
        // Simulator - use localhost since backend is on same Mac
        static let baseURL = "http://localhost:8000"
        #else
        // Physical device - use Tailscale
        static let baseURL = "http://schaaf-home-pc.tail5e22a1.ts.net:8000"
        #endif
        #else
        static let baseURL = "http://schaaf-home-pc.tail5e22a1.ts.net:8000"
        #endif

        static let timeout: TimeInterval = 30
    }

    // MARK: - Keychain

    enum Keychain {
        static let serviceName = "com.logged.fitness"
        static let accessTokenKey = "access_token"
        static let refreshTokenKey = "refresh_token"
    }

    // MARK: - UserDefaults Keys

    enum UserDefaultsKeys {
        static let hasCompletedOnboarding = "hasCompletedOnboarding"
        static let preferredUnits = "preferredUnits"
        static let lastSyncDate = "lastSyncDate"
        static let healthKitEnabled = "healthKitEnabled"
    }

    // MARK: - Defaults

    enum Defaults {
        static let dailyWaterGoalMl = UnitConverter.flOzToMl(80)
        static let dailyStepsGoal = 10000
        static let proteinPerKg = 1.8
        static let defaultGlassSize = UnitConverter.flOzToMl(8) // ml
        static let defaultBottleSize = UnitConverter.flOzToMl(16) // ml
    }

    // MARK: - Validation

    enum Validation {
        static let minWeight: Double = 20 // kg
        static let maxWeight: Double = 500 // kg
        static let minHeight: Double = 50 // cm
        static let maxHeight: Double = 300 // cm
        static let minAge = 10
        static let maxAge = 120
        static let maxGoalRate: Double = 1.5 // kg/week
    }

    // MARK: - Open Food Facts

    enum OpenFoodFacts {
        static let baseURL = "https://world.openfoodfacts.org/api/v2"
        static let userAgent = "Logged Fitness Tracker iOS/1.0"
    }

    // MARK: - Date Formats

    enum DateFormats {
        static let apiFormat = "yyyy-MM-dd'T'HH:mm:ssZ"
        static let displayDate = "MMM d, yyyy"
        static let displayTime = "h:mm a"
        static let displayDateTime = "MMM d, h:mm a"
        static let chartDate = "MMM d"
        static let weekday = "EEEE"
        static let shortWeekday = "EEE"
    }
}

// MARK: - Date Formatter Extensions

extension DateFormatter {
    static let api: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = Constants.DateFormats.apiFormat
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    static let displayDate: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = Constants.DateFormats.displayDate
        return formatter
    }()

    static let displayTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = Constants.DateFormats.displayTime
        return formatter
    }()

    static let displayDateTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = Constants.DateFormats.displayDateTime
        return formatter
    }()
}

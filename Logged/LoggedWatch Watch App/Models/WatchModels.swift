import Foundation

enum WatchWorkoutType: String, CaseIterable, Identifiable {
    case strength
    case cardio
    case hiit
    case flexibility
    case walking
    case running
    case cycling
    case swimming
    case sports
    case other

    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

struct WatchDailySummary: Decodable {
    let date: String
    let caloriesConsumed: Int
    let caloriesTarget: Int?
    let caloriesRemaining: Int?
    let proteinG: Double
    let waterMl: Int
    let steps: Int?
}

struct WatchWaterLogRequest: Encodable {
    let amountMl: Int
    let timestamp: String
}

struct WatchWeightLogRequest: Encodable {
    let weightKg: Double
    let timestamp: String
}

struct WatchWorkoutLogRequest: Encodable {
    let name: String
    let workoutType: String
    let startTime: String
    let durationMin: Int
}

struct WatchUserProfile: Decodable {
    let id: String
    let email: String
}

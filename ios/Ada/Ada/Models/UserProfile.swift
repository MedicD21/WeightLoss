import Foundation
import SwiftData

/// User's biological sex for BMR calculations
enum Sex: String, Codable, CaseIterable {
    case male
    case female

    var displayName: String {
        switch self {
        case .male: return "Male"
        case .female: return "Female"
        }
    }
}

/// Activity level for TDEE calculation
enum ActivityLevel: String, Codable, CaseIterable {
    case sedentary
    case light
    case moderate
    case active
    case veryActive = "very_active"

    var displayName: String {
        switch self {
        case .sedentary: return "Sedentary"
        case .light: return "Lightly Active"
        case .moderate: return "Moderately Active"
        case .active: return "Very Active"
        case .veryActive: return "Extra Active"
        }
    }

    var description: String {
        switch self {
        case .sedentary: return "Little or no exercise"
        case .light: return "Light exercise 1-3 days/week"
        case .moderate: return "Moderate exercise 3-5 days/week"
        case .active: return "Hard exercise 6-7 days/week"
        case .veryActive: return "Very hard exercise, physical job"
        }
    }

    var multiplier: Double {
        switch self {
        case .sedentary: return 1.2
        case .light: return 1.375
        case .moderate: return 1.55
        case .active: return 1.725
        case .veryActive: return 1.9
        }
    }
}

/// Fitness goal type
enum GoalType: String, Codable, CaseIterable {
    case cut
    case maintain
    case bulk

    var displayName: String {
        switch self {
        case .cut: return "Lose Weight"
        case .maintain: return "Maintain Weight"
        case .bulk: return "Build Muscle"
        }
    }

    var description: String {
        switch self {
        case .cut: return "Calorie deficit for fat loss"
        case .maintain: return "Maintain current weight"
        case .bulk: return "Calorie surplus for muscle gain"
        }
    }

    var icon: String {
        switch self {
        case .cut: return "arrow.down.circle.fill"
        case .maintain: return "equal.circle.fill"
        case .bulk: return "arrow.up.circle.fill"
        }
    }
}

/// User profile model stored locally
@Model
final class UserProfile {
    @Attribute(.unique) var id: UUID
    var email: String
    var displayName: String?

    // Body metrics
    var sex: Sex?
    var birthDate: Date?
    var heightCm: Double?
    var currentWeightKg: Double?

    // Goals
    var activityLevel: ActivityLevel
    var goalType: GoalType
    var goalRateKgPerWeek: Double
    var targetWeightKg: Double?

    // Preferences
    var useMetric: Bool
    var dailyWaterGoalMl: Int
    var proteinPerKg: Double

    // Sync
    var lastSyncedAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        email: String,
        displayName: String? = nil,
        sex: Sex? = nil,
        birthDate: Date? = nil,
        heightCm: Double? = nil,
        currentWeightKg: Double? = nil,
        activityLevel: ActivityLevel = .moderate,
        goalType: GoalType = .maintain,
        goalRateKgPerWeek: Double = 0.5,
        targetWeightKg: Double? = nil,
        useMetric: Bool = true,
        dailyWaterGoalMl: Int = 2500,
        proteinPerKg: Double = 1.8
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.sex = sex
        self.birthDate = birthDate
        self.heightCm = heightCm
        self.currentWeightKg = currentWeightKg
        self.activityLevel = activityLevel
        self.goalType = goalType
        self.goalRateKgPerWeek = goalRateKgPerWeek
        self.targetWeightKg = targetWeightKg
        self.useMetric = useMetric
        self.dailyWaterGoalMl = dailyWaterGoalMl
        self.proteinPerKg = proteinPerKg
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var age: Int? {
        guard let birthDate = birthDate else { return nil }
        let calendar = Calendar.current
        let ageComponents = calendar.dateComponents([.year], from: birthDate, to: Date())
        return ageComponents.year
    }

    var isProfileComplete: Bool {
        return sex != nil && birthDate != nil && heightCm != nil && currentWeightKg != nil
    }

    var missingFields: [String] {
        var missing: [String] = []
        if sex == nil { missing.append("Sex") }
        if birthDate == nil { missing.append("Birth Date") }
        if heightCm == nil { missing.append("Height") }
        if currentWeightKg == nil { missing.append("Weight") }
        return missing
    }

    // Display helpers
    var heightDisplay: String {
        guard let height = heightCm else { return "—" }
        if useMetric {
            return String(format: "%.0f cm", height)
        } else {
            let inches = height / 2.54
            let feet = Int(inches / 12)
            let remainingInches = Int(inches.truncatingRemainder(dividingBy: 12))
            return "\(feet)'\(remainingInches)\""
        }
    }

    var weightDisplay: String {
        guard let weight = currentWeightKg else { return "—" }
        if useMetric {
            return String(format: "%.1f kg", weight)
        } else {
            return String(format: "%.1f lbs", weight * 2.20462)
        }
    }
}

/// Calculated macro nutrient targets
@Model
final class MacroTargets {
    @Attribute(.unique) var id: UUID
    var userId: UUID

    // Targets
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?

    // Calculation metadata
    var bmr: Int?
    var tdee: Int?
    var calculatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double? = nil,
        bmr: Int? = nil,
        tdee: Int? = nil
    ) {
        self.id = id
        self.userId = userId
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.bmr = bmr
        self.tdee = tdee
        self.calculatedAt = Date()
    }
}

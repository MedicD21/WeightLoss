import Foundation
import SwiftData

/// Body weight log entry
@Model
final class BodyWeightEntry {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var localId: String?

    // Weight
    var weightKg: Double
    var timestamp: Date

    // Optional details
    var notes: String?
    var bodyFatPercent: Double?
    var muscleMassKg: Double?
    var waterPercent: Double?

    // Source
    var source: String

    // Sync
    var isSynced: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        weightKg: Double,
        timestamp: Date = Date(),
        notes: String? = nil,
        bodyFatPercent: Double? = nil,
        source: String = "manual"
    ) {
        self.id = id
        self.userId = userId
        self.localId = UUID().uuidString
        self.weightKg = weightKg
        self.timestamp = timestamp
        self.notes = notes
        self.bodyFatPercent = bodyFatPercent
        self.source = source
        self.isSynced = false
        self.createdAt = Date()
    }

    func weightDisplay(useMetric: Bool) -> String {
        if useMetric {
            return String(format: "%.1f kg", weightKg)
        } else {
            return String(format: "%.1f lbs", weightKg * 2.20462)
        }
    }
}

/// Water intake log entry
@Model
final class WaterEntry {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var localId: String?

    // Water amount
    var amountMl: Int
    var timestamp: Date

    // Source
    var source: String

    // Sync
    var isSynced: Bool
    var createdAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        amountMl: Int,
        timestamp: Date = Date(),
        source: String = "manual"
    ) {
        self.id = id
        self.userId = userId
        self.localId = UUID().uuidString
        self.amountMl = amountMl
        self.timestamp = timestamp
        self.source = source
        self.isSynced = false
        self.createdAt = Date()
    }

    var amountDisplay: String {
        if amountMl >= 1000 {
            return String(format: "%.1f L", Double(amountMl) / 1000)
        }
        return "\(amountMl) ml"
    }
}

/// Daily step count (from HealthKit)
@Model
final class StepsDaily {
    @Attribute(.unique) var id: UUID
    var userId: UUID

    // Date and steps
    var date: Date
    var steps: Int

    // Additional metrics
    var distanceKm: Double?
    var flightsClimbed: Int?
    var activeEnergyKcal: Int?

    // Source
    var source: String
    var syncedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        date: Date,
        steps: Int,
        distanceKm: Double? = nil,
        flightsClimbed: Int? = nil,
        activeEnergyKcal: Int? = nil,
        source: String = "health_kit"
    ) {
        self.id = id
        self.userId = userId
        self.date = date
        self.steps = steps
        self.distanceKm = distanceKm
        self.flightsClimbed = flightsClimbed
        self.activeEnergyKcal = activeEnergyKcal
        self.source = source
        self.syncedAt = Date()
    }

    var stepsDisplay: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: steps)) ?? "\(steps)"
    }
}

/// Daily summary for dashboard
struct DailySummary {
    let date: Date

    // Nutrition
    var caloriesConsumed: Int = 0
    var caloriesTarget: Int?
    var proteinG: Double = 0
    var proteinTarget: Double?
    var carbsG: Double = 0
    var fatG: Double = 0
    var mealsCount: Int = 0

    // Activity
    var steps: Int?
    var stepsGoal: Int = 10000
    var activeCalories: Int?
    var workoutsCount: Int = 0
    var workoutMinutes: Int = 0

    // Water
    var waterMl: Int = 0
    var waterGoalMl: Int = 2500

    // Weight
    var weightKg: Double?

    var caloriesRemaining: Int? {
        guard let target = caloriesTarget else { return nil }
        return target - caloriesConsumed
    }

    var proteinRemaining: Double? {
        guard let target = proteinTarget else { return nil }
        return target - proteinG
    }

    var caloriesProgress: Double {
        guard let target = caloriesTarget, target > 0 else { return 0 }
        return min(Double(caloriesConsumed) / Double(target), 1.0)
    }

    var proteinProgress: Double {
        guard let target = proteinTarget, target > 0 else { return 0 }
        return min(proteinG / target, 1.0)
    }

    var waterProgress: Double {
        guard waterGoalMl > 0 else { return 0 }
        return min(Double(waterMl) / Double(waterGoalMl), 1.0)
    }

    var stepsProgress: Double {
        guard let steps = steps, stepsGoal > 0 else { return 0 }
        return min(Double(steps) / Double(stepsGoal), 1.0)
    }
}

/// Progress summary for a period
struct ProgressSummary {
    let periodStart: Date
    let periodEnd: Date
    let periodDays: Int

    // Weight
    var weightCurrent: Double?
    var weightStart: Double?
    var weightChange: Double?
    var weightGoal: Double?
    var weightToGoal: Double?

    // Nutrition averages
    var avgDailyCalories: Int?
    var avgDailyProteinG: Double?
    var caloriesTarget: Int?
    var proteinTarget: Double?
    var calorieAdherencePercent: Double?
    var proteinAdherencePercent: Double?
    var daysOnTarget: Int = 0

    // Activity
    var totalWorkouts: Int = 0
    var totalWorkoutMinutes: Int = 0
    var avgDailySteps: Int?
    var totalCaloriesBurned: Int?

    // Water
    var avgDailyWaterMl: Int?
    var waterGoalMl: Int?
    var waterGoalDaysHit: Int = 0

    var weightTrend: String {
        guard let change = weightChange else { return "—" }
        if abs(change) < 0.5 {
            return "Maintaining"
        } else if change < 0 {
            return "Losing"
        } else {
            return "Gaining"
        }
    }
}

/// Chart data point
struct ChartDataPoint: Identifiable {
    let id = UUID()
    let date: Date
    let value: Double
    var label: String?
}

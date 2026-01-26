import Foundation
import SwiftData

/// Type of workout
enum WorkoutType: String, Codable, CaseIterable {
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

    var displayName: String {
        switch self {
        case .hiit: return "HIIT"
        default: return rawValue.capitalized
        }
    }

    var icon: String {
        switch self {
        case .strength: return "dumbbell.fill"
        case .cardio: return "heart.fill"
        case .hiit: return "bolt.fill"
        case .flexibility: return "figure.yoga"
        case .walking: return "figure.walk"
        case .running: return "figure.run"
        case .cycling: return "bicycle"
        case .swimming: return "figure.pool.swim"
        case .sports: return "sportscourt.fill"
        case .other: return "figure.mixed.cardio"
        }
    }
}

/// Source of workout log
enum LogSource: String, Codable {
    case manual
    case healthKit = "health_kit"
    case chat
}

/// Muscle group for exercises
enum MuscleGroup: String, Codable, CaseIterable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case forearms
    case core
    case quads
    case hamstrings
    case glutes
    case calves
    case fullBody = "full_body"
    case cardio

    var displayName: String {
        switch self {
        case .fullBody: return "Full Body"
        default: return rawValue.capitalized
        }
    }
}

/// Workout plan template
@Model
final class WorkoutPlan {
    @Attribute(.unique) var id: UUID
    var userId: UUID

    // Plan info
    var name: String
    var planDescription: String?
    var workoutType: WorkoutType

    // Schedule (0=Monday, 6=Sunday)
    var scheduledDays: [Int]?
    var estimatedDurationMin: Int?

    // Status
    var isActive: Bool
    var orderIndex: Int

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \WorkoutExercise.plan)
    var exercises: [WorkoutExercise]

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        planDescription: String? = nil,
        workoutType: WorkoutType,
        scheduledDays: [Int]? = nil,
        estimatedDurationMin: Int? = nil,
        isActive: Bool = true
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.planDescription = planDescription
        self.workoutType = workoutType
        self.scheduledDays = scheduledDays
        self.estimatedDurationMin = estimatedDurationMin
        self.isActive = isActive
        self.orderIndex = 0
        self.exercises = []
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var scheduledDaysDisplay: String {
        guard let days = scheduledDays, !days.isEmpty else { return "Not scheduled" }
        let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]
        return days.sorted().map { dayNames[$0] }.joined(separator: ", ")
    }
}

/// Exercise within a workout plan
@Model
final class WorkoutExercise {
    @Attribute(.unique) var id: UUID
    var plan: WorkoutPlan?

    // Exercise info
    var name: String
    var muscleGroup: MuscleGroup?
    var equipment: String?
    var notes: String?

    // Sets and reps (target)
    var sets: Int
    var repsMin: Int?
    var repsMax: Int?
    var durationSec: Int?

    // Rest
    var restSec: Int

    // Order in workout
    var orderIndex: Int

    // Superset grouping
    var supersetGroup: Int?

    init(
        id: UUID = UUID(),
        name: String,
        muscleGroup: MuscleGroup? = nil,
        equipment: String? = nil,
        sets: Int = 3,
        repsMin: Int? = 8,
        repsMax: Int? = 12,
        durationSec: Int? = nil,
        restSec: Int = 60,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.name = name
        self.muscleGroup = muscleGroup
        self.equipment = equipment
        self.sets = sets
        self.repsMin = repsMin
        self.repsMax = repsMax
        self.durationSec = durationSec
        self.restSec = restSec
        self.orderIndex = orderIndex
    }

    var repsDisplay: String {
        if let duration = durationSec {
            return "\(duration)s"
        }
        guard let min = repsMin else { return "—" }
        if let max = repsMax, max != min {
            return "\(min)-\(max)"
        }
        return "\(min)"
    }
}

/// Logged workout session
@Model
final class WorkoutLog {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var planId: UUID?
    var localId: String?

    // Workout info
    var name: String
    var workoutType: WorkoutType
    var source: LogSource

    // Timing
    var startTime: Date
    var endTime: Date?
    var durationMin: Int

    // Metrics
    var caloriesBurned: Int?
    var avgHeartRate: Int?
    var maxHeartRate: Int?
    var distanceKm: Double?

    // Notes
    var notes: String?
    var rating: Int?

    // HealthKit sync
    var healthKitId: String?
    var isSynced: Bool

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \WorkoutSetLog.log)
    var sets: [WorkoutSetLog]

    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        planId: UUID? = nil,
        name: String,
        workoutType: WorkoutType,
        source: LogSource = .manual,
        startTime: Date = Date(),
        durationMin: Int,
        caloriesBurned: Int? = nil
    ) {
        self.id = id
        self.userId = userId
        self.planId = planId
        self.localId = UUID().uuidString
        self.name = name
        self.workoutType = workoutType
        self.source = source
        self.startTime = startTime
        self.durationMin = durationMin
        self.caloriesBurned = caloriesBurned
        self.sets = []
        self.isSynced = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    var durationDisplay: String {
        if durationMin >= 60 {
            let hours = durationMin / 60
            let mins = durationMin % 60
            return mins > 0 ? "\(hours)h \(mins)m" : "\(hours)h"
        }
        return "\(durationMin)m"
    }
}

/// Individual set log within a workout
@Model
final class WorkoutSetLog {
    @Attribute(.unique) var id: UUID
    var log: WorkoutLog?

    // Exercise info
    var exerciseName: String
    var setNumber: Int

    // Performance
    var reps: Int?
    var weightKg: Double?
    var durationSec: Int?
    var distanceM: Double?

    // Status
    var completed: Bool
    var isWarmup: Bool
    var isDropset: Bool

    // RPE (Rate of Perceived Exertion, 1-10)
    var rpe: Int?

    // Order
    var orderIndex: Int

    // Notes
    var notes: String?

    init(
        id: UUID = UUID(),
        exerciseName: String,
        setNumber: Int,
        reps: Int? = nil,
        weightKg: Double? = nil,
        durationSec: Int? = nil,
        completed: Bool = true,
        isWarmup: Bool = false,
        isDropset: Bool = false,
        orderIndex: Int = 0
    ) {
        self.id = id
        self.exerciseName = exerciseName
        self.setNumber = setNumber
        self.reps = reps
        self.weightKg = weightKg
        self.durationSec = durationSec
        self.completed = completed
        self.isWarmup = isWarmup
        self.isDropset = isDropset
        self.orderIndex = orderIndex
    }

    var weightDisplay: String {
        guard let weight = weightKg else { return "—" }
        return String(format: "%.1f kg", weight)
    }
}

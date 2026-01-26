import Foundation
import HealthKit
import Combine

/// Service for HealthKit integration
@MainActor
final class HealthKitService: ObservableObject {
    static let shared = HealthKitService()

    private let healthStore = HKHealthStore()

    @Published var isAuthorized = false
    @Published var todaySteps: Int?
    @Published var todayActiveCalories: Int?
    @Published var todayWorkouts: [HKWorkout] = []

    // Types to read
    private let typesToRead: Set<HKObjectType> = [
        HKObjectType.quantityType(forIdentifier: .stepCount)!,
        HKObjectType.quantityType(forIdentifier: .activeEnergyBurned)!,
        HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning)!,
        HKObjectType.quantityType(forIdentifier: .flightsClimbed)!,
        HKObjectType.workoutType(),
    ]

    // Types to write
    private let typesToWrite: Set<HKSampleType> = [
        HKObjectType.workoutType(),
    ]

    private init() {}

    // MARK: - Authorization

    var isHealthKitAvailable: Bool {
        HKHealthStore.isHealthDataAvailable()
    }

    func requestAuthorization() async throws {
        guard isHealthKitAvailable else {
            throw HealthKitError.notAvailable
        }

        try await healthStore.requestAuthorization(toShare: typesToWrite, read: typesToRead)
        isAuthorized = true
    }

    func checkAuthorizationStatus() -> HKAuthorizationStatus {
        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            return .notDetermined
        }
        return healthStore.authorizationStatus(for: stepType)
    }

    // MARK: - Steps

    func fetchTodaySteps() async throws -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.invalidType
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let steps = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sum = result?.sumQuantity() else {
                    continuation.resume(returning: 0)
                    return
                }

                let steps = Int(sum.doubleValue(for: HKUnit.count()))
                continuation.resume(returning: steps)
            }

            healthStore.execute(query)
        }

        todaySteps = steps
        return steps
    }

    func fetchStepsForRange(startDate: Date, endDate: Date) async throws -> [Date: Int] {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            throw HealthKitError.invalidType
        }

        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[Date: Int], Error>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: Calendar.current.startOfDay(for: startDate),
                intervalComponents: DateComponents(day: 1)
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                var stepsByDate: [Date: Int] = [:]

                results?.enumerateStatistics(from: startDate, to: endDate) { statistics, _ in
                    if let sum = statistics.sumQuantity() {
                        let steps = Int(sum.doubleValue(for: HKUnit.count()))
                        let date = Calendar.current.startOfDay(for: statistics.startDate)
                        stepsByDate[date] = steps
                    }
                }

                continuation.resume(returning: stepsByDate)
            }

            healthStore.execute(query)
        }
    }

    // MARK: - Active Calories

    func fetchTodayActiveCalories() async throws -> Int {
        guard let calorieType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) else {
            throw HealthKitError.invalidType
        }

        let startOfDay = Calendar.current.startOfDay(for: Date())
        let predicate = HKQuery.predicateForSamples(withStart: startOfDay, end: Date(), options: .strictStartDate)

        let calories = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, Error>) in
            let query = HKStatisticsQuery(
                quantityType: calorieType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let sum = result?.sumQuantity() else {
                    continuation.resume(returning: 0)
                    return
                }

                let calories = Int(sum.doubleValue(for: HKUnit.kilocalorie()))
                continuation.resume(returning: calories)
            }

            healthStore.execute(query)
        }

        todayActiveCalories = calories
        return calories
    }

    // MARK: - Workouts

    func fetchWorkouts(startDate: Date, endDate: Date) async throws -> [HKWorkout] {
        let predicate = HKQuery.predicateForSamples(withStart: startDate, end: endDate, options: .strictStartDate)
        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: false)

        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[HKWorkout], Error>) in
            let query = HKSampleQuery(
                sampleType: HKObjectType.workoutType(),
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [sortDescriptor]
            ) { _, samples, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                let workouts = samples as? [HKWorkout] ?? []
                continuation.resume(returning: workouts)
            }

            healthStore.execute(query)
        }
    }

    func fetchTodayWorkouts() async throws -> [HKWorkout] {
        let startOfDay = Calendar.current.startOfDay(for: Date())
        let workouts = try await fetchWorkouts(startDate: startOfDay, endDate: Date())
        todayWorkouts = workouts
        return workouts
    }

    // MARK: - Write Workout

    func saveWorkout(
        type: HKWorkoutActivityType,
        startDate: Date,
        endDate: Date,
        calories: Double?,
        distance: Double?
    ) async throws {
        var metadata: [String: Any] = [:]

        let workout = HKWorkout(
            activityType: type,
            start: startDate,
            end: endDate,
            workoutEvents: nil,
            totalEnergyBurned: calories.map { HKQuantity(unit: .kilocalorie(), doubleValue: $0) },
            totalDistance: distance.map { HKQuantity(unit: .meter(), doubleValue: $0 * 1000) },
            metadata: metadata
        )

        try await healthStore.save(workout)
    }

    // MARK: - Helpers

    func mapWorkoutType(_ type: HKWorkoutActivityType) -> WorkoutType {
        switch type {
        case .traditionalStrengthTraining, .functionalStrengthTraining:
            return .strength
        case .running:
            return .running
        case .walking:
            return .walking
        case .cycling:
            return .cycling
        case .swimming:
            return .swimming
        case .highIntensityIntervalTraining:
            return .hiit
        case .yoga, .pilates, .flexibility:
            return .flexibility
        default:
            return .other
        }
    }
}

// MARK: - Errors

enum HealthKitError: LocalizedError {
    case notAvailable
    case notAuthorized
    case invalidType

    var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "HealthKit is not available on this device"
        case .notAuthorized:
            return "HealthKit access is not authorized"
        case .invalidType:
            return "Invalid HealthKit type"
        }
    }
}

// MARK: - HKWorkout Extension

extension HKWorkout {
    var caloriesBurned: Int? {
        guard let quantity = totalEnergyBurned else { return nil }
        return Int(quantity.doubleValue(for: .kilocalorie()))
    }

    var distanceKm: Double? {
        guard let quantity = totalDistance else { return nil }
        return quantity.doubleValue(for: .meter()) / 1000
    }

    var durationMinutes: Int {
        Int(duration / 60)
    }
}

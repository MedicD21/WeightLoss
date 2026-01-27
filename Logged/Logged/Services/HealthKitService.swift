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
    private let typesToWrite: Set<HKSampleType> = {
        var types: Set<HKSampleType> = [HKObjectType.workoutType()]
        let quantityTypes: [HKQuantityTypeIdentifier] = [
            .activeEnergyBurned,
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ]
        for identifier in quantityTypes {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }()

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
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = type
        configuration.locationType = .unknown

        let builder = HKWorkoutBuilder(
            healthStore: healthStore,
            configuration: configuration,
            device: nil
        )

        try await builder.beginCollection(at: startDate)

        var samples: [HKSample] = []

        if let calories,
           let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            let quantity = HKQuantity(unit: .kilocalorie(), doubleValue: calories)
            let sample = HKQuantitySample(type: energyType, quantity: quantity, start: startDate, end: endDate)
            samples.append(sample)
        }

        if let distance,
           let distanceType = distanceQuantityType(for: type) {
            let quantity = HKQuantity(unit: .meter(), doubleValue: distance * 1000)
            let sample = HKQuantitySample(type: distanceType, quantity: quantity, start: startDate, end: endDate)
            samples.append(sample)
        }

        if !samples.isEmpty {
            try await builder.addSamples(samples)
        }

        try await builder.endCollection(at: endDate)
        _ = try await builder.finishWorkout()
    }

    // MARK: - Helpers

    private func distanceQuantityType(for activityType: HKWorkoutActivityType) -> HKQuantityType? {
        let identifier: HKQuantityTypeIdentifier?
        switch activityType {
        case .running, .walking:
            identifier = .distanceWalkingRunning
        case .cycling:
            identifier = .distanceCycling
        case .swimming:
            identifier = .distanceSwimming
        default:
            identifier = nil
        }

        guard let identifier else {
            return nil
        }
        return HKQuantityType.quantityType(forIdentifier: identifier)
    }

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
        guard let energyType = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned),
              let quantity = statistics(for: energyType)?.sumQuantity() else {
            return nil
        }
        return Int(quantity.doubleValue(for: .kilocalorie()))
    }

    var distanceKm: Double? {
        let distanceTypeIdentifiers: [HKQuantityTypeIdentifier] = [
            .distanceWalkingRunning,
            .distanceCycling,
            .distanceSwimming,
        ]

        for identifier in distanceTypeIdentifiers {
            guard let quantityType = HKQuantityType.quantityType(forIdentifier: identifier) else {
                continue
            }
            if let quantity = statistics(for: quantityType)?.sumQuantity() {
                return quantity.doubleValue(for: .meter()) / 1000
            }
        }

        return nil
    }

    var durationMinutes: Int {
        Int(duration / 60)
    }
}

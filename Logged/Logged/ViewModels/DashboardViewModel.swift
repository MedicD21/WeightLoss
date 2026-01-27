import Foundation
import SwiftData
import Combine

/// View model for the dashboard
@MainActor
final class DashboardViewModel: ObservableObject {
    @Published var summary = DailySummary(date: Date())
    @Published var isLoading = false
    @Published var error: Error?

    private let healthKitService = HealthKitService.shared

    func refresh(modelContext: ModelContext) async {
        isLoading = true
        defer { isLoading = false }

        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        // Build summary
        var newSummary = DailySummary(date: today)

        // Fetch meals for today
        let mealsPredicate = #Predicate<Meal> { meal in
            meal.timestamp >= today && meal.timestamp < tomorrow
        }
        let mealsDescriptor = FetchDescriptor<Meal>(predicate: mealsPredicate)

        do {
            let meals = try modelContext.fetch(mealsDescriptor)
            newSummary.mealsCount = meals.count
            newSummary.caloriesConsumed = meals.reduce(0) { $0 + $1.totalCalories }
            newSummary.proteinG = meals.reduce(0) { $0 + $1.totalProteinG }
            newSummary.carbsG = meals.reduce(0) { $0 + $1.totalCarbsG }
            newSummary.fatG = meals.reduce(0) { $0 + $1.totalFatG }
        } catch {
            print("Error fetching meals: \(error)")
        }

        // Fetch water entries for today
        let waterPredicate = #Predicate<WaterEntry> { entry in
            entry.timestamp >= today && entry.timestamp < tomorrow
        }
        let waterDescriptor = FetchDescriptor<WaterEntry>(predicate: waterPredicate)

        do {
            let waterEntries = try modelContext.fetch(waterDescriptor)
            newSummary.waterMl = waterEntries.reduce(0) { $0 + $1.amountMl }
        } catch {
            print("Error fetching water: \(error)")
        }

        // Fetch workouts for today
        let workoutPredicate = #Predicate<WorkoutLog> { log in
            log.startTime >= today && log.startTime < tomorrow
        }
        let workoutDescriptor = FetchDescriptor<WorkoutLog>(predicate: workoutPredicate)

        do {
            let workouts = try modelContext.fetch(workoutDescriptor)
            newSummary.workoutsCount = workouts.count
            newSummary.workoutMinutes = workouts.reduce(0) { $0 + $1.durationMin }
            newSummary.activeCalories = workouts.compactMap { $0.caloriesBurned }.reduce(0, +)
        } catch {
            print("Error fetching workouts: \(error)")
        }

        // Fetch weight for today
        let weightPredicate = #Predicate<BodyWeightEntry> { entry in
            entry.timestamp >= today && entry.timestamp < tomorrow
        }
        let weightDescriptor = FetchDescriptor<BodyWeightEntry>(
            predicate: weightPredicate,
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )

        do {
            let weightEntries = try modelContext.fetch(weightDescriptor)
            newSummary.weightKg = weightEntries.first?.weightKg
        } catch {
            print("Error fetching weight: \(error)")
        }

        // Fetch targets
        let targetsDescriptor = FetchDescriptor<MacroTargets>()
        do {
            let targets = try modelContext.fetch(targetsDescriptor)
            if let target = targets.first {
                newSummary.caloriesTarget = target.calories
                newSummary.proteinTarget = target.proteinG
            }
        } catch {
            print("Error fetching targets: \(error)")
        }

        // Fetch user profile for water goal
        let profileDescriptor = FetchDescriptor<UserProfile>()
        do {
            let profiles = try modelContext.fetch(profileDescriptor)
            if let profile = profiles.first {
                newSummary.waterGoalMl = profile.dailyWaterGoalMl
            }
        } catch {
            print("Error fetching profile: \(error)")
        }

        // Fetch steps from HealthKit
        if healthKitService.isHealthKitAvailable {
            do {
                try await healthKitService.requestAuthorization()
                newSummary.steps = try await healthKitService.fetchTodaySteps()
            } catch {
                print("Error fetching HealthKit data: \(error)")
            }
        }

        summary = newSummary
    }
}

import Foundation
import SwiftData
import Combine

/// View model for chat interface
@MainActor
final class ChatViewModel: ObservableObject {
    @Published var isLoading = false
    @Published var error: Error?
    @Published var conversationId: String?
    @Published var suggestions: [String] = []

    private let apiService = APIService.shared

    init() {
        // Set initial suggestions
        updateSuggestions(for: nil)
    }

    func sendMessage(_ text: String, modelContext: ModelContext) async {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        error = nil
        isLoading = true
        defer { isLoading = false }

        // Get user profile
        let descriptor = FetchDescriptor<UserProfile>()
        guard let profile = try? modelContext.fetch(descriptor).first else {
            error = ChatError.noUserProfile
            return
        }

        // Save user message locally
        let userMessage = ChatMessage(
            userId: profile.id,
            role: .user,
            content: text,
            conversationId: conversationId
        )
        modelContext.insert(userMessage)

        do {
            // Send to API
            let response = try await apiService.sendChatMessage(
                message: text,
                conversationId: conversationId
            )

            // Update conversation ID
            conversationId = response.conversationId

            // Save assistant response
            let assistantMessage = ChatMessage(
                userId: profile.id,
                role: .assistant,
                content: response.message,
                conversationId: conversationId
            )

            // Store tool calls if any
            if let toolCalls = response.toolCalls {
                let encoder = JSONEncoder()
                if let data = try? encoder.encode(toolCalls),
                   let json = String(data: data, encoding: .utf8) {
                    assistantMessage.toolCallsJSON = json
                }
            }

            assistantMessage.modelUsed = response.modelUsed
            assistantMessage.tokensUsed = response.tokensUsed
            modelContext.insert(assistantMessage)

            // Handle created entries (meals, workouts, water, etc.)
            if let createdEntries = response.createdEntries {
                await processCreatedEntries(createdEntries, profile: profile, modelContext: modelContext)
                // Update suggestions based on what was created
                updateSuggestions(for: createdEntries)
            }
            if let toolCalls = response.toolCalls {
                await processToolCalls(toolCalls, profile: profile, modelContext: modelContext)
            }

            try? modelContext.save()

        } catch {
            self.error = error

            // Save error message
            let errorMessage = ChatMessage(
                userId: profile.id,
                role: .assistant,
                content: "Sorry, I couldn't process that request. Please try again.",
                conversationId: conversationId
            )
            modelContext.insert(errorMessage)
            try? modelContext.save()
        }
    }

    func analyzeImage(_ imageData: Data, modelContext: ModelContext) async -> VisionAnalyzeResponse? {
        isLoading = true
        defer { isLoading = false }

        let base64 = imageData.base64EncodedString()

        do {
            return try await apiService.analyzeFood(imageBase64: base64)
        } catch {
            self.error = error
            return nil
        }
    }

    private func processCreatedEntries(
        _ entries: [[String: AnyCodable]],
        profile: UserProfile,
        modelContext: ModelContext
    ) async {
        for entry in entries {
            guard let type = entry["type"]?.value as? String,
                  let data = entry["data"]?.value as? [String: Any] else {
                continue
            }

            switch type {
            case "add_meal":
                if let mealId = Self.uuidValue(from: data["meal_id"]) {
                    if fetchMeal(id: mealId, modelContext: modelContext) == nil {
                        do {
                            let mealResponse = try await apiService.fetchMeal(id: mealId)
                            upsertMeal(from: mealResponse, profile: profile, modelContext: modelContext)
                        } catch {
                            if let name = Self.stringValue(from: data["name"]) {
                                let meal = Meal(
                                    id: mealId,
                                    userId: profile.id,
                                    name: name,
                                    mealType: .other,
                                    timestamp: Date()
                                )
                                meal.totalCalories = Self.intValue(from: data["total_calories"]) ?? 0
                                meal.totalProteinG = Self.doubleValue(from: data["total_protein_g"]) ?? 0
                                meal.totalCarbsG = Self.doubleValue(from: data["total_carbs_g"]) ?? 0
                                meal.totalFatG = Self.doubleValue(from: data["total_fat_g"]) ?? 0
                                meal.isSynced = true
                                modelContext.insert(meal)
                            }
                        }
                    }
                }

            case "add_water":
                if let amount = Self.intValue(from: data["amount_ml"]) {
                    let entry = WaterEntry(
                        userId: profile.id,
                        amountMl: amount,
                        source: "chat"
                    )
                    modelContext.insert(entry)
                }

            case "add_weight":
                if let weight = Self.doubleValue(from: data["weight_kg"]) {
                    let entry = BodyWeightEntry(
                        userId: profile.id,
                        weightKg: weight,
                        source: "chat"
                    )
                    modelContext.insert(entry)
                    profile.currentWeightKg = weight
                }

            case "add_workout":
                if let workoutId = Self.uuidValue(from: data["workout_id"]) {
                    if fetchWorkoutLog(id: workoutId, modelContext: modelContext) == nil {
                        do {
                            let logResponse = try await apiService.fetchWorkoutLog(id: workoutId)
                            upsertWorkoutLog(from: logResponse, profile: profile, modelContext: modelContext)
                        } catch {
                            if let name = Self.stringValue(from: data["name"]),
                               let duration = Self.intValue(from: data["duration_min"]) {
                                let log = WorkoutLog(
                                    id: workoutId,
                                    userId: profile.id,
                                    name: name,
                                    workoutType: .other,
                                    source: .chat,
                                    startTime: Date(),
                                    durationMin: duration
                                )
                                log.isSynced = true
                                modelContext.insert(log)
                            }
                        }
                    }
                }

            case "add_workout_plan":
                if let planId = Self.uuidValue(from: data["plan_id"]) {
                    if fetchWorkoutPlan(id: planId, modelContext: modelContext) == nil {
                        do {
                            let planResponse = try await apiService.fetchWorkoutPlan(id: planId)
                            upsertWorkoutPlan(from: planResponse, profile: profile, modelContext: modelContext)
                        } catch {
                            if let name = Self.stringValue(from: data["name"]) {
                                let plan = WorkoutPlan(
                                    id: planId,
                                    userId: profile.id,
                                    name: name,
                                    planDescription: Self.stringValue(from: data["description"]),
                                    workoutType: .other,
                                    scheduledDays: Self.intArrayValue(from: data["scheduled_days"]),
                                    estimatedDurationMin: Self.intValue(from: data["estimated_duration_min"])
                                )
                                plan.isActive = Self.boolValue(from: data["is_active"]) ?? true
                                modelContext.insert(plan)
                            }
                        }
                    }
                }

            case "set_goal":
                applySetGoalData(data, profile: profile)
                await refreshMacroTargets(profile: profile, modelContext: modelContext)

            case "set_custom_macros":
                if let targets = macroTargetsFromData(data, profile: profile) {
                    upsertMacroTargets(from: targets, profile: profile, modelContext: modelContext)
                }

            default:
                break
            }
        }
    }

    private func processToolCalls(
        _ toolCalls: [ToolCall],
        profile: UserProfile,
        modelContext: ModelContext
    ) async {
        var shouldRefreshTargets = false

        for toolCall in toolCalls {
            switch toolCall.name {
            case "set_goal":
                applySetGoalArguments(toolCall.arguments, profile: profile)
                shouldRefreshTargets = true
            case "set_custom_macros":
                if let targets = macroTargetsFromArguments(toolCall.arguments, profile: profile) {
                    upsertMacroTargets(from: targets, profile: profile, modelContext: modelContext)
                }
            default:
                break
            }
        }

        if shouldRefreshTargets {
            await refreshMacroTargets(profile: profile, modelContext: modelContext)
        }
    }

    private func refreshMacroTargets(profile: UserProfile, modelContext: ModelContext) async {
        do {
            if let targets = try await apiService.fetchMacroTargets() {
                upsertMacroTargets(from: targets, profile: profile, modelContext: modelContext)
            }
        } catch {
            self.error = error
        }
    }

    private func applySetGoalData(_ data: [String: Any], profile: UserProfile) {
        if let goalType = Self.stringValue(from: data["goal_type"]),
           let goal = GoalType(rawValue: goalType) {
            profile.goalType = goal
        }
        if let activity = Self.stringValue(from: data["activity_level"]),
           let level = ActivityLevel(rawValue: activity) {
            profile.activityLevel = level
        }
    }

    private func applySetGoalArguments(_ args: [String: AnyCodable], profile: UserProfile) {
        if let goalType = Self.stringValue(from: args["goal_type"]?.value),
           let goal = GoalType(rawValue: goalType) {
            profile.goalType = goal
        }
        if let activity = Self.stringValue(from: args["activity_level"]?.value),
           let level = ActivityLevel(rawValue: activity) {
            profile.activityLevel = level
        }
        if let targetWeight = Self.doubleValue(from: args["target_weight_kg"]?.value) {
            profile.targetWeightKg = targetWeight
        }
        if let goalRate = Self.doubleValue(from: args["goal_rate_kg_per_week"]?.value) {
            profile.goalRateKgPerWeek = goalRate
        }
        profile.updatedAt = Date()
    }

    private func upsertMeal(from response: MealResponseDTO, profile: UserProfile, modelContext: ModelContext) {
        if fetchMeal(id: response.id, modelContext: modelContext) != nil {
            return
        }
        let meal = Meal(
            id: response.id,
            userId: profile.id,
            name: response.name,
            mealType: response.mealType,
            timestamp: response.timestamp,
            notes: response.notes
        )
        for item in response.items {
            let food = FoodItem(
                id: item.id,
                name: item.name,
                source: item.source,
                grams: item.grams,
                calories: item.calories,
                proteinG: item.proteinG,
                carbsG: item.carbsG,
                fatG: item.fatG,
                fiberG: item.fiberG,
                servingSize: item.servingSize,
                servingUnit: item.servingUnit,
                servings: item.servings,
                barcode: item.barcode,
                nutriScoreGrade: item.nutriScoreGrade,
                confidence: item.confidence,
                portionDescription: item.portionDescription
            )
            food.sodiumMg = item.sodiumMg
            food.sugarG = item.sugarG
            food.saturatedFatG = item.saturatedFatG
            food.createdAt = item.createdAt
            meal.items.append(food)
        }
        meal.recalculateTotals()
        meal.totalCalories = response.totalCalories
        meal.totalProteinG = response.totalProteinG
        meal.totalCarbsG = response.totalCarbsG
        meal.totalFatG = response.totalFatG
        meal.totalFiberG = response.totalFiberG
        meal.isSynced = true
        meal.createdAt = response.createdAt
        meal.updatedAt = response.updatedAt
        modelContext.insert(meal)
    }

    private func upsertWorkoutLog(from response: WorkoutLogResponseDTO, profile: UserProfile, modelContext: ModelContext) {
        if fetchWorkoutLog(id: response.id, modelContext: modelContext) != nil {
            return
        }
        let log = WorkoutLog(
            id: response.id,
            userId: profile.id,
            planId: response.planId,
            name: response.name,
            workoutType: response.workoutType,
            source: response.source,
            startTime: response.startTime,
            durationMin: response.durationMin,
            caloriesBurned: response.caloriesBurned
        )
        log.endTime = response.endTime
        log.avgHeartRate = response.avgHeartRate
        log.maxHeartRate = response.maxHeartRate
        log.distanceKm = response.distanceKm
        log.notes = response.notes
        log.rating = response.rating
        log.healthKitId = response.healthKitId
        log.isSynced = true
        log.createdAt = response.createdAt
        log.updatedAt = response.updatedAt

        for set in response.sets {
            let setLog = WorkoutSetLog(
                id: set.id,
                exerciseName: set.exerciseName,
                setNumber: set.setNumber,
                reps: set.reps,
                weightKg: set.weightKg,
                durationSec: set.durationSec,
                completed: set.completed,
                isWarmup: set.isWarmup,
                isDropset: set.isDropset,
                orderIndex: set.orderIndex
            )
            setLog.distanceM = set.distanceM
            setLog.rpe = set.rpe
            setLog.notes = set.notes
            log.sets.append(setLog)
        }

        modelContext.insert(log)
    }

    private func upsertWorkoutPlan(from response: WorkoutPlanResponseDTO, profile: UserProfile, modelContext: ModelContext) {
        if fetchWorkoutPlan(id: response.id, modelContext: modelContext) != nil {
            return
        }
        let plan = WorkoutPlan(
            id: response.id,
            userId: profile.id,
            name: response.name,
            planDescription: response.description,
            workoutType: response.workoutType,
            scheduledDays: response.scheduledDays,
            estimatedDurationMin: response.estimatedDurationMin,
            isActive: response.isActive
        )
        plan.orderIndex = response.orderIndex
        plan.createdAt = response.createdAt
        plan.updatedAt = response.updatedAt

        for exercise in response.exercises {
            let ex = WorkoutExercise(
                id: exercise.id,
                name: exercise.name,
                muscleGroup: exercise.muscleGroup,
                equipment: exercise.equipment,
                sets: exercise.sets,
                repsMin: exercise.repsMin,
                repsMax: exercise.repsMax,
                durationSec: exercise.durationSec,
                restSec: exercise.restSec,
                orderIndex: exercise.orderIndex
            )
            ex.notes = exercise.notes
            ex.supersetGroup = exercise.supersetGroup
            plan.exercises.append(ex)
        }

        modelContext.insert(plan)
    }

    private func upsertMacroTargets(from response: MacroTargetsResponseDTO, profile: UserProfile, modelContext: ModelContext) {
        if let existing = fetchMacroTargets(modelContext: modelContext) {
            existing.calories = response.calories
            existing.proteinG = response.proteinG
            existing.carbsG = response.carbsG
            existing.fatG = response.fatG
            existing.fiberG = response.fiberG
            existing.bmr = response.bmr
            existing.tdee = response.tdee
            existing.calculatedAt = response.calculatedAt
        } else {
            let targets = MacroTargets(
                id: response.id,
                userId: profile.id,
                calories: response.calories,
                proteinG: response.proteinG,
                carbsG: response.carbsG,
                fatG: response.fatG,
                fiberG: response.fiberG,
                bmr: response.bmr,
                tdee: response.tdee
            )
            targets.calculatedAt = response.calculatedAt
            modelContext.insert(targets)
        }
    }

    private func macroTargetsFromData(_ data: [String: Any], profile: UserProfile) -> MacroTargetsResponseDTO? {
        guard let calories = Self.intValue(from: data["calories"]),
              let protein = Self.doubleValue(from: data["protein_g"]),
              let carbs = Self.doubleValue(from: data["carbs_g"]),
              let fat = Self.doubleValue(from: data["fat_g"]) else {
            return nil
        }
        return MacroTargetsResponseDTO(
            id: UUID(),
            userId: profile.id,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            fiberG: Self.doubleValue(from: data["fiber_g"]),
            bmr: nil,
            tdee: nil,
            calculatedAt: Date()
        )
    }

    private func macroTargetsFromArguments(_ args: [String: AnyCodable], profile: UserProfile) -> MacroTargetsResponseDTO? {
        guard let calories = Self.intValue(from: args["calories"]?.value),
              let protein = Self.doubleValue(from: args["protein_g"]?.value),
              let carbs = Self.doubleValue(from: args["carbs_g"]?.value),
              let fat = Self.doubleValue(from: args["fat_g"]?.value) else {
            return nil
        }
        return MacroTargetsResponseDTO(
            id: UUID(),
            userId: profile.id,
            calories: calories,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat,
            fiberG: Self.doubleValue(from: args["fiber_g"]?.value),
            bmr: nil,
            tdee: nil,
            calculatedAt: Date()
        )
    }

    private func fetchMeal(id: UUID, modelContext: ModelContext) -> Meal? {
        let mealId = id
        let descriptor = FetchDescriptor<Meal>(
            predicate: #Predicate<Meal> { $0.id == mealId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchWorkoutLog(id: UUID, modelContext: ModelContext) -> WorkoutLog? {
        let logId = id
        let descriptor = FetchDescriptor<WorkoutLog>(
            predicate: #Predicate<WorkoutLog> { $0.id == logId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchWorkoutPlan(id: UUID, modelContext: ModelContext) -> WorkoutPlan? {
        let planId = id
        let descriptor = FetchDescriptor<WorkoutPlan>(
            predicate: #Predicate<WorkoutPlan> { $0.id == planId }
        )
        return try? modelContext.fetch(descriptor).first
    }

    private func fetchMacroTargets(modelContext: ModelContext) -> MacroTargets? {
        let descriptor = FetchDescriptor<MacroTargets>()
        return try? modelContext.fetch(descriptor).first
    }

    private static func doubleValue(from value: Any?) -> Double? {
        switch value {
        case let doubleValue as Double:
            return doubleValue
        case let intValue as Int:
            return Double(intValue)
        case let number as NSNumber:
            return number.doubleValue
        case let stringValue as String:
            return Double(stringValue)
        default:
            return nil
        }
    }

    private static func intValue(from value: Any?) -> Int? {
        switch value {
        case let intValue as Int:
            return intValue
        case let doubleValue as Double:
            return Int(doubleValue)
        case let number as NSNumber:
            return number.intValue
        case let stringValue as String:
            return Int(stringValue)
        default:
            return nil
        }
    }

    private static func boolValue(from value: Any?) -> Bool? {
        switch value {
        case let boolValue as Bool:
            return boolValue
        case let number as NSNumber:
            return number.boolValue
        case let stringValue as String:
            return (stringValue as NSString).boolValue
        default:
            return nil
        }
    }

    private func updateSuggestions(for createdEntries: [[String: AnyCodable]]?) {
        // Generate contextual suggestions based on what was just logged
        var newSuggestions: [String] = []

        if let entries = createdEntries {
            for entry in entries {
                guard let type = entry["type"]?.value as? String else { continue }

                switch type {
                case "add_meal":
                    newSuggestions = [
                        "Log my water intake",
                        "Add a snack",
                        "How many calories today?"
                    ]
                case "add_workout":
                    newSuggestions = [
                        "Log my weight",
                        "Create a workout plan",
                        "What's my weekly summary?"
                    ]
                case "add_workout_plan":
                    newSuggestions = [
                        "Show my workout plans",
                        "Log today's workout",
                        "Set a new fitness goal"
                    ]
                case "add_water":
                    newSuggestions = [
                        "Log a meal",
                        "Add another glass of water",
                        "Show my daily summary"
                    ]
                case "add_weight":
                    newSuggestions = [
                        "Log body fat percentage",
                        "Show my progress",
                        "Log a workout"
                    ]
                case "set_goal", "set_custom_macros":
                    newSuggestions = [
                        "Show my daily summary",
                        "Log a meal",
                        "What's my progress?"
                    ]
                default:
                    break
                }
            }
        }

        // Default suggestions if no specific context
        if newSuggestions.isEmpty {
            let defaultSuggestions = [
                "Log breakfast",
                "Log my workout",
                "Add water intake",
                "Show daily summary",
                "Create workout plan",
                "Log my weight"
            ]
            newSuggestions = Array(defaultSuggestions.shuffled().prefix(3))
        }

        suggestions = newSuggestions
    }

    private static func stringValue(from value: Any?) -> String? {
        switch value {
        case let stringValue as String:
            return stringValue
        case let number as NSNumber:
            return number.stringValue
        default:
            return nil
        }
    }

    private static func uuidValue(from value: Any?) -> UUID? {
        if let uuid = value as? UUID {
            return uuid
        }
        if let stringValue = stringValue(from: value) {
            return UUID(uuidString: stringValue)
        }
        return nil
    }

    private static func intArrayValue(from value: Any?) -> [Int]? {
        if let array = value as? [Int] {
            return array
        }
        if let array = value as? [NSNumber] {
            return array.map { $0.intValue }
        }
        if let array = value as? [Any] {
            let ints = array.compactMap { intValue(from: $0) }
            return ints.isEmpty ? nil : ints
        }
        return nil
    }
}

enum ChatError: LocalizedError {
    case noUserProfile
    case sendFailed

    var errorDescription: String? {
        switch self {
        case .noUserProfile:
            return "User profile not found"
        case .sendFailed:
            return "Failed to send message"
        }
    }
}

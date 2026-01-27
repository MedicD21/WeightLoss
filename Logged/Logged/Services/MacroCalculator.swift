import Foundation

/// Macro nutrient calculator using Mifflin-St Jeor equation
final class MacroCalculator {
    // MARK: - Constants

    /// Calories per kg of body weight change (~7700 calories per kg of fat)
    private let caloriesPerKg: Double = 7700

    /// Default protein per kg body weight
    private let defaultProteinPerKg: Double = 1.8

    /// Minimum protein percentage of calories
    private let minProteinPercent: Double = 0.10

    /// Fat percentage of total calories
    private let fatPercent: Double = 0.25

    /// Fiber per 1000 calories
    private let fiberPer1000Kcal: Double = 14

    // MARK: - Calculation Results

    struct MacroTargets {
        let calories: Int
        let proteinG: Double
        let carbsG: Double
        let fatG: Double
        let fiberG: Double?
        let bmr: Int
        let tdee: Int
        let deficitOrSurplus: Int
    }

    // MARK: - Public Methods

    /// Calculate complete macro nutrient targets
    /// - Parameters:
    ///   - sex: Biological sex
    ///   - weightKg: Body weight in kg
    ///   - heightCm: Height in cm
    ///   - age: Age in years
    ///   - activityLevel: Activity level
    ///   - goalType: Fitness goal
    ///   - goalRateKgPerWeek: Rate of weight change
    ///   - proteinPerKg: Optional protein ratio override
    /// - Returns: MacroTargets with all calculated values
    func calculate(
        sex: Sex,
        weightKg: Double,
        heightCm: Double,
        age: Int,
        activityLevel: ActivityLevel,
        goalType: GoalType,
        goalRateKgPerWeek: Double = 0.5,
        proteinPerKg: Double? = nil,
        macroPlan: MacroPlan = .balanced,
        macroPercents: (protein: Double, carbs: Double, fat: Double)? = nil
    ) -> MacroTargets {
        _ = proteinPerKg
        // Calculate base metabolic values
        let bmr = calculateBMR(sex: sex, weightKg: weightKg, heightCm: heightCm, age: age)
        let tdee = calculateTDEE(bmr: bmr, activityLevel: activityLevel)
        let (targetCalories, adjustment) = calculateTargetCalories(
            tdee: tdee,
            goalType: goalType,
            goalRateKgPerWeek: goalRateKgPerWeek
        )

        let split = normalizedSplit(for: macroPlan, custom: macroPercents)
        var proteinCalories = Double(targetCalories) * (split.protein / 100)
        var carbsCalories = Double(targetCalories) * (split.carbs / 100)
        var fatCalories = Double(targetCalories) * (split.fat / 100)

        // Ensure minimum protein percentage for auto plans
        let minProteinCalories = Double(targetCalories) * minProteinPercent
        if macroPlan != .custom && proteinCalories < minProteinCalories {
            proteinCalories = minProteinCalories
            let remaining = Double(targetCalories) - proteinCalories
            let fatFromRemaining = remaining * (fatPercent)
            fatCalories = min(fatFromRemaining, remaining)
            carbsCalories = max(remaining - fatCalories, 0)
        }

        let proteinG = round((proteinCalories / 4) * 10) / 10
        let carbsG = round((carbsCalories / 4) * 10) / 10
        let fatG = round((fatCalories / 9) * 10) / 10

        // Calculate fiber (based on calorie target)
        let fiberG = round((Double(targetCalories) / 1000) * fiberPer1000Kcal * 10) / 10

        return MacroTargets(
            calories: targetCalories,
            proteinG: proteinG,
            carbsG: carbsG,
            fatG: fatG,
            fiberG: fiberG,
            bmr: bmr,
            tdee: tdee,
            deficitOrSurplus: adjustment
        )
    }

    private func normalizedSplit(
        for plan: MacroPlan,
        custom: (protein: Double, carbs: Double, fat: Double)?
    ) -> (protein: Double, carbs: Double, fat: Double) {
        let base: (protein: Double, carbs: Double, fat: Double)
        if plan == .custom, let custom {
            base = custom
        } else {
            base = plan.defaultPercents
        }

        let total = base.protein + base.carbs + base.fat
        guard total > 0 else {
            return plan.defaultPercents
        }

        if abs(total - 100) < 0.01 {
            return base
        }

        let scale = 100 / total
        return (
            protein: base.protein * scale,
            carbs: base.carbs * scale,
            fat: base.fat * scale
        )
    }

    /// Calculate BMR using Mifflin-St Jeor equation
    /// - Male:   BMR = (10 × weight_kg) + (6.25 × height_cm) - (5 × age) + 5
    /// - Female: BMR = (10 × weight_kg) + (6.25 × height_cm) - (5 × age) - 161
    func calculateBMR(sex: Sex, weightKg: Double, heightCm: Double, age: Int) -> Int {
        var bmr = (10 * weightKg) + (6.25 * heightCm) - (5 * Double(age))

        switch sex {
        case .male:
            bmr += 5
        case .female:
            bmr -= 161
        }

        return Int(round(bmr))
    }

    /// Calculate TDEE (Total Daily Energy Expenditure)
    func calculateTDEE(bmr: Int, activityLevel: ActivityLevel) -> Int {
        return Int(round(Double(bmr) * activityLevel.multiplier))
    }

    /// Calculate target calories based on goal
    /// - Returns: Tuple of (target_calories, deficit_or_surplus)
    func calculateTargetCalories(
        tdee: Int,
        goalType: GoalType,
        goalRateKgPerWeek: Double
    ) -> (Int, Int) {
        switch goalType {
        case .maintain:
            return (tdee, 0)

        case .cut:
            // Deficit for weight loss
            let dailyAdjustment = Int(round((caloriesPerKg / 7) * goalRateKgPerWeek))
            let target = max(tdee - dailyAdjustment, 1200) // Minimum safe calories
            return (target, -dailyAdjustment)

        case .bulk:
            // Surplus for weight gain (slower to minimize fat gain)
            let dailyAdjustment = Int(round((caloriesPerKg / 7) * goalRateKgPerWeek * 0.5))
            return (tdee + dailyAdjustment, dailyAdjustment)
        }
    }

    /// Estimate weeks to reach target weight
    func estimateWeeksToGoal(
        currentWeightKg: Double,
        targetWeightKg: Double,
        rateKgPerWeek: Double
    ) -> Int? {
        guard rateKgPerWeek > 0 else { return nil }

        let difference = abs(currentWeightKg - targetWeightKg)
        return Int(round(difference / rateKgPerWeek))
    }

    /// Validate that goal rate is safe and realistic
    /// - Returns: Tuple of (is_valid, warning_message)
    func validateGoalRate(
        goalType: GoalType,
        rateKgPerWeek: Double
    ) -> (Bool, String?) {
        if goalType == .maintain {
            return rateKgPerWeek == 0 ? (true, nil) : (false, "Rate should be 0 for maintenance goal")
        }

        guard rateKgPerWeek >= 0 else {
            return (false, "Rate must be positive")
        }

        switch goalType {
        case .cut:
            if rateKgPerWeek > 1.0 {
                return (false, "Losing more than 1kg/week is not recommended for health")
            }
            if rateKgPerWeek > 0.75 {
                return (true, "This is an aggressive deficit. Consider 0.5kg/week for sustainability")
            }

        case .bulk:
            if rateKgPerWeek > 0.5 {
                return (false, "Gaining more than 0.5kg/week will likely result in excess fat gain")
            }
            if rateKgPerWeek > 0.25 {
                return (true, "Consider a slower bulk (0.25kg/week) to minimize fat gain")
            }

        case .maintain:
            break
        }

        return (true, nil)
    }
}

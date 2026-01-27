import SwiftUI
import SwiftData

/// User profile and settings view
struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Query private var macroTargets: [MacroTargets]

    @State private var showingEditProfile = false
    @State private var showingGoalsSheet = false
    @State private var showingHealthKitSettings = false

    var userProfile: UserProfile? { userProfiles.first }
    var targets: MacroTargets? { macroTargets.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Profile header
                    ProfileHeaderSection(profile: userProfile)

                    // Current targets
                    if let targets = targets {
                        CurrentTargetsSection(targets: targets)
                    }

                    // Body metrics
                    BodyMetricsSection(profile: userProfile)

                    // Goals
                    GoalsSection(profile: userProfile)

                    // Settings
                    SettingsSection(useMetric: userProfile?.useMetric ?? false)

                    // Sign out
                    SignOutButton()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditProfile = true
                    } label: {
                        Text("Edit")
                    }
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showingGoalsSheet) {
                EditGoalsView()
            }
        }
    }
}

// MARK: - Profile Header

struct ProfileHeaderSection: View {
    let profile: UserProfile?
    private var useMetric: Bool { profile?.useMetric ?? false }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Avatar
            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: 64, height: 64)
                .overlay(
                    Text(profile?.displayName?.prefix(1).uppercased() ?? "?")
                        .font(Theme.Typography.title2)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(profile?.displayName ?? "User")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(profile?.email ?? "")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)

                if let profile = profile, !profile.isProfileComplete {
                    Text("Complete your profile to get personalized targets")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.warning)
                }
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Current Targets

struct CurrentTargetsSection: View {
    let targets: MacroTargets

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Daily Targets")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.md) {
                TargetCard(label: "Calories", value: "\(targets.calories)", unit: "cal", color: Theme.Colors.calories)
                TargetCard(label: "Protein", value: String(format: "%.0f", targets.proteinG), unit: "g", color: Theme.Colors.protein)
            }

            HStack(spacing: Theme.Spacing.md) {
                TargetCard(label: "Carbs", value: String(format: "%.0f", targets.carbsG), unit: "g", color: Theme.Colors.carbs)
                TargetCard(label: "Fat", value: String(format: "%.0f", targets.fatG), unit: "g", color: Theme.Colors.fat)
            }

            if let bmr = targets.bmr, let tdee = targets.tdee {
                HStack {
                    Text("BMR: \(bmr) cal")
                    Spacer()
                    Text("TDEE: \(tdee) cal")
                }
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct TargetCard: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.Typography.title3)
                    .foregroundColor(color)
                Text(unit)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surfaceHighlight)
        .cornerRadius(Theme.Radius.small)
    }
}

// MARK: - Body Metrics

struct BodyMetricsSection: View {
    let profile: UserProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Body Metrics")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                MetricRow(label: "Height", value: profile?.heightDisplay ?? "Not set")
                MetricRow(label: "Weight", value: profile?.weightDisplay ?? "Not set")
                MetricRow(label: "Age", value: profile?.age.map { "\($0) years" } ?? "Not set")
                MetricRow(label: "Sex", value: profile?.sex?.displayName ?? "Not set")
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }
}

// MARK: - Goals Section

struct GoalsSection: View {
    let profile: UserProfile?
    private var useMetric: Bool { profile?.useMetric ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Goals")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                MetricRow(label: "Goal", value: profile?.goalType.displayName ?? "Not set")
                MetricRow(label: "Activity Level", value: profile?.activityLevel.displayName ?? "Moderate")
                if let target = profile?.targetWeightKg {
                    MetricRow(
                        label: "Target Weight",
                        value: String(
                            format: "%.1f %@",
                            useMetric ? target : UnitConverter.kgToLb(target),
                            useMetric ? "kg" : "lb"
                        )
                    )
                }
                if let rate = profile?.goalRateKgPerWeek, rate > 0 {
                    MetricRow(
                        label: "Weekly Rate",
                        value: String(
                            format: "%.1f %@/week",
                            useMetric ? rate : UnitConverter.kgToLb(rate),
                            useMetric ? "kg" : "lb"
                        )
                    )
                }
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Settings Section

struct SettingsSection: View {
    @StateObject private var healthKit = HealthKitService.shared
    let useMetric: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Settings")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: 0) {
                SettingsRow(icon: "heart.fill", title: "HealthKit", value: healthKit.isAuthorized ? "Connected" : "Not connected")
                Divider().background(Theme.Colors.border)
                SettingsRow(icon: "bell.fill", title: "Notifications", value: "On")
                Divider().background(Theme.Colors.border)
                SettingsRow(icon: "ruler", title: "Units", value: useMetric ? "Metric" : "Imperial")
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.Colors.accent)
                .frame(width: 24)

            Text(title)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            Text(value)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}

// MARK: - Sign Out

struct SignOutButton: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            appState.signOut()
        } label: {
            Text("Sign Out")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.error)
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.md)
                .cardStyle()
        }
    }
}

// MARK: - Edit Profile

struct EditProfileView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Query private var macroTargets: [MacroTargets]
    @Environment(\.dismiss) private var dismiss

    @State private var displayName = ""
    @State private var email = ""
    @State private var sex: Sex? = nil
    @State private var birthDate = Date()
    @State private var heightFeet = ""
    @State private var heightInches = ""
    @State private var heightCm = ""
    @State private var weightText = ""
    @State private var dailyWaterGoalText = ""
    @State private var activityLevel: ActivityLevel = .moderate
    @State private var useMetric = false
    @State private var errorMessage: String?
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Profile") {
                    TextField("Display name", text: $displayName)
                    TextField("Email", text: $email)
                        .keyboardType(.emailAddress)

                    Picker("Sex", selection: $sex) {
                        Text("Not set").tag(Optional<Sex>.none)
                        ForEach(Sex.allCases, id: \.self) { item in
                            Text(item.displayName).tag(Optional(item))
                        }
                    }

                    DatePicker("Birth date", selection: $birthDate, displayedComponents: .date)
                }

                Section("Body Metrics") {
                    if useMetric {
                        HStack {
                            TextField("Height", text: $heightCm)
                                .keyboardType(.decimalPad)
                            Text("cm")
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    } else {
                        HStack(spacing: Theme.Spacing.sm) {
                            TextField("ft", text: $heightFeet)
                                .keyboardType(.numberPad)
                            Text("ft")
                                .foregroundColor(Theme.Colors.textSecondary)

                            TextField("in", text: $heightInches)
                                .keyboardType(.numberPad)
                            Text("in")
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    HStack {
                        TextField(useMetric ? "Weight" : "Weight", text: $weightText)
                            .keyboardType(.decimalPad)
                        Text(useMetric ? "kg" : "lb")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Section("Daily Goals") {
                    HStack {
                        TextField("Water goal", text: $dailyWaterGoalText)
                            .keyboardType(.decimalPad)
                        Text(useMetric ? "ml" : "oz")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    Picker("Activity level", selection: $activityLevel) {
                        ForEach(ActivityLevel.allCases, id: \.self) { level in
                            Text(level.displayName).tag(level)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
            }
            .navigationTitle("Edit Profile")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveProfile() }
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                loadProfile()
            }
        }
    }

    private func loadProfile() {
        guard let profile = userProfiles.first else {
            useMetric = false
            return
        }

        displayName = profile.displayName ?? ""
        email = profile.email
        sex = profile.sex
        birthDate = profile.birthDate ?? Date()
        activityLevel = profile.activityLevel
        useMetric = profile.useMetric

        if let height = profile.heightCm {
            if useMetric {
                heightCm = String(format: "%.1f", height)
            } else {
                let inchesTotal = UnitConverter.cmToIn(height)
                let feet = Int(inchesTotal / 12)
                let inches = Int(round(inchesTotal.truncatingRemainder(dividingBy: 12)))
                heightFeet = "\(feet)"
                heightInches = "\(inches)"
            }
        }

        if let weightKg = profile.currentWeightKg {
            let value = useMetric ? weightKg : UnitConverter.kgToLb(weightKg)
            weightText = String(format: "%.1f", value)
        }

        let waterGoalValue = useMetric
            ? Double(profile.dailyWaterGoalMl)
            : UnitConverter.mlToFlOz(profile.dailyWaterGoalMl)
        dailyWaterGoalText = String(format: "%.0f", waterGoalValue)
    }

    private func saveProfile() {
        let profile = getOrCreateProfile()

        profile.displayName = displayName.isEmpty ? nil : displayName
        profile.email = email.isEmpty ? profile.email : email
        profile.sex = sex
        profile.birthDate = birthDate
        profile.activityLevel = activityLevel

        if useMetric {
            profile.heightCm = Double(heightCm)
        } else if let feet = Double(heightFeet), let inches = Double(heightInches) {
            let totalInches = (feet * 12) + inches
            profile.heightCm = UnitConverter.inToCm(totalInches)
        }

        if let weightValue = Double(weightText) {
            profile.currentWeightKg = useMetric ? weightValue : UnitConverter.lbToKg(weightValue)
        }

        if let waterGoal = Double(dailyWaterGoalText) {
            let goalMl = useMetric ? Int(waterGoal.rounded()) : UnitConverter.flOzToMl(waterGoal)
            profile.dailyWaterGoalMl = goalMl
        }

        profile.updatedAt = Date()

        updateMacroTargets(for: profile)
        dismiss()
    }

    private func updateMacroTargets(for profile: UserProfile) {
        let targetModel: MacroTargets
        if let existing = macroTargets.first {
            targetModel = existing
        } else {
            targetModel = MacroTargets(
                userId: profile.id,
                calories: 0,
                proteinG: 0,
                carbsG: 0,
                fatG: 0,
                fiberG: nil,
                bmr: nil,
                tdee: nil
            )
            modelContext.insert(targetModel)
        }

        if profile.useManualMacros,
           let protein = profile.manualProteinG,
           let carbs = profile.manualCarbsG,
           let fat = profile.manualFatG {
            let manualCalories = profile.manualCalories ?? Int(round((protein * 4) + (carbs * 4) + (fat * 9)))
            targetModel.calories = manualCalories
            targetModel.proteinG = protein
            targetModel.carbsG = carbs
            targetModel.fatG = fat
            targetModel.fiberG = round((Double(manualCalories) / 1000) * 14 * 10) / 10
            targetModel.bmr = nil
            targetModel.tdee = nil
            targetModel.calculatedAt = Date()
            return
        }

        guard let sex = profile.sex,
              let age = profile.age,
              let height = profile.heightCm,
              let weight = profile.currentWeightKg else {
            return
        }

        let calculator = MacroCalculator()
        let targets = calculator.calculate(
            sex: sex,
            weightKg: weight,
            heightCm: height,
            age: age,
            activityLevel: profile.activityLevel,
            goalType: profile.goalType,
            goalRateKgPerWeek: profile.goalRateKgPerWeek,
            macroPlan: profile.macroPlan,
            macroPercents: (protein: profile.macroProteinPercent, carbs: profile.macroCarbsPercent, fat: profile.macroFatPercent)
        )

        targetModel.calories = targets.calories
        targetModel.proteinG = targets.proteinG
        targetModel.carbsG = targets.carbsG
        targetModel.fatG = targets.fatG
        targetModel.fiberG = targets.fiberG
        targetModel.bmr = targets.bmr
        targetModel.tdee = targets.tdee
        targetModel.calculatedAt = Date()
    }

    private func getOrCreateProfile() -> UserProfile {
        if let profile = userProfiles.first {
            return profile
        }
        let profile = UserProfile(email: "user@example.com")
        modelContext.insert(profile)
        return profile
    }
}

// MARK: - Edit Goals

struct EditGoalsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Query private var macroTargets: [MacroTargets]
    @Environment(\.dismiss) private var dismiss

    @State private var goalType: GoalType = .maintain
    @State private var goalRateText = ""
    @State private var targetWeightText = ""
    @State private var macroPlan: MacroPlan = .balanced
    @State private var proteinPercentText = ""
    @State private var carbsPercentText = ""
    @State private var fatPercentText = ""
    @State private var useManualMacros = false
    @State private var manualCaloriesText = ""
    @State private var manualProteinText = ""
    @State private var manualCarbsText = ""
    @State private var manualFatText = ""
    @State private var errorMessage: String?
    @State private var useMetric = false
    @State private var didLoad = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    Picker("Goal", selection: $goalType) {
                        ForEach(GoalType.allCases, id: \.self) { goal in
                            Text(goal.displayName).tag(goal)
                        }
                    }

                    if goalType != .maintain {
                        HStack {
                            TextField("Rate", text: $goalRateText)
                                .keyboardType(.decimalPad)
                            Text(useMetric ? "kg/week" : "lb/week")
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    HStack {
                        TextField("Target weight", text: $targetWeightText)
                            .keyboardType(.decimalPad)
                        Text(useMetric ? "kg" : "lb")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Section("Macro Plan") {
                    Picker("Plan", selection: $macroPlan) {
                        ForEach(MacroPlan.allCases, id: \.self) { plan in
                            Text(plan.displayName).tag(plan)
                        }
                    }

                    if macroPlan == .custom && !useManualMacros {
                        HStack {
                            TextField("Protein %", text: $proteinPercentText)
                                .keyboardType(.decimalPad)
                            Text("%")
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        HStack {
                            TextField("Carbs %", text: $carbsPercentText)
                                .keyboardType(.decimalPad)
                            Text("%")
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        HStack {
                            TextField("Fat %", text: $fatPercentText)
                                .keyboardType(.decimalPad)
                            Text("%")
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        Text("Total: \(percentTotalText)")
                            .font(Theme.Typography.caption)
                            .foregroundColor(percentTotalIsValid ? Theme.Colors.textSecondary : Theme.Colors.error)
                    }
                }

                Section("Manual Macro Goals") {
                    Toggle("Set macros manually", isOn: $useManualMacros)

                    if useManualMacros {
                        HStack {
                            TextField("Calories", text: $manualCaloriesText)
                                .keyboardType(.numberPad)
                            Text("cal")
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        HStack {
                            TextField("Protein (g)", text: $manualProteinText)
                                .keyboardType(.decimalPad)
                        }

                        HStack {
                            TextField("Carbs (g)", text: $manualCarbsText)
                                .keyboardType(.decimalPad)
                        }

                        HStack {
                            TextField("Fat (g)", text: $manualFatText)
                                .keyboardType(.decimalPad)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
            }
            .navigationTitle("Goals")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { saveGoals() }
                }
            }
            .onAppear {
                guard !didLoad else { return }
                didLoad = true
                loadGoals()
            }
        }
    }

    private func loadGoals() {
        guard let profile = userProfiles.first else {
            useMetric = false
            return
        }

        useMetric = profile.useMetric
        goalType = profile.goalType

        if profile.goalType != .maintain {
            let rate = useMetric ? profile.goalRateKgPerWeek : UnitConverter.kgToLb(profile.goalRateKgPerWeek)
            goalRateText = String(format: "%.1f", rate)
        }

        if let targetWeightKg = profile.targetWeightKg {
            let target = useMetric ? targetWeightKg : UnitConverter.kgToLb(targetWeightKg)
            targetWeightText = String(format: "%.1f", target)
        }

        macroPlan = profile.macroPlan
        proteinPercentText = String(format: "%.0f", profile.macroProteinPercent)
        carbsPercentText = String(format: "%.0f", profile.macroCarbsPercent)
        fatPercentText = String(format: "%.0f", profile.macroFatPercent)

        useManualMacros = profile.useManualMacros
        if let manualCalories = profile.manualCalories {
            manualCaloriesText = "\(manualCalories)"
        }
        if let manualProtein = profile.manualProteinG {
            manualProteinText = String(format: "%.0f", manualProtein)
        }
        if let manualCarbs = profile.manualCarbsG {
            manualCarbsText = String(format: "%.0f", manualCarbs)
        }
        if let manualFat = profile.manualFatG {
            manualFatText = String(format: "%.0f", manualFat)
        }
    }

    private func saveGoals() {
        let profile = getOrCreateProfile()
        errorMessage = nil
        profile.goalType = goalType

        if goalType == .maintain {
            profile.goalRateKgPerWeek = 0
        } else if let rateValue = Double(goalRateText) {
            profile.goalRateKgPerWeek = useMetric ? rateValue : UnitConverter.lbToKg(rateValue)
        }

        if let targetValue = Double(targetWeightText) {
            profile.targetWeightKg = useMetric ? targetValue : UnitConverter.lbToKg(targetValue)
        }

        profile.macroPlan = macroPlan
        profile.useManualMacros = useManualMacros

        if useManualMacros {
            guard let protein = Double(manualProteinText),
                  let carbs = Double(manualCarbsText),
                  let fat = Double(manualFatText) else {
                errorMessage = "Enter protein, carbs, and fat for manual macros."
                return
            }

            let macroCalories = (protein * 4) + (carbs * 4) + (fat * 9)
            if let manualCalories = Int(manualCaloriesText), abs(Double(manualCalories) - macroCalories) > 25 {
                errorMessage = "Macro calories must match total calories. Current macros total \(Int(round(macroCalories))) cal."
                return
            }

            profile.manualCalories = Int(round(macroCalories))
            profile.manualProteinG = protein
            profile.manualCarbsG = carbs
            profile.manualFatG = fat
        } else {
            profile.manualCalories = nil
            profile.manualProteinG = nil
            profile.manualCarbsG = nil
            profile.manualFatG = nil

            if macroPlan == .custom {
                guard let protein = Double(proteinPercentText),
                      let carbs = Double(carbsPercentText),
                      let fat = Double(fatPercentText) else {
                    errorMessage = "Enter all macro percentages."
                    return
                }
                let total = protein + carbs + fat
                if abs(total - 100) > 0.1 {
                    errorMessage = "Macro percentages must total 100%."
                    return
                }
                profile.macroProteinPercent = protein
                profile.macroCarbsPercent = carbs
                profile.macroFatPercent = fat
            } else {
                let defaults = macroPlan.defaultPercents
                profile.macroProteinPercent = defaults.protein
                profile.macroCarbsPercent = defaults.carbs
                profile.macroFatPercent = defaults.fat
            }
        }

        profile.updatedAt = Date()
        updateMacroTargets(for: profile)
        dismiss()
    }

    private var percentTotalText: String {
        let total = (Double(proteinPercentText) ?? 0)
            + (Double(carbsPercentText) ?? 0)
            + (Double(fatPercentText) ?? 0)
        return String(format: "%.0f%%", total)
    }

    private var percentTotalIsValid: Bool {
        let total = (Double(proteinPercentText) ?? 0)
            + (Double(carbsPercentText) ?? 0)
            + (Double(fatPercentText) ?? 0)
        return abs(total - 100) < 0.1
    }

    private func updateMacroTargets(for profile: UserProfile) {
        let targetModel: MacroTargets
        if let existing = macroTargets.first {
            targetModel = existing
        } else {
            targetModel = MacroTargets(
                userId: profile.id,
                calories: 0,
                proteinG: 0,
                carbsG: 0,
                fatG: 0,
                fiberG: nil,
                bmr: nil,
                tdee: nil
            )
            modelContext.insert(targetModel)
        }

        if profile.useManualMacros,
           let protein = profile.manualProteinG,
           let carbs = profile.manualCarbsG,
           let fat = profile.manualFatG {
            let manualCalories = profile.manualCalories ?? Int(round((protein * 4) + (carbs * 4) + (fat * 9)))
            targetModel.calories = manualCalories
            targetModel.proteinG = protein
            targetModel.carbsG = carbs
            targetModel.fatG = fat
            targetModel.fiberG = round((Double(manualCalories) / 1000) * 14 * 10) / 10
            targetModel.bmr = nil
            targetModel.tdee = nil
            targetModel.calculatedAt = Date()
            return
        }

        guard let sex = profile.sex,
              let age = profile.age,
              let height = profile.heightCm,
              let weight = profile.currentWeightKg else {
            return
        }

        let calculator = MacroCalculator()
        let targets = calculator.calculate(
            sex: sex,
            weightKg: weight,
            heightCm: height,
            age: age,
            activityLevel: profile.activityLevel,
            goalType: profile.goalType,
            goalRateKgPerWeek: profile.goalRateKgPerWeek,
            macroPlan: profile.macroPlan,
            macroPercents: (protein: profile.macroProteinPercent, carbs: profile.macroCarbsPercent, fat: profile.macroFatPercent)
        )

        targetModel.calories = targets.calories
        targetModel.proteinG = targets.proteinG
        targetModel.carbsG = targets.carbsG
        targetModel.fatG = targets.fatG
        targetModel.fiberG = targets.fiberG
        targetModel.bmr = targets.bmr
        targetModel.tdee = targets.tdee
        targetModel.calculatedAt = Date()
    }

    private func getOrCreateProfile() -> UserProfile {
        if let profile = userProfiles.first {
            return profile
        }
        let profile = UserProfile(email: "user@example.com")
        modelContext.insert(profile)
        return profile
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
        .modelContainer(for: [UserProfile.self, MacroTargets.self])
}

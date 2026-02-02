import SwiftUI
import SwiftData

/// Onboarding flow to collect user profile data
struct OnboardingView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]

    @State private var currentStep = 0
    @State private var displayName = ""
    @State private var sex: Sex?
    @State private var birthDate = Calendar.current.date(byAdding: .year, value: -25, to: Date())!
    @State private var heightCm: Double = UnitConverter.inToCm(69)
    @State private var weightKg: Double = UnitConverter.lbToKg(170)
    @State private var activityLevel: ActivityLevel = .moderate
    @State private var goalType: GoalType = .maintain
    @State private var goalRate: Double = 0.5

    private let totalSteps = 5

    var body: some View {
        VStack(spacing: 0) {
            // Progress indicator
            ProgressIndicator(current: currentStep, total: totalSteps)
                .padding(.horizontal, Theme.Spacing.lg)
                .padding(.top, Theme.Spacing.lg)

            // Content
            TabView(selection: $currentStep) {
                WelcomeStep(name: $displayName)
                    .tag(0)

                BodyMetricsStep(
                    sex: $sex,
                    birthDate: $birthDate,
                    heightCm: $heightCm,
                    weightKg: $weightKg
                )
                .tag(1)

                ActivityStep(activityLevel: $activityLevel)
                    .tag(2)

                GoalStep(
                    goalType: $goalType,
                    goalRate: $goalRate,
                    currentWeight: weightKg
                )
                .tag(3)

                SummaryStep(
                    name: displayName,
                    sex: sex,
                    height: heightCm,
                    weight: weightKg,
                    activity: activityLevel,
                    goal: goalType
                )
                .tag(4)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut, value: currentStep)

            // Navigation buttons
            HStack(spacing: Theme.Spacing.md) {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation {
                            currentStep -= 1
                        }
                    }
                    .buttonStyle(.secondary)
                }

                Button(currentStep == totalSteps - 1 ? "Get Started" : "Continue") {
                    if currentStep == totalSteps - 1 {
                        completeOnboarding()
                    } else {
                        withAnimation {
                            currentStep += 1
                        }
                    }
                }
                .buttonStyle(.primary)
                .disabled(!canProceed)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.bottom, Theme.Spacing.xl)
        }
        .background(Color.clear)
    }

    private var canProceed: Bool {
        switch currentStep {
        case 0: return !displayName.isEmpty
        case 1: return sex != nil
        default: return true
        }
    }

    private func completeOnboarding() {
        // Get or create user profile
        let profile: UserProfile
        if let existing = userProfiles.first {
            profile = existing
        } else {
            profile = UserProfile(
                email: "user@example.com" // Will be updated from auth
            )
            modelContext.insert(profile)
        }

        // Update profile
        profile.displayName = displayName
        profile.sex = sex
        profile.birthDate = birthDate
        profile.heightCm = heightCm
        profile.currentWeightKg = weightKg
        profile.activityLevel = activityLevel
        profile.goalType = goalType
        profile.goalRateKgPerWeek = goalType == .maintain ? 0 : goalRate
        profile.useMetric = false
        profile.updatedAt = Date()

        // Calculate macro targets
        if let sex = sex, let age = profile.age {
            let calculator = MacroCalculator()
            let targets = calculator.calculate(
                sex: sex,
                weightKg: weightKg,
                heightCm: heightCm,
                age: age,
                activityLevel: activityLevel,
                goalType: goalType,
                goalRateKgPerWeek: goalRate,
                macroPlan: profile.macroPlanValue,
                macroPercents: profile.macroPercentsValue
            )

            let macroTargets = MacroTargets(
                userId: profile.id,
                calories: targets.calories,
                proteinG: targets.proteinG,
                carbsG: targets.carbsG,
                fatG: targets.fatG,
                fiberG: targets.fiberG,
                bmr: targets.bmr,
                tdee: targets.tdee
            )
            modelContext.insert(macroTargets)
        }

        appState.completeOnboarding()
    }
}

// MARK: - Progress Indicator

struct ProgressIndicator: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(0..<total, id: \.self) { index in
                Capsule()
                    .fill(index <= current ? Theme.Colors.accent : Theme.Colors.surfaceHighlight)
                    .frame(height: 4)
            }
        }
    }
}

// MARK: - Welcome Step

struct WelcomeStep: View {
    @Binding var name: String

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            Spacer()

            VStack(spacing: Theme.Spacing.md) {
                Image(systemName: "hand.wave.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.Colors.accent)

                Text("Welcome to Logged")
                    .font(Theme.Typography.title1)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Let's personalize your experience")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("What should we call you?")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                TextField("Your name", text: $name)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textPrimary)
                    .padding(Theme.Spacing.md)
                    .background(Theme.Colors.surface)
                    .cornerRadius(Theme.Radius.medium)
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
            Spacer()
        }
    }
}

// MARK: - Body Metrics Step

struct BodyMetricsStep: View {
    @Binding var sex: Sex?
    @Binding var birthDate: Date
    @Binding var heightCm: Double
    @Binding var weightKg: Double

    private var heightInches: Binding<Double> {
        Binding(
            get: { UnitConverter.cmToIn(heightCm) },
            set: { heightCm = UnitConverter.inToCm($0) }
        )
    }

    private var weightLbs: Binding<Double> {
        Binding(
            get: { UnitConverter.kgToLb(weightKg) },
            set: { weightKg = UnitConverter.lbToKg($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.Spacing.xl) {
                VStack(spacing: Theme.Spacing.sm) {
                    Text("Body Metrics")
                        .font(Theme.Typography.title2)
                        .foregroundColor(Theme.Colors.textPrimary)

                    Text("This helps us calculate your targets")
                        .font(Theme.Typography.body)
                        .foregroundColor(Theme.Colors.textSecondary)
                }

                // Sex selection
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Biological Sex")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)

                    HStack(spacing: Theme.Spacing.md) {
                        ForEach(Sex.allCases, id: \.self) { option in
                            Button {
                                sex = option
                            } label: {
                                Text(option.displayName)
                                    .font(Theme.Typography.body)
                                    .foregroundColor(sex == option ? .white : Theme.Colors.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .padding(Theme.Spacing.md)
                                    .background(sex == option ? Theme.Colors.accent : Theme.Colors.surface)
                                    .cornerRadius(Theme.Radius.medium)
                            }
                        }
                    }
                }

                // Birth date
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Birth Date")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)

                    DatePicker("", selection: $birthDate, displayedComponents: .date)
                        .datePickerStyle(.wheel)
                        .labelsHidden()
                }

                // Height
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Height")
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text(UnitConverter.heightStringFromCm(heightCm))
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.accent)
                    }

                    Slider(value: heightInches, in: 48...84, step: 1)
                        .tint(Theme.Colors.accent)
                }

                // Weight
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Weight")
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text(String(format: "%.1f lb", UnitConverter.kgToLb(weightKg)))
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.accent)
                    }

                    Slider(value: weightLbs, in: 90...350, step: 1)
                        .tint(Theme.Colors.accent)
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .padding(.top, Theme.Spacing.xl)
        }
    }
}

// MARK: - Activity Step

struct ActivityStep: View {
    @Binding var activityLevel: ActivityLevel

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.sm) {
                Text("Activity Level")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("How active are you typically?")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(ActivityLevel.allCases, id: \.self) { level in
                    Button {
                        activityLevel = level
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(level.displayName)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                Text(level.description)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            if activityLevel == level {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.Colors.accent)
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .background(activityLevel == level ? Theme.Colors.accent.opacity(0.2) : Theme.Colors.surface)
                        .cornerRadius(Theme.Radius.medium)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
        .padding(.top, Theme.Spacing.xl)
    }
}

// MARK: - Goal Step

struct GoalStep: View {
    @Binding var goalType: GoalType
    @Binding var goalRate: Double
    let currentWeight: Double

    private var goalRateLbs: Binding<Double> {
        Binding(
            get: { UnitConverter.kgToLb(goalRate) },
            set: { goalRate = UnitConverter.lbToKg($0) }
        )
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.sm) {
                Text("Your Goal")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("What do you want to achieve?")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                ForEach(GoalType.allCases, id: \.self) { goal in
                    Button {
                        goalType = goal
                    } label: {
                        HStack {
                            Image(systemName: goal.icon)
                                .font(.system(size: 24))
                                .foregroundColor(goalType == goal ? Theme.Colors.accent : Theme.Colors.textSecondary)
                                .frame(width: 40)

                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(goal.displayName)
                                    .font(Theme.Typography.headline)
                                    .foregroundColor(Theme.Colors.textPrimary)

                                Text(goal.description)
                                    .font(Theme.Typography.caption)
                                    .foregroundColor(Theme.Colors.textSecondary)
                            }

                            Spacer()

                            if goalType == goal {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Theme.Colors.accent)
                            }
                        }
                        .padding(Theme.Spacing.md)
                        .background(goalType == goal ? Theme.Colors.accent.opacity(0.2) : Theme.Colors.surface)
                        .cornerRadius(Theme.Radius.medium)
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.lg)

            if goalType != .maintain {
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Text("Weekly Rate")
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.textPrimary)
                        Spacer()
                        Text(String(format: "%.1f lb/week", UnitConverter.kgToLb(goalRate)))
                            .font(Theme.Typography.headline)
                            .foregroundColor(Theme.Colors.accent)
                    }

                    Slider(value: goalRateLbs, in: 0.5...2.0, step: 0.5)
                        .tint(Theme.Colors.accent)

                    Text(goalType == .cut ? "1 lb/week is recommended for sustainable fat loss" : "0.5 lb/week is recommended for lean muscle gain")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
                .padding(.horizontal, Theme.Spacing.lg)
            }

            Spacer()
        }
        .padding(.top, Theme.Spacing.xl)
    }
}

// MARK: - Summary Step

struct SummaryStep: View {
    let name: String
    let sex: Sex?
    let height: Double
    let weight: Double
    let activity: ActivityLevel
    let goal: GoalType

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            VStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 60))
                    .foregroundColor(Theme.Colors.success)

                Text("You're all set, \(name)!")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("Here's your personalized profile")
                    .font(Theme.Typography.body)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            VStack(spacing: Theme.Spacing.sm) {
                SummaryRow(label: "Sex", value: sex?.displayName ?? "—")
                SummaryRow(label: "Height", value: UnitConverter.heightStringFromCm(height))
                SummaryRow(label: "Weight", value: String(format: "%.1f lb", UnitConverter.kgToLb(weight)))
                SummaryRow(label: "Activity", value: activity.displayName)
                SummaryRow(label: "Goal", value: goal.displayName)
            }
            .padding(Theme.Spacing.md)
            .cardStyle()
            .padding(.horizontal, Theme.Spacing.lg)

            Text("We'll calculate your personalized macro targets based on this information.")
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Theme.Spacing.lg)

            Spacer()
        }
        .padding(.top, Theme.Spacing.xl)
    }
}

struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Typography.body)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }
}

#Preview {
    OnboardingView()
        .environmentObject(AppState())
        .modelContainer(for: [UserProfile.self, MacroTargets.self])
}

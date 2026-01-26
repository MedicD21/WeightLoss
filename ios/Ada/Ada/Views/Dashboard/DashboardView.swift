import SwiftUI
import SwiftData

/// Main dashboard showing today's summary
struct DashboardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Query private var macroTargets: [MacroTargets]

    @StateObject private var viewModel = DashboardViewModel()

    var userProfile: UserProfile? { userProfiles.first }
    var targets: MacroTargets? { macroTargets.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Greeting
                    greetingSection

                    // Calories card
                    CaloriesCard(
                        consumed: viewModel.summary.caloriesConsumed,
                        target: targets?.calories,
                        remaining: viewModel.summary.caloriesRemaining
                    )

                    // Macros row
                    MacrosRow(
                        protein: viewModel.summary.proteinG,
                        proteinTarget: targets?.proteinG,
                        carbs: viewModel.summary.carbsG,
                        carbsTarget: targets?.carbsG,
                        fat: viewModel.summary.fatG,
                        fatTarget: targets?.fatG
                    )

                    // Activity cards
                    HStack(spacing: Theme.Spacing.md) {
                        ActivityCard(
                            title: "Steps",
                            value: viewModel.summary.steps.map { "\($0.formatted())" } ?? "—",
                            icon: "figure.walk",
                            progress: viewModel.summary.stepsProgress,
                            color: Theme.Colors.accent
                        )

                        ActivityCard(
                            title: "Water",
                            value: "\(viewModel.summary.waterMl) ml",
                            icon: "drop.fill",
                            progress: viewModel.summary.waterProgress,
                            color: Theme.Colors.info
                        )
                    }

                    // Workouts today
                    if viewModel.summary.workoutsCount > 0 {
                        WorkoutSummaryCard(
                            count: viewModel.summary.workoutsCount,
                            minutes: viewModel.summary.workoutMinutes,
                            calories: viewModel.summary.activeCalories
                        )
                    }

                    // Quick actions
                    QuickActionsSection()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Today")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        // Refresh
                        Task { await viewModel.refresh(modelContext: modelContext) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await viewModel.refresh(modelContext: modelContext)
        }
    }

    private var greetingSection: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(greeting)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)

                Text(userProfile?.displayName ?? "There")
                    .font(Theme.Typography.title2)
                    .foregroundColor(Theme.Colors.textPrimary)
            }
            Spacer()
        }
        .padding(.top, Theme.Spacing.sm)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        if hour < 12 {
            return "Good morning,"
        } else if hour < 17 {
            return "Good afternoon,"
        } else {
            return "Good evening,"
        }
    }
}

// MARK: - Calories Card

struct CaloriesCard: View {
    let consumed: Int
    let target: Int?
    let remaining: Int?

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("Calories")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
                if let target = target {
                    Text("Goal: \(target)")
                        .font(Theme.Typography.subheadline)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: Theme.Spacing.xs) {
                Text("\(consumed)")
                    .font(Theme.Typography.statLarge)
                    .foregroundColor(Theme.Colors.calories)

                Text("kcal")
                    .font(Theme.Typography.callout)
                    .foregroundColor(Theme.Colors.textSecondary)

                Spacer()

                if let remaining = remaining {
                    VStack(alignment: .trailing) {
                        Text(remaining >= 0 ? "remaining" : "over")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textTertiary)
                        Text("\(abs(remaining))")
                            .font(Theme.Typography.statSmall)
                            .foregroundColor(remaining >= 0 ? Theme.Colors.textPrimary : Theme.Colors.warning)
                    }
                }
            }

            if let target = target {
                ProgressBar(
                    progress: min(Double(consumed) / Double(target), 1.0),
                    color: Theme.Colors.calories
                )
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Macros Row

struct MacrosRow: View {
    let protein: Double
    let proteinTarget: Double?
    let carbs: Double
    let carbsTarget: Double?
    let fat: Double
    let fatTarget: Double?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            MacroCard(
                name: "Protein",
                value: protein,
                target: proteinTarget,
                color: Theme.Colors.protein
            )

            MacroCard(
                name: "Carbs",
                value: carbs,
                target: carbsTarget,
                color: Theme.Colors.carbs
            )

            MacroCard(
                name: "Fat",
                value: fat,
                target: fatTarget,
                color: Theme.Colors.fat
            )
        }
    }
}

struct MacroCard: View {
    let name: String
    let value: Double
    let target: Double?
    let color: Color

    var progress: Double {
        guard let target = target, target > 0 else { return 0 }
        return min(value / target, 1.0)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.sm) {
            Text(name)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            Text(String(format: "%.0fg", value))
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            CircularProgressView(progress: progress, color: color)
                .frame(width: 40, height: 40)

            if let target = target {
                Text(String(format: "%.0fg", target))
                    .font(Theme.Typography.caption2)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.sm)
        .cardStyle()
    }
}

// MARK: - Activity Card

struct ActivityCard: View {
    let title: String
    let value: String
    let icon: String
    let progress: Double
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(color)
                Text(title)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Text(value)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            ProgressBar(progress: progress, color: color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Workout Summary Card

struct WorkoutSummaryCard: View {
    let count: Int
    let minutes: Int
    let calories: Int?

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Image(systemName: "flame.fill")
                .font(.system(size: 32))
                .foregroundColor(Theme.Colors.warning)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text("\(count) workout\(count == 1 ? "" : "s") today")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text("\(minutes) minutes")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            if let calories = calories {
                VStack(alignment: .trailing) {
                    Text("\(calories)")
                        .font(Theme.Typography.title3)
                        .foregroundColor(Theme.Colors.warning)
                    Text("kcal burned")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textTertiary)
                }
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Quick Actions

struct QuickActionsSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Quick Add")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.md) {
                QuickActionButton(icon: "plus.circle.fill", title: "Meal", color: Theme.Colors.calories)
                QuickActionButton(icon: "drop.fill", title: "Water", color: Theme.Colors.info)
                QuickActionButton(icon: "scalemass.fill", title: "Weight", color: Theme.Colors.accent)
                QuickActionButton(icon: "figure.run", title: "Workout", color: Theme.Colors.warning)
            }
        }
    }
}

struct QuickActionButton: View {
    let icon: String
    let title: String
    let color: Color

    var body: some View {
        Button {
            // Action
        } label: {
            VStack(spacing: Theme.Spacing.xs) {
                Image(systemName: icon)
                    .font(.system(size: 24))
                    .foregroundColor(color)

                Text(title)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, Theme.Spacing.md)
            .cardStyle()
        }
    }
}

// MARK: - Progress Components

struct ProgressBar: View {
    let progress: Double
    let color: Color

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Theme.Colors.surfaceHighlight)

                RoundedRectangle(cornerRadius: 4)
                    .fill(color)
                    .frame(width: geometry.size.width * progress)
            }
        }
        .frame(height: 8)
    }
}

struct CircularProgressView: View {
    let progress: Double
    let color: Color
    let lineWidth: CGFloat = 4

    var body: some View {
        ZStack {
            Circle()
                .stroke(Theme.Colors.surfaceHighlight, lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))

            Text(String(format: "%.0f%%", progress * 100))
                .font(Theme.Typography.caption2)
                .foregroundColor(Theme.Colors.textSecondary)
        }
    }
}

#Preview {
    DashboardView()
        .environmentObject(AppState())
        .modelContainer(for: [UserProfile.self, MacroTargets.self])
}

import SwiftUI
import SwiftData

/// Workout planning and logging view
struct WorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutLog.startTime, order: .reverse) private var recentLogs: [WorkoutLog]
    @Query(filter: #Predicate<WorkoutPlan> { $0.isActive }, sort: \WorkoutPlan.orderIndex) private var plans: [WorkoutPlan]

    @State private var showingAddWorkout = false
    @State private var showingCreatePlan = false
    @State private var selectedSegment = 0

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Segmented control
                Picker("View", selection: $selectedSegment) {
                    Text("Log").tag(0)
                    Text("Plans").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)

                ScrollView {
                    if selectedSegment == 0 {
                        WorkoutLogSection(logs: recentLogs)
                    } else {
                        WorkoutPlansSection(plans: plans)
                    }
                }
            }
            .background(Theme.Colors.background)
            .navigationTitle("Workout")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if selectedSegment == 0 {
                            showingAddWorkout = true
                        } else {
                            showingCreatePlan = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingAddWorkout) {
                AddWorkoutView()
            }
            .sheet(isPresented: $showingCreatePlan) {
                CreatePlanView()
            }
        }
    }
}

// MARK: - Workout Log Section

struct WorkoutLogSection: View {
    let logs: [WorkoutLog]

    var thisWeekLogs: [WorkoutLog] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return logs.filter { $0.startTime >= weekAgo }
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            // Weekly summary
            WeeklyWorkoutSummary(logs: thisWeekLogs)

            // Recent workouts
            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                Text("Recent Workouts")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                if logs.isEmpty {
                    EmptyWorkoutsView()
                } else {
                    ForEach(logs.prefix(10)) { log in
                        WorkoutLogCard(log: log)
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xl)
    }
}

struct WeeklyWorkoutSummary: View {
    let logs: [WorkoutLog]

    var totalMinutes: Int {
        logs.reduce(0) { $0 + $1.durationMin }
    }

    var totalCalories: Int {
        logs.compactMap { $0.caloriesBurned }.reduce(0, +)
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            HStack {
                Text("This Week")
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)
                Spacer()
            }

            HStack(spacing: Theme.Spacing.lg) {
                StatItem(value: "\(logs.count)", label: "Workouts", icon: "figure.run")
                StatItem(value: "\(totalMinutes)", label: "Minutes", icon: "clock.fill")
                StatItem(value: "\(totalCalories)", label: "Calories", icon: "flame.fill")
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct StatItem: View {
    let value: String
    let label: String
    let icon: String

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(Theme.Colors.accent)

            Text(value)
                .font(Theme.Typography.title3)
                .foregroundColor(Theme.Colors.textPrimary)

            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }
}

struct WorkoutLogCard: View {
    let log: WorkoutLog

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            Image(systemName: log.workoutType.icon)
                .font(.system(size: 24))
                .foregroundColor(Theme.Colors.accent)
                .frame(width: 44, height: 44)
                .background(Theme.Colors.surfaceHighlight)
                .cornerRadius(Theme.Radius.medium)

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(log.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                HStack(spacing: Theme.Spacing.sm) {
                    Label(log.durationDisplay, systemImage: "clock")
                    if let calories = log.caloriesBurned {
                        Label("\(calories) kcal", systemImage: "flame.fill")
                    }
                }
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Theme.Spacing.xxs) {
                Text(log.startTime.formatted(date: .abbreviated, time: .omitted))
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)

                Text(log.startTime.formatted(date: .omitted, time: .shortened))
                    .font(Theme.Typography.caption2)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct EmptyWorkoutsView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "figure.run")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No workouts yet")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textSecondary)

            Text("Log your first workout to start tracking")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }
}

// MARK: - Workout Plans Section

struct WorkoutPlansSection: View {
    let plans: [WorkoutPlan]

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            if plans.isEmpty {
                EmptyPlansView()
            } else {
                ForEach(plans) { plan in
                    WorkoutPlanCard(plan: plan)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xl)
    }
}

struct WorkoutPlanCard: View {
    let plan: WorkoutPlan

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            HStack {
                Image(systemName: plan.workoutType.icon)
                    .foregroundColor(Theme.Colors.accent)

                Text(plan.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(Theme.Colors.textPrimary)

                Spacer()

                if let duration = plan.estimatedDurationMin {
                    Text("\(duration) min")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.textSecondary)
                }
            }

            if let description = plan.planDescription {
                Text(description)
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }

            HStack {
                Text("\(plan.exercises.count) exercises")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)

                Spacer()

                Text(plan.scheduledDaysDisplay)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct EmptyPlansView: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "doc.text")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No workout plans")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textSecondary)

            Text("Create a plan to organize your workouts")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Theme.Spacing.xxl)
    }
}

// MARK: - Placeholder Views

struct AddWorkoutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Add Workout View")
                .navigationTitle("Log Workout")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

struct CreatePlanView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Create Plan View")
                .navigationTitle("New Plan")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    WorkoutView()
        .environmentObject(AppState())
        .modelContainer(for: [WorkoutLog.self, WorkoutPlan.self])
}

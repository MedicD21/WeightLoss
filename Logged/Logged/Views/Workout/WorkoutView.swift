import SwiftUI
import SwiftData
import HealthKit

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
            .background(Color.clear)
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
    @Environment(\.modelContext) private var modelContext
    let logs: [WorkoutLog]
    @State private var logsToDisplay: [WorkoutLog] = []

    var thisWeekLogs: [WorkoutLog] {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date())!
        return logsToDisplay.filter { $0.startTime >= weekAgo }
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

                if logsToDisplay.isEmpty {
                    EmptyWorkoutsView()
                } else {
                    ForEach(logsToDisplay.prefix(10)) { log in
                        WorkoutLogCard(log: log) {
                            refreshLogs()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.bottom, Theme.Spacing.xl)
        .onAppear {
            logsToDisplay = logs
        }
        .onChange(of: logs) { _, newLogs in
            logsToDisplay = newLogs
        }
    }

    private func refreshLogs() {
        logsToDisplay = logs
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
    @Environment(\.modelContext) private var modelContext
    let log: WorkoutLog
    let onDelete: (() -> Void)?

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
                        Label("\(calories) cal", systemImage: "flame.fill")
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
        .contextMenu {
            Button(role: .destructive) {
                deleteWorkout()
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private func deleteWorkout() {
        Task {
            do {
                try await APIService.shared.deleteWorkoutLog(id: log.id)
                modelContext.delete(log)
                try? modelContext.save()
                onDelete?()
            } catch {
                print("Failed to delete workout: \(error)")
            }
        }
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
                    NavigationLink(destination: WorkoutPlanDetailView(plan: plan)) {
                        WorkoutPlanCard(plan: plan)
                    }
                    .buttonStyle(PlainButtonStyle())
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

// MARK: - Add Workout

struct AddWorkoutView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Environment(\.dismiss) private var dismiss

    var onSaved: (() -> Void)? = nil

    @State private var workoutName = ""
    @State private var workoutType: WorkoutType = .strength
    @State private var durationText = ""
    @State private var caloriesText = ""
    @State private var saveToHealthKit = true
    @State private var errorMessage: String?
    @State private var isSaving = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Workout") {
                    TextField("Workout name", text: $workoutName)

                    Picker("Type", selection: $workoutType) {
                        ForEach(WorkoutType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section("Duration") {
                    HStack {
                        TextField("Minutes", text: $durationText)
                            .keyboardType(.numberPad)
                        Text("min")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Section("Calories (optional)") {
                    HStack {
                        TextField("Calories", text: $caloriesText)
                            .keyboardType(.numberPad)
                        Text("cal")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                Section("HealthKit") {
                    Toggle("Save to Health", isOn: $saveToHealthKit)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
            }
            .navigationTitle("Log Workout")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        Task { await saveWorkout() }
                    }
                    .disabled(isSaving || durationText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveWorkout() async {
        guard let duration = Int(durationText), duration > 0 else {
            errorMessage = "Enter a valid duration."
            return
        }

        isSaving = true
        defer { isSaving = false }

        let profile = getOrCreateProfile()
        let name = workoutName.trimmingCharacters(in: .whitespacesAndNewlines)
        let startTime = Date()
        let endTime = Calendar.current.date(byAdding: .minute, value: duration, to: startTime)
        let calories = Int(caloriesText)

        let log = WorkoutLog(
            userId: profile.id,
            name: name.isEmpty ? workoutType.displayName : name,
            workoutType: workoutType,
            durationMin: duration,
            caloriesBurned: calories
        )
        log.startTime = startTime
        log.endTime = endTime

        modelContext.insert(log)

        if saveToHealthKit {
            do {
                try await HealthKitService.shared.requestAuthorization()
                let hkType = healthKitActivityType(for: workoutType)
                try await HealthKitService.shared.saveWorkout(
                    type: hkType,
                    startDate: startTime,
                    endDate: endTime ?? startTime,
                    calories: calories.map { Double($0) },
                    distance: nil
                )
            } catch {
                errorMessage = "Saved locally, but HealthKit failed: \(error.localizedDescription)"
            }
        }

        onSaved?()
        dismiss()
    }

    private func healthKitActivityType(for workoutType: WorkoutType) -> HKWorkoutActivityType {
        switch workoutType {
        case .strength:
            return .traditionalStrengthTraining
        case .cardio:
            return .mixedCardio
        case .hiit:
            return .highIntensityIntervalTraining
        case .flexibility:
            return .flexibility
        case .walking:
            return .walking
        case .running:
            return .running
        case .cycling:
            return .cycling
        case .swimming:
            return .swimming
        case .sports:
            return .other
        case .other:
            return .other
        }
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

struct CreatePlanView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var planDescription = ""
    @State private var workoutType: WorkoutType = .strength
    @State private var estimatedDurationText = ""
    @State private var scheduledDays: Set<Int> = []
    @State private var errorMessage: String?

    private let dayNames = ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"]

    var body: some View {
        NavigationStack {
            Form {
                Section("Plan") {
                    TextField("Name", text: $name)
                    TextField("Description (optional)", text: $planDescription)
                    Picker("Type", selection: $workoutType) {
                        ForEach(WorkoutType.allCases, id: \.self) { type in
                            Text(type.displayName).tag(type)
                        }
                    }
                }

                Section("Schedule") {
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text("Days")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)
                        HStack {
                            ForEach(dayNames.indices, id: \.self) { index in
                                Button {
                                    toggleDay(index)
                                } label: {
                                    Text(dayNames[index])
                                        .font(Theme.Typography.caption)
                                        .foregroundColor(scheduledDays.contains(index) ? .white : Theme.Colors.textSecondary)
                                        .padding(.horizontal, Theme.Spacing.sm)
                                        .padding(.vertical, Theme.Spacing.xs)
                                        .background(scheduledDays.contains(index) ? Theme.Colors.accent : Theme.Colors.surface)
                                        .cornerRadius(Theme.Radius.full)
                                }
                            }
                        }
                    }

                    HStack {
                        TextField("Estimated minutes", text: $estimatedDurationText)
                            .keyboardType(.numberPad)
                        Text("min")
                            .foregroundColor(Theme.Colors.textSecondary)
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.error)
                }
            }
            .navigationTitle("New Plan")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") { savePlan() }
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func toggleDay(_ index: Int) {
        if scheduledDays.contains(index) {
            scheduledDays.remove(index)
        } else {
            scheduledDays.insert(index)
        }
    }

    private func savePlan() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            errorMessage = "Name is required."
            return
        }

        let profile = getOrCreateProfile()
        let duration = Int(estimatedDurationText)
        let days = scheduledDays.isEmpty ? nil : scheduledDays.sorted()

        let plan = WorkoutPlan(
            userId: profile.id,
            name: trimmedName,
            planDescription: planDescription.isEmpty ? nil : planDescription,
            workoutType: workoutType,
            scheduledDays: days,
            estimatedDurationMin: duration
        )

        modelContext.insert(plan)
        dismiss()
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

// MARK: - Workout Plan Detail

struct WorkoutPlanDetailView: View {
    let plan: WorkoutPlan
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Environment(\.dismiss) private var dismiss

    @State private var completedExercises: Set<UUID> = []
    @State private var startTime: Date = Date()
    @State private var isSaving = false
    @State private var showingCompleteConfirmation = false

    var sortedExercises: [WorkoutExercise] {
        plan.exercises.sorted(by: { $0.orderIndex < $1.orderIndex })
    }

    var allCompleted: Bool {
        !sortedExercises.isEmpty && sortedExercises.allSatisfy { completedExercises.contains($0.id) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                // Header
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    HStack {
                        Image(systemName: plan.workoutType.icon)
                            .foregroundColor(Theme.Colors.accent)

                        Text(plan.name)
                            .font(Theme.Typography.title2)
                            .foregroundColor(Theme.Colors.textPrimary)
                    }

                    if let description = plan.planDescription {
                        Text(description)
                            .font(Theme.Typography.body)
                            .foregroundColor(Theme.Colors.textSecondary)
                    }

                    HStack(spacing: Theme.Spacing.md) {
                        if let duration = plan.estimatedDurationMin {
                            Label("\(duration) min", systemImage: "clock")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }

                        Label("\(plan.exercises.count) exercises", systemImage: "list.bullet")
                            .font(Theme.Typography.caption)
                            .foregroundColor(Theme.Colors.textSecondary)

                        if !plan.scheduledDaysDisplay.isEmpty {
                            Label(plan.scheduledDaysDisplay, systemImage: "calendar")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.textSecondary)
                        }
                    }

                    // Progress indicator
                    if !completedExercises.isEmpty {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(Theme.Colors.success)
                            Text("\(completedExercises.count)/\(plan.exercises.count) completed")
                                .font(Theme.Typography.caption)
                                .foregroundColor(Theme.Colors.success)
                        }
                        .padding(.top, Theme.Spacing.xs)
                    }
                }
                .padding(Theme.Spacing.md)
                .cardStyle()

                // Exercises List
                VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                    Text("Exercises")
                        .font(Theme.Typography.headline)
                        .foregroundColor(Theme.Colors.textPrimary)
                        .padding(.horizontal, Theme.Spacing.md)

                    ForEach(sortedExercises) { exercise in
                        ExerciseCard(
                            exercise: exercise,
                            isCompleted: completedExercises.contains(exercise.id)
                        ) {
                            toggleExerciseCompletion(exercise)
                        }
                    }
                }

                // Complete Workout Button
                if !completedExercises.isEmpty {
                    Button {
                        showingCompleteConfirmation = true
                    } label: {
                        HStack {
                            Image(systemName: allCompleted ? "checkmark.circle.fill" : "flag.checkered")
                            Text(allCompleted ? "Complete Workout" : "Finish Early (\(completedExercises.count)/\(plan.exercises.count))")
                        }
                    }
                    .buttonStyle(.primary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .disabled(isSaving)
                }
            }
            .padding(Theme.Spacing.md)
        }
        .background(Theme.Colors.background)
        .navigationBarTitleDisplayMode(.inline)
        .alert("Complete Workout?", isPresented: $showingCompleteConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Complete") {
                Task { await completeWorkout() }
            }
        } message: {
            Text("Log this workout with \(completedExercises.count) completed exercises?")
        }
    }

    private func toggleExerciseCompletion(_ exercise: WorkoutExercise) {
        if completedExercises.contains(exercise.id) {
            completedExercises.remove(exercise.id)
        } else {
            completedExercises.insert(exercise.id)
        }
    }

    private func completeWorkout() async {
        guard !completedExercises.isEmpty else { return }

        isSaving = true
        defer { isSaving = false }

        let profile = getOrCreateProfile()
        let endTime = Date()
        let durationMin = max(1, Int(endTime.timeIntervalSince(startTime) / 60))

        // Create workout log
        let log = WorkoutLog(
            userId: profile.id,
            planId: plan.id,
            name: plan.name,
            workoutType: plan.workoutType,
            source: .manual,
            startTime: startTime,
            durationMin: durationMin
        )
        log.endTime = endTime

        modelContext.insert(log)

        // Create set logs for completed exercises
        var orderIndex = 0
        for exercise in sortedExercises where completedExercises.contains(exercise.id) {
            // Create a set log for each set in the exercise
            for setNum in 1...exercise.sets {
                let setLog = WorkoutSetLog(
                    exerciseName: exercise.name,
                    setNumber: setNum,
                    reps: exercise.repsMin,
                    durationSec: exercise.durationSec,
                    completed: true,
                    orderIndex: orderIndex
                )
                setLog.log = log
                modelContext.insert(setLog)
                orderIndex += 1
            }
        }

        // Save to backend
        do {
            try await APIService.shared.createWorkoutLog(log: log)
            try? modelContext.save()
            dismiss()
        } catch {
            print("Failed to save workout: \(error)")
        }
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

struct ExerciseCard: View {
    let exercise: WorkoutExercise
    var isCompleted: Bool = false
    var onToggle: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            HStack {
                // Completion checkbox
                if let toggle = onToggle {
                    Button {
                        toggle()
                    } label: {
                        Image(systemName: isCompleted ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 24))
                            .foregroundColor(isCompleted ? Theme.Colors.success : Theme.Colors.textTertiary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }

                Text("\(exercise.orderIndex).")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .frame(width: 24, alignment: .leading)

                Text(exercise.name)
                    .font(Theme.Typography.headline)
                    .foregroundColor(isCompleted ? Theme.Colors.textSecondary : Theme.Colors.textPrimary)
                    .strikethrough(isCompleted)

                Spacer()

                if let muscleGroup = exercise.muscleGroup {
                    Text(muscleGroup.rawValue.capitalized)
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.accent)
                        .padding(.horizontal, Theme.Spacing.xs)
                        .padding(.vertical, 2)
                        .background(Theme.Colors.accent.opacity(0.15))
                        .cornerRadius(Theme.Radius.small)
                }
            }

            HStack(spacing: Theme.Spacing.md) {
                if let repsMin = exercise.repsMin {
                    if let repsMax = exercise.repsMax, repsMax != repsMin {
                        Text("\(exercise.sets) × \(repsMin)-\(repsMax) reps")
                    } else {
                        Text("\(exercise.sets) × \(repsMin) reps")
                    }
                } else if let duration = exercise.durationSec {
                    Text("\(exercise.sets) × \(duration)s")
                }

                if exercise.restSec > 0 {
                    Text("•")
                    Text("\(exercise.restSec)s rest")
                }
            }
            .font(Theme.Typography.caption)
            .foregroundColor(Theme.Colors.textSecondary)
            .padding(.leading, 32)

            if let equipment = exercise.equipment {
                Text("Equipment: \(equipment)")
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
                    .padding(.leading, 32)
            }

            if let notes = exercise.notes {
                Text(notes)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textSecondary)
                    .italic()
                    .padding(.leading, 32)
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

#Preview {
    WorkoutView()
        .environmentObject(AppState())
        .modelContainer(for: [WorkoutLog.self, WorkoutPlan.self])
}

import SwiftUI

struct WorkoutLogView: View {
    @StateObject private var viewModel = WorkoutLogViewModel()
    @State private var workoutType: WatchWorkoutType = .walking
    @State private var durationMin: Int = 20

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text("Workout")
                    .font(.headline)

                Picker("Type", selection: $workoutType) {
                    ForEach(WatchWorkoutType.allCases) { type in
                        Text(type.label).tag(type)
                    }
                }

                Stepper(value: $durationMin, in: 5...180, step: 5) {
                    Text("Duration: \(durationMin) min")
                }

                Button("Log Workout") {
                    Task { await viewModel.logWorkout(type: workoutType, durationMin: durationMin) }
                }

                if let message = viewModel.message {
                    Text(message)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}

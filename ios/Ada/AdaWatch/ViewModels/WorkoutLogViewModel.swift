import Foundation

@MainActor
final class WorkoutLogViewModel: ObservableObject {
    @Published var isLogging = false
    @Published var message: String? = nil

    func logWorkout(type: WatchWorkoutType, durationMin: Int) async {
        isLogging = true
        message = nil

        let payload = WatchWorkoutLogRequest(
            name: type.label,
            workoutType: type.rawValue,
            startTime: ISO8601DateFormatter().string(from: Date()),
            durationMin: durationMin
        )

        do {
            let _: EmptyResponse = try await WatchAPIService.shared.request(
                endpoint: "workouts/logs",
                method: "POST",
                body: payload,
                requiresAuth: true
            )
            message = "Workout logged"
        } catch {
            message = error.localizedDescription
        }

        isLogging = false
    }
}

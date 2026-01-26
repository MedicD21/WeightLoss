import SwiftUI
import SwiftData

/// Main entry point for the Logged Fitness Tracker app
@main
struct LoggedApp: App {
    @StateObject private var appState = AppState()

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            MacroTargets.self,
            Meal.self,
            FoodItem.self,
            SavedFood.self,
            WorkoutPlan.self,
            WorkoutExercise.self,
            WorkoutLog.self,
            WorkoutSetLog.self,
            BodyWeightEntry.self,
            WaterEntry.self,
            StepsDaily.self,
            ChatMessage.self,
        ])
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .none // Offline-first, sync manually
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .modelContainer(sharedModelContainer)
                .preferredColorScheme(.dark)
        }
    }
}

/// Global app state
@MainActor
class AppState: ObservableObject {
    @Published var isAuthenticated = false
    @Published var isOnboarded = false
    @Published var selectedTab: Tab = .dashboard
    @Published var showingChat = false

    enum Tab: String, CaseIterable {
        case dashboard = "Dashboard"
        case food = "Food"
        case workout = "Workout"
        case progress = "Progress"
        case profile = "Profile"

        var icon: String {
            switch self {
            case .dashboard: return "house.fill"
            case .food: return "fork.knife"
            case .workout: return "figure.run"
            case .progress: return "chart.line.uptrend.xyaxis"
            case .profile: return "person.fill"
            }
        }
    }

    init() {
        // Check for existing auth token
        if let _ = KeychainService.shared.getToken() {
            isAuthenticated = true
        }

        // Check if user has completed onboarding
        isOnboarded = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")

        #if canImport(WatchConnectivity)
        WatchConnectivityService.shared.activate()
        #endif
    }

    func signIn(token: String, refreshToken: String) {
        KeychainService.shared.saveToken(token)
        KeychainService.shared.saveRefreshToken(refreshToken)
        isAuthenticated = true
    }

    func signOut() {
        KeychainService.shared.deleteToken()
        KeychainService.shared.deleteRefreshToken()
        isAuthenticated = false
    }

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        isOnboarded = true
    }
}

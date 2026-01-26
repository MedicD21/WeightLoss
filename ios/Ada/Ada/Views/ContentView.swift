import SwiftUI
import SwiftData

/// Root content view that handles navigation
struct ContentView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        ZStack {
            Theme.Colors.background
                .ignoresSafeArea()

            if appState.isAuthenticated {
                if appState.isOnboarded {
                    MainTabView()
                } else {
                    OnboardingView()
                }
            } else {
                AuthView()
            }

            // Floating chat button
            if appState.isAuthenticated && appState.isOnboarded && !appState.showingChat {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FloatingChatButton()
                    }
                    .padding(.trailing, Theme.Spacing.lg)
                    .padding(.bottom, 90) // Above tab bar
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// Main tab view for authenticated users
struct MainTabView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            DashboardView()
                .tabItem {
                    Label(AppState.Tab.dashboard.rawValue, systemImage: AppState.Tab.dashboard.icon)
                }
                .tag(AppState.Tab.dashboard)

            FoodView()
                .tabItem {
                    Label(AppState.Tab.food.rawValue, systemImage: AppState.Tab.food.icon)
                }
                .tag(AppState.Tab.food)

            WorkoutView()
                .tabItem {
                    Label(AppState.Tab.workout.rawValue, systemImage: AppState.Tab.workout.icon)
                }
                .tag(AppState.Tab.workout)

            ProgressView()
                .tabItem {
                    Label(AppState.Tab.progress.rawValue, systemImage: AppState.Tab.progress.icon)
                }
                .tag(AppState.Tab.progress)

            ProfileView()
                .tabItem {
                    Label(AppState.Tab.profile.rawValue, systemImage: AppState.Tab.profile.icon)
                }
                .tag(AppState.Tab.profile)
        }
        .tint(Theme.Colors.accent)
        .sheet(isPresented: $appState.showingChat) {
            ChatView()
        }
    }
}

/// Floating button to open Ada chat
struct FloatingChatButton: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            appState.showingChat = true
        } label: {
            HStack(spacing: Theme.Spacing.xs) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 18, weight: .semibold))
                Text("Ada")
                    .font(Theme.Typography.headline)
            }
            .foregroundColor(.white)
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.vertical, Theme.Spacing.sm)
            .background(
                Capsule()
                    .fill(Theme.Colors.accent)
                    .shadow(color: Theme.Colors.accent.opacity(0.4), radius: 8, x: 0, y: 4)
            )
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .modelContainer(for: [UserProfile.self])
}

import SwiftUI
import SwiftData

/// Root content view that handles navigation
struct ContentView: View {
    @EnvironmentObject private var appState: AppState

    private var shouldShowChatButton: Bool {
        appState.isAuthenticated && appState.isOnboarded && !appState.showingChat
    }

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

            // Floating chat handle
            if shouldShowChatButton {
                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        FloatingChatHandle()
                    }
                    .padding(.trailing, -Theme.Spacing.xs)
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

/// Floating handle that opens Terry chat on swipe
struct FloatingChatHandle: View {
    @EnvironmentObject private var appState: AppState
    @GestureState private var dragOffset: CGSize = .zero

    private let swipeThreshold: CGFloat = 40

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            Image(systemName: "chevron.left")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Theme.Colors.textSecondary)

            Image("ChatBot")
                .resizable()
                .scaledToFill()
                .frame(width: 26, height: 26)
                .clipShape(Circle())
                .overlay(
                    Circle().stroke(Theme.Colors.border, lineWidth: 1)
                )
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(
            Capsule()
                .fill(Theme.Colors.surfaceElevated)
                .overlay(
                    Capsule()
                        .stroke(Theme.Colors.border, lineWidth: 1)
                )
                .shadow(color: Theme.Shadows.small, radius: 6, x: 0, y: 3)
        )
        .offset(x: min(0, dragOffset.width))
        .offset(x: 14)
        .gesture(
            DragGesture(minimumDistance: 10)
                .updating($dragOffset) { value, state, _ in
                    if value.translation.width < 0 {
                        state = value.translation
                    }
                }
                .onEnded { value in
                    if value.translation.width < -swipeThreshold {
                        appState.showingChat = true
                    }
                }
        )
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
        .modelContainer(for: [UserProfile.self])
}

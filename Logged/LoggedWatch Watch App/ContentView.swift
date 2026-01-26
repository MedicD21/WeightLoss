import SwiftUI

struct ContentView: View {
    @StateObject private var sessionManager = WatchSessionManager.shared

    var body: some View {
        Group {
            if sessionManager.isAuthenticated {
                TabView {
                    SummaryView()
                    QuickLogView()
                    WorkoutLogView()
                }
                .tabViewStyle(.page)
            } else {
                AuthRequiredView()
            }
        }
        .onAppear {
            sessionManager.requestTokens()
        }
    }
}

struct AuthRequiredView: View {
    @StateObject private var sessionManager = WatchSessionManager.shared

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "iphone")
            Text("Open Logged on iPhone to sign in")
                .font(.footnote)
                .multilineTextAlignment(.center)
            if let error = sessionManager.lastError {
                Text(error)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }
        }
        .padding()
    }
}

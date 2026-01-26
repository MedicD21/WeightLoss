import SwiftUI
import SwiftData

/// User profile and settings view
struct ProfileView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.modelContext) private var modelContext
    @Query private var userProfiles: [UserProfile]
    @Query private var macroTargets: [MacroTargets]

    @State private var showingEditProfile = false
    @State private var showingGoalsSheet = false
    @State private var showingHealthKitSettings = false

    var userProfile: UserProfile? { userProfiles.first }
    var targets: MacroTargets? { macroTargets.first }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Profile header
                    ProfileHeaderSection(profile: userProfile)

                    // Current targets
                    if let targets = targets {
                        CurrentTargetsSection(targets: targets)
                    }

                    // Body metrics
                    BodyMetricsSection(profile: userProfile)

                    // Goals
                    GoalsSection(profile: userProfile)

                    // Settings
                    SettingsSection()

                    // Sign out
                    SignOutButton()
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditProfile = true
                    } label: {
                        Text("Edit")
                    }
                }
            }
            .sheet(isPresented: $showingEditProfile) {
                EditProfileView()
            }
            .sheet(isPresented: $showingGoalsSheet) {
                EditGoalsView()
            }
        }
    }
}

// MARK: - Profile Header

struct ProfileHeaderSection: View {
    let profile: UserProfile?

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            // Avatar
            Circle()
                .fill(Theme.Colors.accent)
                .frame(width: 64, height: 64)
                .overlay(
                    Text(profile?.displayName?.prefix(1).uppercased() ?? "?")
                        .font(Theme.Typography.title2)
                        .foregroundColor(.white)
                )

            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                Text(profile?.displayName ?? "User")
                    .font(Theme.Typography.title3)
                    .foregroundColor(Theme.Colors.textPrimary)

                Text(profile?.email ?? "")
                    .font(Theme.Typography.subheadline)
                    .foregroundColor(Theme.Colors.textSecondary)

                if let profile = profile, !profile.isProfileComplete {
                    Text("Complete your profile to get personalized targets")
                        .font(Theme.Typography.caption)
                        .foregroundColor(Theme.Colors.warning)
                }
            }

            Spacer()
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Current Targets

struct CurrentTargetsSection: View {
    let targets: MacroTargets

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Daily Targets")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            HStack(spacing: Theme.Spacing.md) {
                TargetCard(label: "Calories", value: "\(targets.calories)", unit: "kcal", color: Theme.Colors.calories)
                TargetCard(label: "Protein", value: String(format: "%.0f", targets.proteinG), unit: "g", color: Theme.Colors.protein)
            }

            HStack(spacing: Theme.Spacing.md) {
                TargetCard(label: "Carbs", value: String(format: "%.0f", targets.carbsG), unit: "g", color: Theme.Colors.carbs)
                TargetCard(label: "Fat", value: String(format: "%.0f", targets.fatG), unit: "g", color: Theme.Colors.fat)
            }

            if let bmr = targets.bmr, let tdee = targets.tdee {
                HStack {
                    Text("BMR: \(bmr) kcal")
                    Spacer()
                    Text("TDEE: \(tdee) kcal")
                }
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct TargetCard: View {
    let label: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
            Text(label)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            HStack(alignment: .lastTextBaseline, spacing: 2) {
                Text(value)
                    .font(Theme.Typography.title3)
                    .foregroundColor(color)
                Text(unit)
                    .font(Theme.Typography.caption)
                    .foregroundColor(Theme.Colors.textTertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.sm)
        .background(Theme.Colors.surfaceHighlight)
        .cornerRadius(Theme.Radius.small)
    }
}

// MARK: - Body Metrics

struct BodyMetricsSection: View {
    let profile: UserProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Body Metrics")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                MetricRow(label: "Height", value: profile?.heightDisplay ?? "Not set")
                MetricRow(label: "Weight", value: profile?.weightDisplay ?? "Not set")
                MetricRow(label: "Age", value: profile?.age.map { "\($0) years" } ?? "Not set")
                MetricRow(label: "Sex", value: profile?.sex?.displayName ?? "Not set")
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct MetricRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
            Spacer()
            Text(value)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textPrimary)
        }
    }
}

// MARK: - Goals Section

struct GoalsSection: View {
    let profile: UserProfile?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Goals")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: Theme.Spacing.sm) {
                MetricRow(label: "Goal", value: profile?.goalType.displayName ?? "Not set")
                MetricRow(label: "Activity Level", value: profile?.activityLevel.displayName ?? "Moderate")
                if let target = profile?.targetWeightKg {
                    MetricRow(label: "Target Weight", value: String(format: "%.1f kg", target))
                }
                if let rate = profile?.goalRateKgPerWeek, rate > 0 {
                    MetricRow(label: "Weekly Rate", value: String(format: "%.2f kg/week", rate))
                }
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

// MARK: - Settings Section

struct SettingsSection: View {
    @StateObject private var healthKit = HealthKitService.shared

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.md) {
            Text("Settings")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.textPrimary)

            VStack(spacing: 0) {
                SettingsRow(icon: "heart.fill", title: "HealthKit", value: healthKit.isAuthorized ? "Connected" : "Not connected")
                Divider().background(Theme.Colors.border)
                SettingsRow(icon: "bell.fill", title: "Notifications", value: "On")
                Divider().background(Theme.Colors.border)
                SettingsRow(icon: "ruler", title: "Units", value: "Metric")
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct SettingsRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(Theme.Colors.accent)
                .frame(width: 24)

            Text(title)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textPrimary)

            Spacer()

            Text(value)
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)

            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .padding(.vertical, Theme.Spacing.sm)
    }
}

// MARK: - Sign Out

struct SignOutButton: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Button {
            appState.signOut()
        } label: {
            Text("Sign Out")
                .font(Theme.Typography.headline)
                .foregroundColor(Theme.Colors.error)
                .frame(maxWidth: .infinity)
                .padding(Theme.Spacing.md)
                .cardStyle()
        }
    }
}

// MARK: - Placeholder Views

struct EditProfileView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Edit Profile")
                .navigationTitle("Edit Profile")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { dismiss() }
                    }
                }
        }
    }
}

struct EditGoalsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Text("Edit Goals")
                .navigationTitle("Goals")
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Save") { dismiss() }
                    }
                }
        }
    }
}

#Preview {
    ProfileView()
        .environmentObject(AppState())
        .modelContainer(for: [UserProfile.self, MacroTargets.self])
}

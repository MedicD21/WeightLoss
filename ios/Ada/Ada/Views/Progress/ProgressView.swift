import SwiftUI
import SwiftData
import Charts

/// Progress tracking view with charts
struct ProgressView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyWeightEntry.timestamp) private var weightEntries: [BodyWeightEntry]

    @State private var selectedMetric: Metric = .weight
    @State private var selectedPeriod: Period = .month

    enum Metric: String, CaseIterable {
        case weight = "Weight"
        case calories = "Calories"
        case protein = "Protein"
        case steps = "Steps"
        case water = "Water"
    }

    enum Period: String, CaseIterable {
        case week = "7D"
        case month = "30D"
        case quarter = "90D"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Spacing.lg) {
                    // Metric selector
                    MetricSelector(selected: $selectedMetric)

                    // Period selector
                    PeriodSelector(selected: $selectedPeriod)

                    // Chart
                    ChartSection(
                        metric: selectedMetric,
                        period: selectedPeriod,
                        weightEntries: filteredWeightEntries
                    )

                    // Summary stats
                    ProgressStatsSection(
                        metric: selectedMetric,
                        weightEntries: filteredWeightEntries
                    )
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.bottom, Theme.Spacing.xl)
            }
            .background(Theme.Colors.background)
            .navigationTitle("Progress")
        }
    }

    private var filteredWeightEntries: [BodyWeightEntry] {
        let days: Int
        switch selectedPeriod {
        case .week: days = 7
        case .month: days = 30
        case .quarter: days = 90
        }

        let startDate = Calendar.current.date(byAdding: .day, value: -days, to: Date())!
        return weightEntries.filter { $0.timestamp >= startDate }
    }
}

// MARK: - Metric Selector

struct MetricSelector: View {
    @Binding var selected: ProgressView.Metric

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Theme.Spacing.sm) {
                ForEach(ProgressView.Metric.allCases, id: \.self) { metric in
                    MetricButton(
                        title: metric.rawValue,
                        isSelected: selected == metric
                    ) {
                        selected = metric
                    }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
        }
    }
}

struct MetricButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Typography.subheadline)
                .foregroundColor(isSelected ? .white : Theme.Colors.textSecondary)
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.vertical, Theme.Spacing.sm)
                .background(isSelected ? Theme.Colors.accent : Theme.Colors.surface)
                .cornerRadius(Theme.Radius.full)
        }
    }
}

// MARK: - Period Selector

struct PeriodSelector: View {
    @Binding var selected: ProgressView.Period

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(ProgressView.Period.allCases, id: \.self) { period in
                Button {
                    selected = period
                } label: {
                    Text(period.rawValue)
                        .font(Theme.Typography.caption)
                        .foregroundColor(selected == period ? Theme.Colors.accent : Theme.Colors.textSecondary)
                        .padding(.horizontal, Theme.Spacing.sm)
                        .padding(.vertical, Theme.Spacing.xs)
                        .background(
                            selected == period
                                ? Theme.Colors.accent.opacity(0.2)
                                : Color.clear
                        )
                        .cornerRadius(Theme.Radius.small)
                }
            }
        }
        .padding(.horizontal, Theme.Spacing.sm)
        .padding(.vertical, Theme.Spacing.xs)
        .background(Theme.Colors.surface)
        .cornerRadius(Theme.Radius.medium)
    }
}

// MARK: - Chart Section

struct ChartSection: View {
    let metric: ProgressView.Metric
    let period: ProgressView.Period
    let weightEntries: [BodyWeightEntry]

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            if metric == .weight && !weightEntries.isEmpty {
                WeightChart(entries: weightEntries)
            } else {
                PlaceholderChart()
            }
        }
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct WeightChart: View {
    let entries: [BodyWeightEntry]

    var body: some View {
        Chart {
            ForEach(entries) { entry in
                LineMark(
                    x: .value("Date", entry.timestamp),
                    y: .value("Weight", entry.weightKg)
                )
                .foregroundStyle(Theme.Colors.accent)
                .interpolationMethod(.catmullRom)

                AreaMark(
                    x: .value("Date", entry.timestamp),
                    y: .value("Weight", entry.weightKg)
                )
                .foregroundStyle(
                    LinearGradient(
                        colors: [Theme.Colors.accent.opacity(0.3), Theme.Colors.accent.opacity(0.05)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .interpolationMethod(.catmullRom)

                PointMark(
                    x: .value("Date", entry.timestamp),
                    y: .value("Weight", entry.weightKg)
                )
                .foregroundStyle(Theme.Colors.accent)
                .symbolSize(30)
            }
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                    .foregroundStyle(Theme.Colors.textSecondary)
            }
        }
        .chartYAxis {
            AxisMarks { value in
                AxisValueLabel()
                    .foregroundStyle(Theme.Colors.textSecondary)
                AxisGridLine()
                    .foregroundStyle(Theme.Colors.border)
            }
        }
        .frame(height: 200)
    }
}

struct PlaceholderChart: View {
    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 48))
                .foregroundColor(Theme.Colors.textTertiary)

            Text("No data available")
                .font(Theme.Typography.subheadline)
                .foregroundColor(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 200)
    }
}

// MARK: - Progress Stats

struct ProgressStatsSection: View {
    let metric: ProgressView.Metric
    let weightEntries: [BodyWeightEntry]

    var body: some View {
        VStack(spacing: Theme.Spacing.md) {
            if metric == .weight && !weightEntries.isEmpty {
                WeightProgressStats(entries: weightEntries)
            } else {
                EmptyStatsView()
            }
        }
    }
}

struct WeightProgressStats: View {
    let entries: [BodyWeightEntry]

    var currentWeight: Double? {
        entries.last?.weightKg
    }

    var startWeight: Double? {
        entries.first?.weightKg
    }

    var change: Double? {
        guard let current = currentWeight, let start = startWeight else { return nil }
        return current - start
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ProgressStatCard(
                title: "Current",
                value: currentWeight.map { String(format: "%.1f", $0) } ?? "—",
                unit: "kg",
                color: Theme.Colors.textPrimary
            )

            ProgressStatCard(
                title: "Change",
                value: change.map { String(format: "%+.1f", $0) } ?? "—",
                unit: "kg",
                color: change ?? 0 < 0 ? Theme.Colors.success : Theme.Colors.warning
            )

            ProgressStatCard(
                title: "Entries",
                value: "\(entries.count)",
                unit: "logs",
                color: Theme.Colors.accent
            )
        }
    }
}

struct ProgressStatCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: Theme.Spacing.xs) {
            Text(title)
                .font(Theme.Typography.caption)
                .foregroundColor(Theme.Colors.textSecondary)

            Text(value)
                .font(Theme.Typography.title3)
                .foregroundColor(color)

            Text(unit)
                .font(Theme.Typography.caption2)
                .foregroundColor(Theme.Colors.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(Theme.Spacing.md)
        .cardStyle()
    }
}

struct EmptyStatsView: View {
    var body: some View {
        Text("Start tracking to see your progress")
            .font(Theme.Typography.subheadline)
            .foregroundColor(Theme.Colors.textSecondary)
            .frame(maxWidth: .infinity)
            .padding(Theme.Spacing.lg)
            .cardStyle()
    }
}

#Preview {
    ProgressView()
        .environmentObject(AppState())
        .modelContainer(for: [BodyWeightEntry.self])
}

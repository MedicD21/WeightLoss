import SwiftUI

struct SummaryView: View {
    @StateObject private var viewModel = SummaryViewModel()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Today")
                        .font(.headline)
                    Spacer()
                    Button {
                        Task { await viewModel.fetchToday() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }

                if viewModel.isLoading {
                    ProgressView()
                } else if let summary = viewModel.summary {
                    SummaryRow(label: "Calories", value: "\(summary.caloriesConsumed)")
                    if let target = summary.caloriesTarget {
                        SummaryRow(label: "Target", value: "\(target)")
                    }
                    SummaryRow(label: "Protein", value: String(format: "%.0fg", summary.proteinG))
                    SummaryRow(label: "Water", value: String(format: "%.0f oz", WatchUnitConverter.mlToFlOz(summary.waterMl)))
                    if let steps = summary.steps {
                        SummaryRow(label: "Steps", value: "\(steps)")
                    }
                } else if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text("No data yet")
                        .font(.caption)
                }
            }
            .padding()
        }
        .task {
            await viewModel.fetchToday()
        }
    }
}

struct SummaryRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .font(.footnote)
    }
}

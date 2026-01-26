import SwiftUI

struct QuickLogView: View {
    @StateObject private var viewModel = QuickLogViewModel()
    @State private var weightKg: Double = 70

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Log")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Water")
                        .font(.subheadline)
                    HStack {
                        ForEach(WatchConstants.Defaults.quickWaterOptions, id: \.self) { amount in
                            Button("+\(amount)") {
                                Task { await viewModel.logWater(amountMl: amount) }
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Weight")
                        .font(.subheadline)
                    HStack {
                        Stepper(value: $weightKg, in: 30...200, step: 0.1) {
                            Text(String(format: "%.1f kg", weightKg))
                        }
                    }
                    Button("Log Weight") {
                        Task { await viewModel.logWeight(weightKg: weightKg) }
                    }
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

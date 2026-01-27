import SwiftUI

struct QuickLogView: View {
    @StateObject private var viewModel = QuickLogViewModel()
    @State private var weightKg: Double = WatchUnitConverter.lbToKg(170)

    private var weightLbs: Binding<Double> {
        Binding(
            get: { WatchUnitConverter.kgToLb(weightKg) },
            set: { weightKg = WatchUnitConverter.lbToKg($0) }
        )
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Quick Log")
                    .font(.headline)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Water")
                        .font(.subheadline)
                    HStack {
                        ForEach(WatchConstants.Defaults.quickWaterOptionsOz, id: \.self) { ounces in
                            Button("+\(Int(ounces)) oz") {
                                let ml = WatchUnitConverter.flOzToMl(ounces)
                                Task { await viewModel.logWater(amountMl: ml) }
                            }
                        }
                    }
                }

                Divider()

                VStack(alignment: .leading, spacing: 6) {
                    Text("Weight")
                        .font(.subheadline)
                    Stepper(value: weightLbs, in: 90...350, step: 1) {
                        Text(String(format: "%.1f lb", WatchUnitConverter.kgToLb(weightKg)))
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

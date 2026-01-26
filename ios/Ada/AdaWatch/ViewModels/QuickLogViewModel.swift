import Foundation

@MainActor
final class QuickLogViewModel: ObservableObject {
    @Published var isLogging = false
    @Published var message: String? = nil

    func logWater(amountMl: Int) async {
        await log(
            endpoint: "tracking/water",
            body: WatchWaterLogRequest(amountMl: amountMl, timestamp: Self.isoString())
        )
    }

    func logWeight(weightKg: Double) async {
        await log(
            endpoint: "tracking/weight",
            body: WatchWeightLogRequest(weightKg: weightKg, timestamp: Self.isoString())
        )
    }

    private func log(endpoint: String, body: Encodable) async {
        isLogging = true
        message = nil
        do {
            let _: EmptyResponse = try await WatchAPIService.shared.request(
                endpoint: endpoint,
                method: "POST",
                body: body,
                requiresAuth: true
            )
            message = "Logged"
        } catch {
            message = error.localizedDescription
        }
        isLogging = false
    }

    private static func isoString() -> String {
        ISO8601DateFormatter().string(from: Date())
    }
}

struct EmptyResponse: Decodable {}

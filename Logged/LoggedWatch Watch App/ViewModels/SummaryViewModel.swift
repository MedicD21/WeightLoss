import Foundation
import Combine

@MainActor
final class SummaryViewModel: ObservableObject {
    @Published var summary: WatchDailySummary? = nil
    @Published var isLoading = false
    @Published var errorMessage: String? = nil

    func fetchToday() async {
        isLoading = true
        errorMessage = nil
        let dateString = Self.dateFormatter.string(from: Date())

        do {
            summary = try await WatchAPIService.shared.request(
                endpoint: "tracking/daily/\(dateString)",
                method: "GET",
                requiresAuth: true
            )
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        return formatter
    }()
}

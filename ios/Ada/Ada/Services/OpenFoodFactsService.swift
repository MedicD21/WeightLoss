import Foundation

/// Service for Open Food Facts API
@MainActor
final class OpenFoodFactsService {
    static let shared = OpenFoodFactsService()

    private let baseURL = URL(string: Constants.OpenFoodFacts.baseURL)!
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 10
        session = URLSession(configuration: config)
    }

    // MARK: - Barcode Lookup

    func lookupBarcode(_ barcode: String) async throws -> OFFProduct? {
        let url = baseURL.appendingPathComponent("product/\(barcode).json")
        var request = URLRequest(url: url)
        request.setValue(Constants.OpenFoodFacts.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return nil
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(OFFResponse.self, from: data)

        guard result.status == 1, let product = result.product else {
            return nil
        }

        return product
    }

    // MARK: - Search

    func search(query: String, page: Int = 1, pageSize: Int = 20) async throws -> [OFFProduct] {
        var components = URLComponents(url: baseURL.appendingPathComponent("search"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "search_terms", value: query),
            URLQueryItem(name: "page", value: String(page)),
            URLQueryItem(name: "page_size", value: String(pageSize)),
            URLQueryItem(name: "json", value: "1"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments,serving_size,serving_quantity,nutriscore_grade,image_url"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(Constants.OpenFoodFacts.userAgent, forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            return []
        }

        let decoder = JSONDecoder()
        let result = try decoder.decode(OFFSearchResponse.self, from: data)

        return result.products
    }
}

// MARK: - Response Types

struct OFFResponse: Decodable {
    let status: Int
    let product: OFFProduct?
}

struct OFFSearchResponse: Decodable {
    let products: [OFFProduct]
}

struct OFFProduct: Decodable {
    let code: String
    let productName: String?
    let brands: String?
    let imageUrl: String?
    let servingSize: String?
    let servingQuantity: Double?
    let nutriscoreGrade: String?
    let nutriments: OFFNutriments?

    enum CodingKeys: String, CodingKey {
        case code
        case productName = "product_name"
        case brands
        case imageUrl = "image_url"
        case servingSize = "serving_size"
        case servingQuantity = "serving_quantity"
        case nutriscoreGrade = "nutriscore_grade"
        case nutriments
    }

    var name: String {
        productName ?? "Unknown Product"
    }

    var caloriesPer100g: Int? {
        nutriments?.energyKcal100g.map(Int.init)
    }

    var proteinPer100g: Double? {
        nutriments?.proteins100g
    }

    var carbsPer100g: Double? {
        nutriments?.carbohydrates100g
    }

    var fatPer100g: Double? {
        nutriments?.fat100g
    }

    var fiberPer100g: Double? {
        nutriments?.fiber100g
    }

    var defaultServingG: Double {
        servingQuantity ?? 100
    }

    func toSavedFood(userId: UUID) -> SavedFood {
        SavedFood(
            userId: userId,
            name: name,
            brand: brands,
            source: .openFoodFacts,
            caloriesPer100g: caloriesPer100g ?? 0,
            proteinPer100g: proteinPer100g ?? 0,
            carbsPer100g: carbsPer100g ?? 0,
            fatPer100g: fatPer100g ?? 0,
            fiberPer100g: fiberPer100g,
            defaultServingG: defaultServingG,
            barcode: code
        )
    }

    func toFoodItem(grams: Double) -> FoodItem {
        let multiplier = grams / 100.0
        return FoodItem(
            name: brands != nil ? "\(brands!) \(name)" : name,
            source: .openFoodFacts,
            grams: grams,
            calories: Int(Double(caloriesPer100g ?? 0) * multiplier),
            proteinG: (proteinPer100g ?? 0) * multiplier,
            carbsG: (carbsPer100g ?? 0) * multiplier,
            fatG: (fatPer100g ?? 0) * multiplier,
            fiberG: fiberPer100g.map { $0 * multiplier },
            servingSize: defaultServingG,
            barcode: code
        )
    }
}

struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let proteins100g: Double?
    let carbohydrates100g: Double?
    let fat100g: Double?
    let fiber100g: Double?
    let sugars100g: Double?
    let sodium100g: Double?
    let saturatedFat100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case proteins100g = "proteins_100g"
        case carbohydrates100g = "carbohydrates_100g"
        case fat100g = "fat_100g"
        case fiber100g = "fiber_100g"
        case sugars100g = "sugars_100g"
        case sodium100g = "sodium_100g"
        case saturatedFat100g = "saturated-fat_100g"
    }
}

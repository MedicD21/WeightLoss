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
            URLQueryItem(name: "action", value: "process"),
            URLQueryItem(name: "json", value: "true"),
            URLQueryItem(name: "fields", value: "code,product_name,brands,nutriments,serving_size,serving_quantity,nutriscore_grade,image_url"),
        ]

        var request = URLRequest(url: components.url!)
        request.setValue(Constants.OpenFoodFacts.userAgent, forHTTPHeaderField: "User-Agent")

        print("[OFF DEBUG] Search URL: \(components.url?.absoluteString ?? "nil")")

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            print("[OFF DEBUG] Invalid response type")
            return []
        }

        print("[OFF DEBUG] HTTP Status: \(httpResponse.statusCode)")

        guard httpResponse.statusCode == 200 else {
            if let responseString = String(data: data, encoding: .utf8) {
                print("[OFF DEBUG] Error response: \(responseString.prefix(500))")
            }
            return []
        }

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase

        do {
            let result = try decoder.decode(OFFSearchResponse.self, from: data)
            print("[OFF DEBUG] Found \(result.products.count) products")
            return result.products
        } catch {
            print("[OFF DEBUG] Decode error: \(error)")
            if let responseString = String(data: data, encoding: .utf8) {
                print("[OFF DEBUG] Response: \(responseString.prefix(500))")
            }
            return []
        }
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

    var caloriesPerServing: Double? {
        nutriments?.energyKcalServing
    }

    var proteinPer100g: Double? {
        nutriments?.proteins100g
    }

    var proteinPerServing: Double? {
        nutriments?.proteinsServing
    }

    var carbsPer100g: Double? {
        nutriments?.carbohydrates100g
    }

    var carbsPerServing: Double? {
        nutriments?.carbohydratesServing
    }

    var fatPer100g: Double? {
        nutriments?.fat100g
    }

    var fatPerServing: Double? {
        nutriments?.fatServing
    }

    var fiberPer100g: Double? {
        nutriments?.fiber100g
    }

    var fiberPerServing: Double? {
        nutriments?.fiberServing
    }

    var sugarAlcoholPer100g: Double? {
        nutriments?.sugarAlcohol100g
    }

    var sugarAlcoholPerServing: Double? {
        nutriments?.sugarAlcoholServing
    }

    var netCarbsPer100g: Double {
        max(0, (carbsPer100g ?? 0) - (fiberPer100g ?? 0) - (sugarAlcoholPer100g ?? 0))
    }

    var netCarbsPerServing: Double? {
        guard let carbs = carbsPerServing else { return nil }
        return max(0, carbs - (fiberPerServing ?? 0) - (sugarAlcoholPerServing ?? 0))
    }

    var defaultServingG: Double {
        servingQuantity ?? 100
    }

    var servingUnit: String? {
        guard let servingSize = servingSize?.lowercased() else { return nil }
        if servingSize.contains("ml") { return "ml" }
        if servingSize.contains("g") { return "g" }
        if servingSize.contains("oz") { return "oz" }
        return nil
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
        let servings = defaultServingG > 0 ? grams / defaultServingG : 1
        let multiplier = grams / 100.0
        let calories = caloriesPerServing != nil
            ? Int(round((caloriesPerServing ?? 0) * servings))
            : Int(round(Double(caloriesPer100g ?? 0) * multiplier))
        let protein = proteinPerServing != nil
            ? (proteinPerServing ?? 0) * servings
            : (proteinPer100g ?? 0) * multiplier
        let netCarbs = netCarbsPerServing != nil
            ? (netCarbsPerServing ?? 0) * servings
            : netCarbsPer100g * multiplier
        let fat = fatPerServing != nil
            ? (fatPerServing ?? 0) * servings
            : (fatPer100g ?? 0) * multiplier
        let fiber = fiberPerServing != nil
            ? fiberPerServing.map { $0 * servings }
            : fiberPer100g.map { $0 * multiplier }
        return FoodItem(
            name: brands != nil ? "\(brands!) \(name)" : name,
            source: .openFoodFacts,
            grams: grams,
            calories: calories,
            proteinG: protein,
            carbsG: netCarbs,
            fatG: fat,
            fiberG: fiber,
            servingSize: defaultServingG,
            servingUnit: servingUnit,
            servings: servings,
            barcode: code,
            nutriScoreGrade: nutriscoreGrade
        )
    }
}

struct OFFNutriments: Decodable {
    let energyKcal100g: Double?
    let energyKcalServing: Double?
    let proteins100g: Double?
    let proteinsServing: Double?
    let carbohydrates100g: Double?
    let carbohydratesServing: Double?
    let fat100g: Double?
    let fatServing: Double?
    let fiber100g: Double?
    let fiberServing: Double?
    let sugars100g: Double?
    let sugarAlcohol100g: Double?
    let sugarAlcoholServing: Double?
    let sodium100g: Double?
    let saturatedFat100g: Double?

    enum CodingKeys: String, CodingKey {
        case energyKcal100g = "energy-kcal_100g"
        case energyKcalServing = "energy-kcal_serving"
        case proteins100g = "proteins_100g"
        case proteinsServing = "proteins_serving"
        case carbohydrates100g = "carbohydrates_100g"
        case carbohydratesServing = "carbohydrates_serving"
        case fat100g = "fat_100g"
        case fatServing = "fat_serving"
        case fiber100g = "fiber_100g"
        case fiberServing = "fiber_serving"
        case sugars100g = "sugars_100g"
        case sugarAlcohol100g = "polyols_100g"
        case sugarAlcoholServing = "polyols_serving"
        case sodium100g = "sodium_100g"
        case saturatedFat100g = "saturated-fat_100g"
    }
}

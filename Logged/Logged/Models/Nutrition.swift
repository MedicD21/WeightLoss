import Foundation
import SwiftData

/// Source of food item data
enum FoodSource: String, Codable {
    case manual
    case openFoodFacts = "open_food_facts"
    case barcode
    case vision
    case chat
}

/// Type of meal
enum MealType: String, Codable, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack
    case other

    var displayName: String {
        rawValue.capitalized
    }

    var icon: String {
        switch self {
        case .breakfast: return "sunrise.fill"
        case .lunch: return "sun.max.fill"
        case .dinner: return "moon.fill"
        case .snack: return "carrot.fill"
        case .other: return "fork.knife"
        }
    }
}

/// A meal containing one or more food items
@Model
final class Meal {
    @Attribute(.unique) var id: UUID
    var userId: UUID
    var localId: String?

    // Meal info
    var name: String
    var mealType: MealType
    var timestamp: Date
    var notes: String?
    var photoURL: String?

    // Aggregated totals
    var totalCalories: Int
    var totalProteinG: Double
    var totalCarbsG: Double
    var totalFatG: Double
    var totalFiberG: Double?

    // Relationships
    @Relationship(deleteRule: .cascade, inverse: \FoodItem.meal)
    var items: [FoodItem]

    // Sync
    var isSynced: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        mealType: MealType = .other,
        timestamp: Date = Date(),
        notes: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.localId = UUID().uuidString
        self.name = name
        self.mealType = mealType
        self.timestamp = timestamp
        self.notes = notes
        self.totalCalories = 0
        self.totalProteinG = 0
        self.totalCarbsG = 0
        self.totalFatG = 0
        self.items = []
        self.isSynced = false
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func recalculateTotals() {
        totalCalories = items.reduce(0) { $0 + $1.calories }
        totalProteinG = items.reduce(0) { $0 + $1.proteinG }
        totalCarbsG = items.reduce(0) { $0 + $1.carbsG }
        totalFatG = items.reduce(0) { $0 + $1.fatG }
        totalFiberG = items.compactMap { $0.fiberG }.reduce(0, +)
        updatedAt = Date()
    }

    func addItem(_ item: FoodItem) {
        items.append(item)
        recalculateTotals()
    }

    func removeItem(_ item: FoodItem) {
        items.removeAll { $0.id == item.id }
        recalculateTotals()
    }
}

/// Individual food item within a meal
@Model
final class FoodItem {
    @Attribute(.unique) var id: UUID
    var meal: Meal?

    // Food info
    var name: String
    var source: FoodSource

    // Quantity
    var grams: Double
    var servingSize: Double?
    var servingUnit: String?
    var servings: Double

    // Macros (for the amount consumed)
    var calories: Int
    var proteinG: Double
    var carbsG: Double
    var fatG: Double
    var fiberG: Double?

    // Additional nutrition
    var sodiumMg: Double?
    var sugarG: Double?
    var saturatedFatG: Double?

    // Barcode/OFF data
    var barcode: String?
    var offProductId: String?
    var nutriScoreGrade: String?

    // Vision AI metadata
    var confidence: Double?
    var portionDescription: String?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        name: String,
        source: FoodSource = .manual,
        grams: Double,
        calories: Int,
        proteinG: Double,
        carbsG: Double,
        fatG: Double,
        fiberG: Double? = nil,
        servingSize: Double? = nil,
        servingUnit: String? = nil,
        servings: Double = 1.0,
        barcode: String? = nil,
        nutriScoreGrade: String? = nil,
        confidence: Double? = nil,
        portionDescription: String? = nil
    ) {
        self.id = id
        self.name = name
        self.source = source
        self.grams = grams
        self.calories = calories
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
        self.fiberG = fiberG
        self.servingSize = servingSize
        self.servingUnit = servingUnit
        self.servings = servings
        self.barcode = barcode
        self.nutriScoreGrade = nutriScoreGrade
        self.confidence = confidence
        self.portionDescription = portionDescription
        self.createdAt = Date()
    }
}

/// Saved foods for quick access
@Model
final class SavedFood {
    @Attribute(.unique) var id: UUID
    var userId: UUID

    // Food info
    var name: String
    var brand: String?
    var source: FoodSource

    // Per 100g values
    var caloriesPer100g: Int
    var proteinPer100g: Double
    var carbsPer100g: Double
    var fatPer100g: Double
    var fiberPer100g: Double?

    // Default serving
    var defaultServingG: Double
    var servingUnit: String?

    // Barcode
    var barcode: String?

    // Usage tracking
    var timesUsed: Int
    var lastUsedAt: Date?

    var createdAt: Date

    init(
        id: UUID = UUID(),
        userId: UUID,
        name: String,
        brand: String? = nil,
        source: FoodSource = .manual,
        caloriesPer100g: Int,
        proteinPer100g: Double,
        carbsPer100g: Double,
        fatPer100g: Double,
        fiberPer100g: Double? = nil,
        defaultServingG: Double = 100,
        servingUnit: String? = nil,
        barcode: String? = nil
    ) {
        self.id = id
        self.userId = userId
        self.name = name
        self.brand = brand
        self.source = source
        self.caloriesPer100g = caloriesPer100g
        self.proteinPer100g = proteinPer100g
        self.carbsPer100g = carbsPer100g
        self.fatPer100g = fatPer100g
        self.fiberPer100g = fiberPer100g
        self.defaultServingG = defaultServingG
        self.servingUnit = servingUnit
        self.barcode = barcode
        self.timesUsed = 0
        self.createdAt = Date()
    }

    func toFoodItem(grams: Double) -> FoodItem {
        let multiplier = grams / 100.0
        return FoodItem(
            name: brand != nil ? "\(brand!) \(name)" : name,
            source: source,
            grams: grams,
            calories: Int(Double(caloriesPer100g) * multiplier),
            proteinG: proteinPer100g * multiplier,
            carbsG: carbsPer100g * multiplier,
            fatG: fatPer100g * multiplier,
            fiberG: fiberPer100g.map { $0 * multiplier },
            servingSize: defaultServingG,
            servingUnit: servingUnit,
            barcode: barcode
        )
    }
}

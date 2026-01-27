import Foundation

enum WatchUnitConverter {
    static let poundsPerKg: Double = 2.20462
    static let mlPerFlOz: Double = 29.5735

    static func kgToLb(_ kg: Double) -> Double {
        kg * poundsPerKg
    }

    static func lbToKg(_ lb: Double) -> Double {
        lb / poundsPerKg
    }

    static func mlToFlOz(_ ml: Int) -> Double {
        Double(ml) / mlPerFlOz
    }

    static func flOzToMl(_ oz: Double) -> Int {
        Int(round(oz * mlPerFlOz))
    }
}

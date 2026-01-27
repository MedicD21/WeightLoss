import Foundation

enum UnitConverter {
    static let poundsPerKg: Double = 2.20462
    static let inchesPerCm: Double = 0.393701
    static let mlPerFlOz: Double = 29.5735

    static func kgToLb(_ kg: Double) -> Double {
        kg * poundsPerKg
    }

    static func lbToKg(_ lb: Double) -> Double {
        lb / poundsPerKg
    }

    static func cmToIn(_ cm: Double) -> Double {
        cm * inchesPerCm
    }

    static func inToCm(_ inches: Double) -> Double {
        inches / inchesPerCm
    }

    static func mlToFlOz(_ ml: Int) -> Double {
        Double(ml) / mlPerFlOz
    }

    static func flOzToMl(_ oz: Double) -> Int {
        Int(round(oz * mlPerFlOz))
    }

    static func heightStringFromCm(_ cm: Double) -> String {
        let totalInches = Int(round(cmToIn(cm)))
        let feet = totalInches / 12
        let inches = totalInches % 12
        return "\(feet)'\(inches)\""
    }
}

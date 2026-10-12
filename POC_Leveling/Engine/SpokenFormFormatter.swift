import Foundation

public enum SpokenFormFormatter {
    private static let digits: [Character: String] = [
        "0": "zero", "1": "one", "2": "two", "3": "three", "4": "four",
        "5": "five", "6": "six", "7": "seven", "8": "eight", "9": "niner"
    ]

    public static func runway(_ value: String) -> String {
        let uppercase = value.uppercased()
        let numeric = uppercase.prefix { $0.isNumber }
        let suffix = uppercase.dropFirst(numeric.count)
        let spokenDigits = digitWords(String(numeric))
        let spokenSuffix: String
        switch suffix {
        case "L": spokenSuffix = "left"
        case "R": spokenSuffix = "right"
        case "C": spokenSuffix = "centre"
        default: spokenSuffix = ""
        }
        return [spokenDigits, spokenSuffix].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func frequency(_ value: String) -> String {
        let parts = value.split(separator: ".", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return digitWords(value) }
        let fractional = parts[1].trimmingCharacters(in: CharacterSet(charactersIn: "0"))
        return [digitWords(parts[0]), "decimal", digitWords(fractional)].filter { !$0.isEmpty }.joined(separator: " ")
    }

    public static func qnh(_ value: Int) -> String { digitWords(String(value)) }

    public static func heading(_ value: Int) -> String {
        digitWords(String(format: "%03d", ((value % 360) + 360) % 360))
    }

    public static func altitude(_ feet: Int) -> String {
        let thousands = feet / 1000
        let hundreds = (feet % 1000) / 100
        var words: [String] = []
        if thousands > 0 { words += [cardinal(thousands), "thousand"] }
        if hundreds > 0 { words += [cardinal(hundreds), "hundred"] }
        if words.isEmpty { words.append("zero") }
        words.append("feet")
        return words.joined(separator: " ")
    }

    public static func flightLevel(_ value: Int) -> String { "flight level \(digitWords(String(format: "%03d", value)))" }
    public static func speed(_ value: Int) -> String { "\(digitWords(String(value))) knots" }
    public static func degrees(_ value: Int) -> String { "\(heading(value)) degrees" }
    public static func knots(_ value: Int) -> String { speed(value) }

    public static func wind(direction: Int, knots: Int) -> String {
        "\(degrees(direction)) \(self.knots(knots))"
    }

    // ICAO Doc 9432 Section 2.5: Transmission of Time
    public static func timeMinutes(_ minutes: Int) -> String {
        digitWords(String(format: "%02d", minutes % 60))
    }

    public static func timeFull(hour: Int, minute: Int) -> String {
        "\(digitWords(String(format: "%02d", hour % 24))) \(digitWords(String(format: "%02d", minute % 60)))"
    }

    public static func digitWords(_ value: String) -> String {
        value.compactMap { digits[$0] }.joined(separator: " ")
    }

    private static func cardinal(_ value: Int) -> String {
        let values = ["zero", "one", "two", "three", "four", "five", "six", "seven", "eight", "nine"]
        return value >= 0 && value < values.count ? values[value] : digitWords(String(value))
    }
}

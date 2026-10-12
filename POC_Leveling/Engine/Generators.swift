import Foundation

public enum CallsignGenerator {
    private static let gaSuffixes = ["KRS", "ABC", "LNX", "ROZ", "VAL", "PLT", "DEF", "XYZ", "RFA", "BWA"]
    // Official ICAO Doc 8585 Telephony Designators
    private static let airlines: [(name: String, flightNumbers: [Int])] = [
        ("Indonesia", [110, 204, 312, 452, 608, 712, 820]),   // Garuda Indonesia (ICAO: GIA -> Telephony: INDONESIA)
        ("Supergreen", [142, 230, 480, 522, 631, 710]),       // Citilink (ICAO: CTV -> Telephony: SUPERGREEN)
        ("Batik", [6500, 6401, 6300, 6224, 6802, 7015]),      // Batik Air (ICAO: BTK -> Telephony: BATIK)
        ("Lion Inter", [320, 502, 712, 804, 911, 654]),       // Lion Air (ICAO: LNI -> Telephony: LION INTER)
        ("Wagon Air", [502, 751, 804, 920, 411]),             // Indonesia AirAsia (ICAO: AWQ -> Telephony: WAGON AIR)
        ("Prosper", [310, 542, 720, 814, 955, 618]),          // Super Air Jet (ICAO: SJV -> Telephony: PROSPER)
        ("Sriwijaya", [252, 360, 410, 580]),                  // Sriwijaya Air (ICAO: SJY -> Telephony: SRIWIJAYA)
        ("Wings Abadi", [1201, 1405, 1820]),                  // Wings Air (ICAO: WON -> Telephony: WINGS ABADI)
        ("Pelita", [102, 215, 330, 412, 506])                  // Pelita Air (ICAO: PAS -> Telephony: PELITA)
    ]

    public static func generate(profile: FlightProfile, seed: Int) -> String {
        var state = UInt64(bitPattern: Int64(seed &* 2862933555777941757 &+ 3037000493))

        switch profile {
        case .vfrLocal:
            let index = Int(state % UInt64(gaSuffixes.count))
            return "PK-\(gaSuffixes[index])"
        case .ifrCommercial:
            let airlineIndex = Int(state % UInt64(airlines.count))
            let airline = airlines[airlineIndex]
            state = state &* 2862933555777941757 &+ 3037000493
            let flightIndex = Int(state % UInt64(airline.flightNumbers.count))
            let flightNum = airline.flightNumbers[flightIndex]
            let spokenFlight = SpokenFormFormatter.digitWords(String(flightNum))
            return "\(airline.name) \(spokenFlight)"
        }
    }
}

public enum AircraftGenerator {
    private static let level1Aircraft = [
        "Cessna one seven two",
        "Piper Archer two eight",
        "Diamond four zero"
    ]

    private static let level2Aircraft = [
        "ATR seven two",
        "Dash eight",
        "Cessna two zero eight Caravan",
        "Boeing seven three seven"
    ]

    private static let level3Aircraft = [
        "Boeing seven three seven",
        "Airbus A three two zero"
    ]

    private static let level4Aircraft = [
        "Boeing seven three seven",
        "Airbus A three two zero",
        "Airbus A three three zero"
    ]

    private static let level5Aircraft = [
        "Boeing seven three seven",
        "Airbus A three two zero",
        "Airbus A three three zero",
        "Boeing seven seven seven"
    ]

    public static func generate(profile: FlightProfile, level: CurriculumLevel? = nil, seed: Int) -> String {
        if let lvl = level {
            switch lvl {
            case .level1:
                return level1Aircraft[abs(seed) % level1Aircraft.count]
            case .level2:
                return level2Aircraft[abs(seed) % level2Aircraft.count]
            case .level3:
                return level3Aircraft[abs(seed) % level3Aircraft.count]
            case .level4:
                return level4Aircraft[abs(seed) % level4Aircraft.count]
            case .level5:
                return level5Aircraft[abs(seed) % level5Aircraft.count]
            }
        }

        switch profile {
        case .vfrLocal:
            return level1Aircraft[abs(seed) % level1Aircraft.count]
        case .ifrCommercial:
            return level3Aircraft[abs(seed) % level3Aircraft.count]
        }
    }

    public static func generate(profile: FlightProfile, seed: Int) -> String {
        generate(profile: profile, level: nil, seed: seed)
    }
}

public enum FlightLevelGenerator {
    private static let eastboundFLs = [
        "flight level three one zero",
        "flight level three three zero",
        "flight level three five zero",
        "flight level three seven zero"
    ]

    private static let westboundFLs = [
        "flight level three two zero",
        "flight level three four zero",
        "flight level three six zero",
        "flight level three eight zero"
    ]

    public static func cruisingLevel(headingTrack: Int, seed: Int) -> String {
        // Semicircular rule: 000-179 Eastbound (Odd FL), 180-359 Westbound (Even FL)
        let isEastbound = (headingTrack >= 0 && headingTrack < 180)
        let list = isEastbound ? eastboundFLs : westboundFLs
        return list[abs(seed) % list.count]
    }

    public static func initialAltitude(seed: Int) -> String {
        let altitudes = [
            "altitude four thousand feet",
            "altitude five thousand feet",
            "flight level zero eight zero",
            "flight level one zero zero"
        ]
        return altitudes[abs(seed) % altitudes.count]
    }
}

public enum StandGenerator {
    private static let jakartaStands = [
        "Alpha Twelve", "Alpha Seven", "Bravo Six", "Bravo Nine",
        "Echo Four", "Delta Two", "Delta Five", "Fox One", "Gate G Four Two"
    ]

    private static let baliStands = [
        "Alfa One", "Bravo Six", "Charlie Four", "Delta Two", "Echo Three"
    ]

    private static let gaStands = [
        "One", "Two", "Three", "General Aviation Four"
    ]

    public static func originStand(icao: String, seed: Int) -> String {
        switch icao {
        case "WIII":
            return jakartaStands[abs(seed) % jakartaStands.count]
        case "WADD":
            return baliStands[abs(seed) % baliStands.count]
        default:
            return gaStands[abs(seed) % gaStands.count]
        }
    }

    public static func destinationStand(icao: String, seed: Int) -> String {
        switch icao {
        case "WADD":
            return baliStands[abs(seed + 13) % baliStands.count]
        case "WIII":
            return jakartaStands[abs(seed + 13) % jakartaStands.count]
        default:
            return gaStands[abs(seed + 13) % gaStands.count]
        }
    }
}

public enum ATISGenerator {
    private static let letters = [
        "Alfa", "Bravo", "Charlie", "Delta", "Echo",
        "Foxtrot", "Golf", "Hotel", "India", "Kilo",
        "Lima", "Mike", "November", "Oscar", "Papa",
        "Quebec", "Romeo", "Sierra", "Tango", "Uniform",
        "Victor", "Whiskey", "X-ray", "Yankee", "Zulu"
    ]

    public static func letter(seed: Int) -> String {
        let index = abs(seed) % letters.count
        return letters[index]
    }
}

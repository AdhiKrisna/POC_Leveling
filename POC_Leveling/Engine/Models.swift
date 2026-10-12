import Foundation

public enum Phase: String, CaseIterable, Codable, Sendable {
    case preDeparture = "PRE_DEPARTURE"
    case departure = "DEPARTURE"
    case enRoute = "EN_ROUTE"
    case arrival = "ARRIVAL"
    case approach = "APPROACH"
    case landing = "LANDING"

    var resourceName: String {
        switch self {
        case .preDeparture: "pre_departure"
        case .departure: "departure"
        case .enRoute: "en_route"
        case .arrival: "arrival"
        case .approach: "approach"
        case .landing: "landing"
        }
    }

    public var frequencyRole: String {
        switch self {
        case .preDeparture: "Delivery / Ground"
        case .departure: "Tower / Departure"
        case .enRoute: "Area Control / Radar"
        case .arrival: "Arrival / Radar"
        case .approach: "Approach / Tower"
        case .landing: "Tower / Ground"
        }
    }
}

public enum FlightProfile: String, Codable, Sendable {
    case vfrLocal = "VFR_LOCAL"
    case ifrCommercial = "IFR_COMMERCIAL"
}

public struct Airport: Codable, Equatable, Sendable {
    public let icao: String
    public let iata: String?
    public let name: String
    public let profile: FlightProfile
    public let elevationFt: Int
    public let runways: [Runway]
    public let units: AirportUnits
    public let taxiways: [Taxiway]
    public let stands: [Stand]
    public let procedures: Procedures

    enum CodingKeys: String, CodingKey {
        case icao, iata, name, profile, runways, units, taxiways, stands, procedures
        case elevationFt = "elevation_ft"
    }
}

public struct Runway: Codable, Equatable, Sendable {
    public let pair: [String]
    public let designator: String
    public let reciprocal: String
    public let headingDegT: Double
    public let holdingPoints: [String]

    enum CodingKeys: String, CodingKey {
        case pair, designator, reciprocal, holdingPoints
        case headingDegT = "heading_degT"
    }
}

public struct AirportUnits: Codable, Equatable, Sendable {
    public let delivery: ATCUnit?
    public let apron: ATCUnit?
    public let ground: ATCUnit?
    public let tower: ATCUnit?
    public let approach: ATCUnit?
    public let departure: ATCUnit?
    public let center: ATCUnit?
    public let atis: ATCUnit?
}

public struct ATCUnit: Codable, Equatable, Sendable {
    public let callsign: String
    public let frequency: String
}

public struct Taxiway: Codable, Equatable, Sendable {
    public let id: String
    public let spoken: String
}

public struct Stand: Codable, Equatable, Sendable {
    public let id: String
    public let spoken: String
}

public struct Procedures: Codable, Equatable, Sendable {
    public let sids: [SID]
    public let stars: [STAR]
    public let approaches: [ApproachProcedure]
    public let holdings: [Holding]
}

public struct SID: Codable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let runway: String
    public let initialAltFt: Int
    enum CodingKeys: String, CodingKey { case id, name, runway; case initialAltFt = "initialAltFt" }
}

public struct STAR: Codable, Equatable, Sendable { public let id: String; public let name: String; public let runway: String }

public struct ApproachProcedure: Codable, Equatable, Sendable {
    public let id: String
    public let type: String
    public let runway: String
    public let missedApproachAltFt: Int?
    enum CodingKeys: String, CodingKey { case id, type, runway; case missedApproachAltFt = "missedApproachAltFt" }
}

public struct Holding: Codable, Equatable, Sendable {
    public let fix: String
    public let inboundTrack: Int
    public let turns: String
    public let altFt: Int
    enum CodingKeys: String, CodingKey { case fix, turns; case inboundTrack = "inboundTrack"; case altFt = "altFt" }
}

public struct ScenarioTemplate: Codable, Sendable {
    public let id: String
    public let name: String
    public let phase: Phase
    public let profile: [FlightProfile]
    public let isAbnormal: Bool?
    public let exchanges: [ExchangeTemplate]
}

public struct ExchangeTemplate: Codable, Sendable {
    public let turn: Int
    public let speaker: String
    public let isUserTurn: Bool
    public let template: String
    public let slots: [String]
    public let criticalReadback: [CriticalReadbackRule]
    public let branch: String?
}

public struct CriticalReadbackRule: Codable, Sendable {
    public let slot: String
    public let keyword: String?
    public let position: String?
    public let type: String
}

public struct AbnormalEvent: Codable, Sendable { public let id: String; public let name: String; public let eligiblePhases: [Phase] }
public struct EmergencyRule: Codable, Sendable { public let id: String; public let eventClass: String; public let eventType: String; public let severity: String; public let eligiblePhases: [Phase] }

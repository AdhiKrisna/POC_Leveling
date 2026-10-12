import Foundation

public enum PilotEmergencyIntent: String, Sendable {
    case returnToField = "RETURN_TO_FIELD"
    case unknown = "UNKNOWN"
    case forcedLanding = "FORCED_LANDING"
    case priorityLanding = "PRIORITY_LANDING"
}

public struct EmergencyExchangeResult: Equatable, Sendable {
    public let ruleID: String
    public let severity: String
    public let atcText: String
    public let pilotExpectedText: String
    public let criticalReadbacks: [String]

    public init(
        ruleID: String,
        severity: String,
        atcText: String,
        pilotExpectedText: String,
        criticalReadbacks: [String]
    ) {
        self.ruleID = ruleID
        self.severity = severity
        self.atcText = atcText
        self.pilotExpectedText = pilotExpectedText
        self.criticalReadbacks = criticalReadbacks
    }
}

public final class EmergencyResponseEngine {
    private let templateRepository: TemplateRepository

    public init(templateRepository: TemplateRepository = TemplateRepository()) {
        self.templateRepository = templateRepository
    }

    public func evaluate(
        eventType: String,
        intent: PilotEmergencyIntent,
        context: SlotContext
    ) throws -> EmergencyExchangeResult {
        let unit = context.unitTower?.callsign ?? "Tower"

        switch (eventType, intent) {
        case ("ENGINE_FAILURE", .returnToField):
            let spokenRwy = SpokenFormFormatter.runway(context.selectedRunway.designator)
            let spokenWindHdg = SpokenFormFormatter.heading(context.weather.windDirection)
            let spokenWindSpd = SpokenFormFormatter.digitWords(String(context.weather.windSpeed))
            let spokenQnh = SpokenFormFormatter.qnh(context.weather.qnh)

            let atc = "\(context.callsign), \(unit), roger MAYDAY, runway \(spokenRwy), wind \(spokenWindHdg) degrees \(spokenWindSpd) knots, QNH \(spokenQnh), you are number one, report field in sight if able."
            let pilot = "Runway \(spokenRwy), QNH \(spokenQnh), \(context.callsign)."
            return EmergencyExchangeResult(
                ruleID: "EF-A-return-to-field",
                severity: "MAYDAY",
                atcText: atc,
                pilotExpectedText: pilot,
                criticalReadbacks: ["RUNWAY", "QNH", "CALLSIGN"]
            )

        case ("ENGINE_FAILURE", .unknown):
            let atc = "\(context.callsign), \(unit), roger MAYDAY, state intentions."
            return EmergencyExchangeResult(
                ruleID: "EF-B-intention-unknown",
                severity: "MAYDAY",
                atcText: atc,
                pilotExpectedText: "Returning field, \(context.callsign).",
                criticalReadbacks: ["PILOT_INTENTION", "CALLSIGN"]
            )

        case ("ENGINE_FAILURE", .forcedLanding):
            let atc = "\(context.callsign), \(unit), roger MAYDAY, say intended landing area if able."
            return EmergencyExchangeResult(
                ruleID: "EF-D-forced-landing",
                severity: "MAYDAY",
                atcText: atc,
                pilotExpectedText: "Intended landing area southern beach, \(context.callsign).",
                criticalReadbacks: ["LANDING_AREA", "CALLSIGN"]
            )

        case ("MEDICAL", .priorityLanding):
            let spokenRwy = SpokenFormFormatter.runway(context.selectedRunway.designator)
            let spokenWindHdg = SpokenFormFormatter.heading(context.weather.windDirection)
            let spokenWindSpd = SpokenFormFormatter.digitWords(String(context.weather.windSpeed))
            let spokenQnh = SpokenFormFormatter.qnh(context.weather.qnh)

            let atc = "\(context.callsign), \(unit), roger PAN PAN, runway \(spokenRwy), wind \(spokenWindHdg) degrees \(spokenWindSpd) knots, QNH \(spokenQnh), you are number one."
            let pilot = "Runway \(spokenRwy), QNH \(spokenQnh), \(context.callsign)."
            return EmergencyExchangeResult(
                ruleID: "MED-A-priority-landing",
                severity: "PAN_PAN",
                atcText: atc,
                pilotExpectedText: pilot,
                criticalReadbacks: ["RUNWAY", "QNH", "CALLSIGN"]
            )

        default:
            throw GeneratorError.templateNotFound("No emergency rule for \(eventType) / \(intent.rawValue)")
        }
    }
}

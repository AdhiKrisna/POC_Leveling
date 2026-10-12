import Foundation

public struct ScriptRequest: Equatable, Sendable {
    public let phase: Phase
    public let airportID: String
    public let profile: FlightProfile
    public let callsign: String?
    public let seed: Int
    public let includeAbnormal: Bool
    public let includeEmergency: Bool
    public let forcedEventID: String?

    public init(
        phase: Phase,
        airportID: String,
        profile: FlightProfile,
        callsign: String? = nil,
        seed: Int = 4207,
        includeAbnormal: Bool = false,
        includeEmergency: Bool = false,
        forcedEventID: String? = nil
    ) {
        self.phase = phase
        self.airportID = airportID
        self.profile = profile
        self.callsign = callsign
        self.seed = seed
        self.includeAbnormal = includeAbnormal
        self.includeEmergency = includeEmergency
        self.forcedEventID = forcedEventID
    }
}

public struct CriticalSlot: Equatable, Codable, Sendable {
    public let slot: String
    public let expectedValue: String
    public let type: String
    public let position: String?

    public init(slot: String, expectedValue: String, type: String, position: String? = nil) {
        self.slot = slot
        self.expectedValue = expectedValue
        self.type = type
        self.position = position
    }
}

public enum EventSeverity: String, Codable, Sendable {
    case normal = "NORMAL"
    case abnormal = "ABNORMAL"
    case urgency = "URGENCY"    // PAN PAN
    case distress = "DISTRESS"  // MAYDAY
}

public struct InjectedContingency: Equatable, Codable, Sendable {
    public let title: String
    public let severity: EventSeverity
    public let triggerPhase: Phase
    public let summary: String
    public let downstreamEffect: String

    public init(
        title: String,
        severity: EventSeverity,
        triggerPhase: Phase,
        summary: String,
        downstreamEffect: String
    ) {
        self.title = title
        self.severity = severity
        self.triggerPhase = triggerPhase
        self.summary = summary
        self.downstreamEffect = downstreamEffect
    }
}

public enum ContingencySelection: String, CaseIterable, Identifiable, Sendable {
    case auto = "Auto (Random by Difficulty)"
    case routineOnly = "Routine Only (Normal Flight)"
    // L1+ (Local Aerodrome & Visual Circuit)
    case runwayChange = "Runway Wind Shift (180° Change)"
    case forgottenLandingClearancePrompt = "Late Landing Clearance (Short Final Prompt)"
    case abortTakeoff = "Abort Take-Off (Ground Roll Stop)"
    case efato = "EFATO (Engine Out 500ft MAYDAY)"
    case birdHazardHold = "Bird Hazard on Runway (Dispersal Hold)"
    case birdStrikeAbort = "Bird Strike on Take-off Roll (Abort)"

    // L2+ (Cross-Border VFR/IFR Transition)
    case cancelLineUp = "Cancel Line-Up (Traffic Delay)"
    case emergencyLandingHold = "Inbound Emergency Priority (Hold Short / Cancel TO)"
    case lowPassInspection = "Low Pass Inspection (Kencana 191 Style)"
    case weatherDeviation = "Weather Deviation En-Route (CB Avoidance)"
    case flapFailure = "Flap System Failure (Approach DPS PAN PAN)"

    // L3+ (Tactical Radar & Airway IFR)
    case unsafeGear = "Unsafe Gear (VOR Holding & Check)"
    case unclearedGoAround = "No Clearance Received (Uncleared Go-Around)"
    case midAirEngineOut = "Mid-Air Engine Out (Diversion ASSIST)"

    // L4+ (Long Range Corridor & Complex Terrain / Ground)
    case holdShortCrossing = "Runway Incursion Mitigation (Hold Short Crossing)"
    case engineFailureFinal = "Engine Failure on Final (MAYDAY 4 DME)"

    // L5 (Mega-Hub High Density)
    case tcasRA = "TCAS Resolution Advisory"
    case rnavFailure = "RNAV / GPS Failure (Vectoring)"
    case parallelBreakout = "Parallel Breakout (Simultaneous ILS Hazard)"

    // ICAO Doc 9432 Additional Procedures
    // Visual Aerodrome & Circuit Spacing (Doc 9432 Section 4.6)
    case visualOrbitSpacing = "Visual Orbit for Spacing (360° Turn)"
    case extendDownwind = "Extend Downwind (Traffic Spacing)"
    case nordoBlindTransmission = "Transmitting Blind (NORDO Receiver Fail)"

    // Take-off Line-Up & Runway Operations (Doc 9432 Section 4.5)
    case wakeTurbulenceLineUp = "Wake Turbulence Line-Up (2 Min Delay)"
    case immediateTakeoffOrVacate = "Immediate Take-off or Vacate Runway"

    // Radar & High Altitude En-Route (Doc 9432 Section 6.4 & 9.4)
    case radarAvoidingAction = "Radar Avoiding Action (Near-Miss Turn)"
    case emergencyDescentDecompression = "Emergency Descent (Cabin Decompression)"

    // Aerodrome Weather & Special Urgency (Doc 9432 Section 9.2, 9.3, 10.2, 10.3)
    case impositionOfSilence = "Imposition of Silence (MAYDAY Traffic)"
    case passengerMedicalEmergency = "Medical Priority PAN PAN (Heart Attack)"
    case lowVisibilityRVR = "Low Visibility RVR Breakdown (Cat II ILS)"
    case contaminatedRunwayBraking = "Contaminated Runway & Braking Action Poor"

    public var id: String { rawValue }

    public var defaultSeverity: EventSeverity {
        switch self {
        case .efato, .midAirEngineOut, .engineFailureFinal, .tcasRA, .parallelBreakout, .birdStrikeAbort, .emergencyDescentDecompression:
            return .distress
        case .flapFailure, .unsafeGear, .unclearedGoAround, .emergencyLandingHold, .nordoBlindTransmission, .radarAvoidingAction, .impositionOfSilence, .passengerMedicalEmergency:
            return .urgency
        default:
            return .abnormal
        }
    }

    public var triggerPhase: Phase {
        switch self {
        case .runwayChange, .holdShortCrossing:
            return .preDeparture
        case .abortTakeoff, .efato, .cancelLineUp, .birdHazardHold, .birdStrikeAbort, .emergencyLandingHold, .wakeTurbulenceLineUp, .immediateTakeoffOrVacate:
            return .departure
        case .weatherDeviation, .midAirEngineOut, .tcasRA, .nordoBlindTransmission, .radarAvoidingAction, .emergencyDescentDecompression:
            return .enRoute
        case .rnavFailure, .passengerMedicalEmergency:
            return .arrival
        case .lowPassInspection, .forgottenLandingClearancePrompt, .flapFailure, .unsafeGear, .unclearedGoAround, .engineFailureFinal, .parallelBreakout, .visualOrbitSpacing, .extendDownwind, .impositionOfSilence, .lowVisibilityRVR, .contaminatedRunwayBraking:
            return .approach
        default:
            return .enRoute
        }
    }

    public var shortDisplayName: String {
        switch self {
        case .auto: "Auto"
        case .routineOnly: "Routine Only"
        case .runwayChange: "Runway Change"
        case .forgottenLandingClearancePrompt: "Late Landing Prompt"
        case .abortTakeoff: "Abort Take-Off"
        case .efato: "EFATO (Engine Out)"
        case .birdHazardHold: "Bird Hazard Hold"
        case .birdStrikeAbort: "Bird Strike Abort"
        case .cancelLineUp: "Cancel Line-Up"
        case .emergencyLandingHold: "Inbound Emergency Priority"
        case .lowPassInspection: "Low Pass Inspection"
        case .weatherDeviation: "Weather Deviation"
        case .flapFailure: "Flap Failure"
        case .unsafeGear: "Unsafe Gear"
        case .unclearedGoAround: "Uncleared Go-Around"
        case .midAirEngineOut: "Mid-Air Engine Out"
        case .holdShortCrossing: "Hold Short Crossing"
        case .engineFailureFinal: "Engine Failure Final"
        case .tcasRA: "TCAS RA"
        case .rnavFailure: "RNAV GPS Failure"
        case .parallelBreakout: "Parallel Breakout"
        case .visualOrbitSpacing: "Visual Orbit 360°"
        case .extendDownwind: "Extend Downwind"
        case .nordoBlindTransmission: "Blind Transmission (NORDO)"
        case .wakeTurbulenceLineUp: "Wake Turbulence Wait"
        case .immediateTakeoffOrVacate: "Takeoff or Vacate"
        case .radarAvoidingAction: "Avoiding Action (Near-Miss)"
        case .emergencyDescentDecompression: "Emergency Descent (Cabin Alt)"
        case .impositionOfSilence: "Silence Imposed (MAYDAY)"
        case .passengerMedicalEmergency: "Medical Priority (PAN PAN)"
        case .lowVisibilityRVR: "Low Visibility RVR"
        case .contaminatedRunwayBraking: "Runway Water / Braking Poor"
        }
    }
}

public struct FilledExchange: Equatable, Codable, Sendable, Identifiable {
    public var id: String { exchangeID }
    public let exchangeID: String
    public let templateID: String
    public let turn: Int
    public let speaker: String
    public let isUserTurn: Bool
    public let text: String
    public let criticalSlots: [CriticalSlot]
    public let severity: EventSeverity
    public let eventTag: String?

    public init(
        exchangeID: String,
        templateID: String,
        turn: Int,
        speaker: String,
        isUserTurn: Bool,
        text: String,
        criticalSlots: [CriticalSlot],
        severity: EventSeverity = .normal,
        eventTag: String? = nil
    ) {
        self.exchangeID = exchangeID
        self.templateID = templateID
        self.turn = turn
        self.speaker = speaker
        self.isUserTurn = isUserTurn
        self.text = text
        self.criticalSlots = criticalSlots
        self.severity = severity
        self.eventTag = eventTag
    }
}

public struct SlotContext: Equatable, Sendable {
    public let airport: Airport
    public let selectedRunway: Runway
    public let holdingPoint: String
    public let taxiRoute: String
    public let callsign: String
    public let weather: AlignedWeather
    public let atisId: String
    public let unitGround: ATCUnit?
    public let unitTower: ATCUnit?
    public let unitApproach: ATCUnit?
    public let unitDeparture: ATCUnit?
    public let unitDelivery: ATCUnit?
    public let unitControl: ATCUnit?
    public let stand: String
    public let aircraftType: String
    public let pob: Int

    // Extended flight parameters
    public let airportName: String
    public let destinationName: String
    public let sidProcedure: String
    public let starProcedure: String
    public let squawk: String
    public let depFreq: String
    public let approachFreq: String
    public let controlFreq: String
    public let arrRunway: String
    public let arrAtisId: String
    public let visibility: String
    public let cloudCondition: String
    public let temperature: String
    public let dewPoint: String

    public let turnDirection: String
    public let heading: Int
    public let initialAlt: String
    public let levelStatus: String
    public let currentLevel: String
    public let routeContext: String
    public let currentPosition: String
    public let timeUTC: String
    public let nextPosition: String
    public let nextETA: String
    public let requestedLevel: String
    public let requestedDeviationDistance: String
    public let requestedDeviationDirection: String
    public let approvedDeviationDistance: String
    public let approvedDeviationDirection: String
    public let descentLevel: String
    public let holdingFix: String
    public let holdingLevel: String
    public let inboundTrack: String
    public let eat: String
    public let goAroundReason: String
    public let missedAlt: String
    public let missedInstruction: String
    public let exitDirection: String
    public let exitTaxiway: String
    public let destinationStand: String
    public let taxiInRoute: String
}

public struct GeneratedScript: Equatable, Sendable {
    public let id: UUID
    public let seed: Int
    public let phase: Phase
    public let airport: String
    public let callsign: String
    public let context: SlotContext
    public let exchanges: [FilledExchange]
    public let criticalSlots: [CriticalSlot]
}

// MARK: - Full Flight Mission Models

public enum UserRole: String, CaseIterable, Identifiable, Sendable {
    case pilot = "Student Pilot"
    case atc = "ATC Trainee"
    public var id: String { rawValue }
}

public enum SimulationMode: String, CaseIterable, Identifiable, Sendable {
    case practice = "Practice Mode"
    case learning = "Learning Mode"
    public var id: String { rawValue }
}

public enum CurriculumLevel: Int, CaseIterable, Identifiable, Sendable {
    case level1 = 1
    case level2 = 2
    case level3 = 3
    case level4 = 4
    case level5 = 5

    public var id: Int { rawValue }

    public var nextLevel: CurriculumLevel? {
        CurriculumLevel(rawValue: rawValue + 1)
    }

    public var title: String {
        switch self {
        case .level1: "Level 1: Local Flight (BWX – BWX)"
        case .level2: "Level 2: Point-to-Point Lintas Batas (BWX – DPS)"
        case .level3: "Level 3: Medium Cross-Country & Tactical Radar (DPS – SUB)"
        case .level4: "Level 4: Long-Range Corridor & Mega-Hub Complexity (SUB – YIA)"
        case .level5: "Level 5: High-Density Trunk Route (YIA – CGK)"
        }
    }

    public var routeCode: String {
        switch self {
        case .level1: "BWX → BWX"
        case .level2: "BWX → DPS"
        case .level3: "DPS → SUB"
        case .level4: "SUB → YIA"
        case .level5: "YIA → CGK"
        }
    }

    public var originICAO: String {
        switch self {
        case .level1: "WADY"
        case .level2: "WADY"
        case .level3: "WADD"
        case .level4: "WARR"
        case .level5: "WAHI"
        }
    }

    public var destinationICAO: String {
        switch self {
        case .level1: "WADY"
        case .level2: "WADD"
        case .level3: "WARR"
        case .level4: "WAHI"
        case .level5: "WIII"
        }
    }

    public var defaultProfile: FlightProfile {
        switch self {
        case .level1: .vfrLocal
        case .level2, .level3, .level4, .level5: .ifrCommercial
        }
    }

    public var curriculumObjective: String {
        switch self {
        case .level1: "Pembentukan fondasi frasa ICAO, disiplin sirkuit visual, dan operasi prosedural tanpa radar."
        case .level2: "Transisi ruang udara, transfer frekuensi (handoff), dan integrasi lalu lintas campuran VFR-IFR."
        case .level3: "Kepatuhan penuh aturan terbang instrumen (IFR), vektor radar taktis, dan prosedur instrumen kompleks."
        case .level4: "Navigasi koridor padat, operasi darat multi-landasan, fragmentasi frekuensi, dan disiplin anti-blocking."
        case .level5: "Kepatuhan slot waktu A-CDM, RNAV 1 kompleks, holding stack EFC time, dan simultaneous parallel approach."
        }
    }

    public var emergencyFocus: String {
        switch self {
        case .level1: "EFATO (Engine Failure After Takeoff) / NORDO (No Radio)"
        case .level2: "Awan CB Selat Bali (Weather Deviation) / Flap System Failure"
        case .level3: "Unsafe Gear Indication / Missed Approach & Holding Pattern"
        case .level4: "Engine Failure on Final Approach / Runway Crossing Blocked / Fuel Emergency"
        case .level5: "TCAS Resolution Advisory (TCAS RA) / RNAV GPS Failure / Parallel Breakout"
        }
    }

    public var sidName: String {
        switch self {
        case .level1: "Circuit Departure"
        case .level2: "Area Alpha Departure via Selat Bali"
        case .level3: "BLI Two Charlie (BLI 2C)"
        case .level4: "SURABAYA One Bravo (SBY 1B)"
        case .level5: "JOG One Charlie (JOG 1C)"
        }
    }

    public var starName: String {
        switch self {
        case .level1: "Overhead Join Pattern"
        case .level2: "Right Base Runway 09"
        case .level3: "POSOP One Alfa (POSOP 1A)"
        case .level4: "GANDI One Alfa (GANDI 1A)"
        case .level5: "DOLTA One Alfa (DOLTA 1A)"
        }
    }

    public var criticalPhrases: [String] {
        switch self {
        case .level1:
            return ["Backtrack runway 08 approved", "Report downwind", "Touch and go approved", "Orbit right present position"]
        case .level2:
            return ["Contact Bali Approach 124.0", "Caution wake turbulence behind B737", "Join right base runway 09"]
        case .level3:
            return ["Cleared to Surabaya via W17", "Vector for ILS runway 10", "Reduce speed 160 knots", "Execute missed approach"]
        case .level4:
            return ["Pushback facing north", "Cross runway 25L hold short 25R", "Direct BUNTA", "Contact Jakarta Director 124.35"]
        case .level5:
            return ["Cancel speed restriction above 10,000", "Cross BUNTA at FL140, 220 knots", "Expect further clearance at 45", "TCAS RA, returning FL180"]
        }
    }

    public var allowedContingencies: [ContingencySelection] {
        switch self {
        case .level1:
            // Sirkuit Visual Latih Dasar BWX: pola visual, spacing, touch-and-go, dan darurat lokal
            return [
                .auto,
                .routineOnly,
                .runwayChange,
                .birdHazardHold,
                .visualOrbitSpacing,
                .extendDownwind,
                .forgottenLandingClearancePrompt,
                .nordoBlindTransmission,
                .abortTakeoff,
                .birdStrikeAbort,
                .efato
            ]
        case .level2:
            // Lintas Batas BWX-DPS: WAJIB TERBANG KE BALI (tidak ada abort di darat Banyuwangi)
            return [
                .auto,
                .routineOnly,
                .runwayChange,
                .cancelLineUp,
                .birdHazardHold,
                .weatherDeviation,
                .passengerMedicalEmergency,
                .flapFailure,
                .lowPassInspection
            ]
        case .level3:
            // Tactical Radar IFR DPS-SUB: WAJIB TERBANG KE SURABAYA (fokus radar vectors, ILS Surabaya, gear holding)
            return [
                .auto,
                .routineOnly,
                .runwayChange,
                .wakeTurbulenceLineUp,
                .radarAvoidingAction,
                .unsafeGear,
                .unclearedGoAround,
                .contaminatedRunwayBraking,
                .impositionOfSilence
            ]
        case .level4:
            // Corridor & Terrain Complexity SUB-YIA: WAJIB TERBANG KE YIA (fokus en-route failure, depressurization, crossing Juanda)
            return [
                .auto,
                .routineOnly,
                .holdShortCrossing,
                .wakeTurbulenceLineUp,
                .immediateTakeoffOrVacate,
                .weatherDeviation,
                .midAirEngineOut,
                .emergencyDescentDecompression,
                .engineFailureFinal,
                .lowVisibilityRVR
            ]
        case .level5:
            // Mega-Hub Trunk YIA-CGK: Kapabilitas Penuh Mega-Hub Cengkareng
            return ContingencySelection.allCases
        }
    }

    public var allowedScenarios: [ContingencySelection] {
        allowedContingencies.filter { $0 != .auto && $0 != .routineOnly }
    }
}

public struct DiagnosticReport: Sendable, Equatable {
    public let overallScore: Int
    public let readbackAccuracyPercent: Int
    public let phraseologyScorePercent: Int
    public let disciplineScorePercent: Int
    public let isPassed: Bool
    public let summaryFeedback: String
    public let improvementAreas: [String]
}

public enum MissionArchetype: String, CaseIterable, Sendable, Identifiable {
    // IFR Archetypes
    case ifrRoutineDirect = "Routine Flight (Step Climb & Straight-in ILS)"
    case ifrWeatherAvoidance = "Severe Weather Diversion (CB Avoidance)"
    case ifrAirspaceCongestion = "Airspace Congestion & Radar Vectoring"
    case ifrHoldingPattern = "Holding Delay over VOR (Traffic Queue)"
    case ifrGoAroundReApproach = "Unstabilized Approach & Go-Around Loop"

    // VFR Archetypes
    case vfrTrainingAreaAirwork = "Training Area Alpha Airwork & Maneuvers"
    case vfrCircuitTouchAndGo = "Circuit Traffic Pattern (Touch & Go)"
    case vfrSimulatedEngineOut = "Simulated Engine Failure in Circuit"

    public var id: String { rawValue }
}

public struct FlightMissionContext: Equatable, Sendable {
    public let missionID: UUID
    public let profile: FlightProfile
    public let archetype: MissionArchetype
    public let aircraftType: String
    public let callsign: String
    public let originAirport: Airport
    public let destinationAirport: Airport
    public let depRunway: Runway
    public let arrRunway: Runway
    public let depWeather: AlignedWeather
    public let arrWeather: AlignedWeather
    public let depAtisId: String
    public let arrAtisId: String
    public let cruisingLevel: String
    public let squawkCode: String
    public let initialAlt: String
    public let sidProcedure: String
    public let starProcedure: String
    public let departureHeading: Int
    public let standOrigin: String
    public let standDestination: String
    public let taxiOutRoute: String
    public let taxiInRoute: String
    public let weatherDeviationDistance: String?
    public let weatherDeviationDirection: String?

    public var depAtisBroadcastText: String {
        let infoName = originAirport.name.components(separatedBy: " ").first ?? originAirport.name
        let windSpoken = SpokenFormFormatter.wind(direction: depWeather.windDirection, knots: depWeather.windSpeed)
        let rwySpoken = SpokenFormFormatter.runway(depRunway.designator)
        let qnhSpoken = SpokenFormFormatter.qnh(depWeather.qnh)
        return "\(infoName) Information \(depAtisId). Time zero one two zero UTC. Wind \(windSpoken). Runway \(rwySpoken) in use. QNH \(qnhSpoken) hPa. Advise information \(depAtisId) received on initial contact."
    }
}

public struct PhaseScript: Identifiable, Equatable, Sendable {
    public var id: Phase { phase }
    public let phase: Phase
    public let title: String
    public let educationalGoal: String
    public let exchanges: [FilledExchange]

    public var turnCount: Int { exchanges.count }
    public var estimatedDurationMinutes: Double { Double(exchanges.count) * 0.45 }
}

public struct FlightMissionScript: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let seed: Int
    public let level: CurriculumLevel?
    public let role: UserRole
    public let mode: SimulationMode
    public let profile: FlightProfile
    public let archetype: MissionArchetype
    public let originAirport: Airport
    public let destinationAirport: Airport
    public let callsign: String
    public let missionContext: FlightMissionContext
    public let phaseScripts: [PhaseScript]
    public let diagnosticReport: DiagnosticReport?
    public let contingencies: [InjectedContingency]

    public var contingency: InjectedContingency? {
        contingencies.first
    }

    public init(
        id: UUID = UUID(),
        seed: Int,
        level: CurriculumLevel? = nil,
        role: UserRole = .pilot,
        mode: SimulationMode = .practice,
        profile: FlightProfile,
        archetype: MissionArchetype,
        originAirport: Airport,
        destinationAirport: Airport,
        callsign: String,
        missionContext: FlightMissionContext,
        phaseScripts: [PhaseScript],
        diagnosticReport: DiagnosticReport? = nil,
        contingency: InjectedContingency? = nil,
        contingencies: [InjectedContingency] = []
    ) {
        self.id = id
        self.seed = seed
        self.level = level
        self.role = role
        self.mode = mode
        self.profile = profile
        self.archetype = archetype
        self.originAirport = originAirport
        self.destinationAirport = destinationAirport
        self.callsign = callsign
        self.missionContext = missionContext
        self.phaseScripts = phaseScripts
        self.diagnosticReport = diagnosticReport
        if !contingencies.isEmpty {
            self.contingencies = contingencies
        } else if let c = contingency {
            self.contingencies = [c]
        } else {
            self.contingencies = []
        }
    }

    public var allExchanges: [FilledExchange] {
        phaseScripts.flatMap { $0.exchanges }
    }

    public var totalExchanges: Int {
        allExchanges.count
    }

    public var totalEstimatedDurationMinutes: Double {
        phaseScripts.reduce(0.0) { $0 + $1.estimatedDurationMinutes }
    }

    public var allCriticalSlots: [CriticalSlot] {
        allExchanges.filter { $0.isUserTurn }.flatMap { $0.criticalSlots }
    }

    public func exportAsPlainText() -> String {
        var output = """
        ================================================================================
        HERMES RADIOTELEPHONY SIMULATION FLIGHT SCRIPT
        Level: \(level?.title ?? "Custom Route")
        Mode: \(mode.rawValue) | Role: \(role.rawValue) | Seed: \(seed)
        Route: \(missionContext.originAirport.icao) (\(missionContext.originAirport.name)) -> \(missionContext.destinationAirport.icao) (\(missionContext.destinationAirport.name))
        Aircraft: \(missionContext.aircraftType) | Callsign: \(callsign)
        Assigned SID: \(missionContext.sidProcedure) | Assigned STAR: \(missionContext.starProcedure)
        Departure Runway: \(missionContext.depRunway.designator) | Arrival Runway: \(missionContext.arrRunway.designator)
        Departure Weather: Wind \(missionContext.depWeather.windDirection)°/\(missionContext.depWeather.windSpeed) kts | QNH \(missionContext.depWeather.qnh) hPa | ATIS \(missionContext.depAtisId)
        Assigned Squawk: \(missionContext.squawkCode) | Cruising Level: \(missionContext.cruisingLevel)
        Total Turns: \(totalExchanges) | Estimated Duration: \(String(format: "%.1f", totalEstimatedDurationMinutes)) mins
        ================================================================================
        📻 COCKPIT ATIS BROADCAST (ICAO DOC 9432 BAB 4.4.3 / 4.6.2):
        "\(missionContext.depAtisBroadcastText)"
        (Prosedur Resmi: Pilot memantau ATIS secara pasif di radio COMM-2 sebelum transmisi awal; pilot menyatakan kode pengenal '\(missionContext.depAtisId)' pada initial call ke ATC).
        ================================================================================
        """

        if let cont = contingency {
            output += """

            ⚠️ INJECTED CONTINGENCY EVENT: [\(cont.severity.rawValue)] \(cont.title)
            Phase Trigger: \(cont.triggerPhase.rawValue)
            Situation: \(cont.summary)
            Downstream Impact: \(cont.downstreamEffect)
            ================================================================================
            """
        }

        output += "\n"

        for phaseScript in phaseScripts {
            output += """

            ================================================================================
            \(phaseScript.title.uppercased())
            Goal: \(phaseScript.educationalGoal)
            Turns: \(phaseScript.turnCount) (~ \(String(format: "%.1f", phaseScript.estimatedDurationMinutes)) minutes)
            --------------------------------------------------------------------------------

            """

            for ex in phaseScript.exchanges {
                var speakerLabel = ex.isUserTurn ? "\(ex.speaker) [USER TURN]" : ex.speaker
                if ex.severity != .normal, let tag = ex.eventTag {
                    speakerLabel += " [\(ex.severity.rawValue): \(tag)]"
                }
                output += "Turn \(ex.turn) | \(speakerLabel):\n"
                output += "\"\(ex.text)\"\n"
                if !ex.criticalSlots.isEmpty {
                    let items = ex.criticalSlots.map { "\($0.slot): '\($0.expectedValue)'" }.joined(separator: ", ")
                    output += "  >> Mandatory Readback: [\(items)]\n"
                }
                output += "\n"
            }
        }

        if let diag = diagnosticReport {
            output += """

            ================================================================================
            DIAGNOSTIC & PERFORMANCE EVALUATION (POST-SESSION REPORT)
            Status: \(diag.isPassed ? "PASSED (SCORE >= 80%)" : "NEEDS IMPROVEMENT (SCORE < 80%)")
            Overall Score: \(diag.overallScore)%
            - Safety-Critical Readback Accuracy: \(diag.readbackAccuracyPercent)%
            - Standard ICAO Phraseology Compliance: \(diag.phraseologyScorePercent)%
            - Transmission Discipline & Latency: \(diag.disciplineScorePercent)%

            Summary:
            \(diag.summaryFeedback)

            Key Improvement Areas:
            """
            for area in diag.improvementAreas {
                output += "\n• \(area)"
            }
            output += "\n"
        }

        output += """

        ================================================================================
        END OF SIMULATION SCRIPT — HERMES TECHNICAL SECOND BRAIN
        ================================================================================
        """
        return output
    }
}

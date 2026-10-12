import Foundation

public enum GeneratorError: Error, LocalizedError {
    case airportNotFound(String)
    case templateNotFound(String)
    case unresolvedSlot(String)

    public var errorDescription: String? {
        switch self {
        case let .airportNotFound(icao): "Airport not found: \(icao)"
        case let .templateNotFound(id): "Template not found: \(id)"
        case let .unresolvedSlot(slot): "Slot could not be resolved: \(slot)"
        }
    }
}

public final class ScriptGeneratorEngine {
    private let airportRepository: AirportRepository
    private let templateRepository: TemplateRepository

    public init(
        airportRepository: AirportRepository = AirportRepository(),
        templateRepository: TemplateRepository = TemplateRepository()
    ) {
        self.airportRepository = airportRepository
        self.templateRepository = templateRepository
    }

    // MARK: - Legacy Single Phase Generator
    public func generate(request: ScriptRequest) throws -> GeneratedScript {
        let airport = try airportRepository.airport(icao: request.airportID)
        let resolvedCallsign = request.callsign ?? CallsignGenerator.generate(profile: request.profile, seed: request.seed)
        let context = resolveContext(airport: airport, request: request, callsign: resolvedCallsign)

        let templates = try templateRepository.templates(for: request.phase)
        let chain = buildTemplateChain(
            availableTemplates: templates,
            request: request,
            context: context
        )

        var allFilledExchanges: [FilledExchange] = []
        var allCriticalSlots: [CriticalSlot] = []
        var globalTurn = 1

        for template in chain {
            for exchange in template.exchanges {
                let filledText = fillTemplateSlots(exchange.template, context: context)
                let resolvedCritical = resolveCriticalSlots(exchange.criticalReadback, context: context)

                let filledExchange = FilledExchange(
                    exchangeID: "\(template.id)-t\(exchange.turn)",
                    templateID: template.id,
                    turn: globalTurn,
                    speaker: exchange.speaker,
                    isUserTurn: exchange.isUserTurn,
                    text: filledText,
                    criticalSlots: resolvedCritical
                )

                allFilledExchanges.append(filledExchange)
                if exchange.isUserTurn {
                    allCriticalSlots.append(contentsOf: resolvedCritical)
                }
                globalTurn += 1
            }
        }

        return GeneratedScript(
            id: UUID(),
            seed: request.seed,
            phase: request.phase,
            airport: request.airportID,
            callsign: resolvedCallsign,
            context: context,
            exchanges: allFilledExchanges,
            criticalSlots: allCriticalSlots
        )
    }

    // MARK: - Full Flight Mission Generator (End-to-End Across 6 Phases)
    public func generateFullMission(
        profile: FlightProfile? = nil,
        originICAO: String? = nil,
        destinationICAO: String? = nil,
        seed: Int? = nil,
        includeAbnormal: Bool = false,
        includeEmergency: Bool = false
    ) throws -> FlightMissionScript {
        let chosenSeed = seed ?? Int.random(in: 1000...9999)
        let chosenProfile: FlightProfile
        let originID: String
        let destinationID: String

        // Profile & Route Resolution
        if let explicitProfile = profile {
            chosenProfile = explicitProfile
            if explicitProfile == .vfrLocal {
                originID = originICAO ?? "WADY"
                destinationID = destinationICAO ?? "WADY"
            } else {
                if abs(chosenSeed) % 2 == 0 {
                    originID = originICAO ?? "WIII"
                    destinationID = destinationICAO ?? "WADD"
                } else {
                    originID = originICAO ?? "WADD"
                    destinationID = destinationICAO ?? "WIII"
                }
            }
        } else {
            if chosenSeed % 3 == 0 {
                chosenProfile = .vfrLocal
                originID = originICAO ?? "WADY"
                destinationID = destinationICAO ?? "WADY"
            } else {
                chosenProfile = .ifrCommercial
                if abs(chosenSeed) % 2 == 0 {
                    originID = originICAO ?? "WIII"
                    destinationID = destinationICAO ?? "WADD"
                } else {
                    originID = originICAO ?? "WADD"
                    destinationID = destinationICAO ?? "WIII"
                }
            }
        }

        let originAirport = try airportRepository.airport(icao: originID)
        let destinationAirport = try airportRepository.airport(icao: destinationID)

        let callsign = CallsignGenerator.generate(profile: chosenProfile, seed: chosenSeed)
        let aircraftType = AircraftGenerator.generate(profile: chosenProfile, seed: chosenSeed)

        // Dynamic Wind and Runways for Origin
        let depRwyHeadings = Dictionary(uniqueKeysWithValues: originAirport.runways.map { ($0.designator, $0.headingDegT) })
        let depRwyPair = originAirport.runways.first?.pair ?? [originAirport.runways.first?.designator ?? "08"]
        let depWeather = WeatherEngine.alignedWeather(
            runway: originAirport.runways.first?.designator ?? "08",
            heading: originAirport.runways.first?.headingDegT ?? 80,
            seed: chosenSeed
        )
        let depRwyDesignator = WeatherEngine.bestRunway(
            pair: depRwyPair,
            headings: depRwyHeadings,
            windDirection: Double(depWeather.windDirection),
            windSpeed: Double(depWeather.windSpeed)
        ).runway
        let depRunway = originAirport.runways.first(where: { $0.designator == depRwyDesignator }) ?? originAirport.runways.first!

        // Dynamic Wind and Runways for Destination
        let arrRwyHeadings = Dictionary(uniqueKeysWithValues: destinationAirport.runways.map { ($0.designator, $0.headingDegT) })
        let arrRwyPair = destinationAirport.runways.first?.pair ?? [destinationAirport.runways.first?.designator ?? "09"]
        let arrWeather = WeatherEngine.alignedWeather(
            runway: destinationAirport.runways.first?.designator ?? "09",
            heading: destinationAirport.runways.first?.headingDegT ?? 90,
            seed: chosenSeed + 101
        )
        let arrRwyDesignator = WeatherEngine.bestRunway(
            pair: arrRwyPair,
            headings: arrRwyHeadings,
            windDirection: Double(arrWeather.windDirection),
            windSpeed: Double(arrWeather.windSpeed)
        ).runway
        let arrRunway = destinationAirport.runways.first(where: { $0.designator == arrRwyDesignator }) ?? destinationAirport.runways.first!

        let depAtisId = ATISGenerator.letter(seed: chosenSeed)
        let arrAtisId = ATISGenerator.letter(seed: chosenSeed + 5)

        let depHeading = Int(depRunway.headingDegT)

        // Cruise Altitude using Semicircular Rule & SIDs/STARs
        let flightHeadingTrack = (originAirport.icao == "WIII" && destinationAirport.icao == "WADD") ? 95 : 280
        let cruisingLevel: String
        let initialAlt: String
        if chosenProfile == .vfrLocal {
            let vfrAlts = ["two thousand five hundred feet", "three thousand feet", "three thousand five hundred feet"]
            cruisingLevel = vfrAlts[abs(chosenSeed) % vfrAlts.count]
            initialAlt = "altitude two thousand five hundred feet"
        } else {
            cruisingLevel = FlightLevelGenerator.cruisingLevel(headingTrack: flightHeadingTrack, seed: chosenSeed)
            initialAlt = FlightLevelGenerator.initialAltitude(seed: chosenSeed)
        }

        let sidName: String
        let starName: String
        if originAirport.icao == "WIII" {
            sidName = (abs(chosenSeed) % 2 == 0) ? "DOLTA One Alfa" : "BUNTA One Bravo"
            starName = "ELANG One Alfa"
        } else if originAirport.icao == "WADD" {
            sidName = "BLI Two Charlie"
            starName = "DOLTA One Bravo"
        } else {
            sidName = "Area Alpha departure"
            starName = "Overhead arrival"
        }

        let standOrigin = StandGenerator.originStand(icao: originAirport.icao, seed: chosenSeed)
        let standDest = StandGenerator.destinationStand(icao: destinationAirport.icao, seed: chosenSeed)
        let taxiOutRoute = Self.composeTaxiRoute(from: originAirport.taxiways, seed: chosenSeed)
        let taxiInRoute = Self.composeTaxiRoute(from: destinationAirport.taxiways, seed: chosenSeed + 7)
        let depHoldingPoint = Self.pickHoldingPoint(from: depRunway.holdingPoints, defaultPoint: "A1", seed: chosenSeed)
        let arrExitTaxiway = destinationAirport.taxiways.isEmpty ? "Echo" : destinationAirport.taxiways[abs(chosenSeed + 3) % destinationAirport.taxiways.count].spoken
        let squawkCode: String = chosenProfile == .vfrLocal ? "one two zero zero" : SpokenFormFormatter.digitWords(String(4200 + (abs(chosenSeed) % 500)))

        // Mission Archetype Resolution
        let chosenArchetype: MissionArchetype
        if chosenProfile == .vfrLocal {
            let vfrArchetypes: [MissionArchetype] = [.vfrTrainingAreaAirwork, .vfrCircuitTouchAndGo]
            chosenArchetype = vfrArchetypes[abs(chosenSeed) % vfrArchetypes.count]
        } else {
            if includeAbnormal {
                let abnList: [MissionArchetype] = [.ifrGoAroundReApproach, .ifrHoldingPattern, .ifrWeatherAvoidance]
                chosenArchetype = abnList[abs(chosenSeed) % abnList.count]
            } else {
                let normalList: [MissionArchetype] = [.ifrRoutineDirect, .ifrWeatherAvoidance, .ifrAirspaceCongestion]
                chosenArchetype = normalList[abs(chosenSeed) % normalList.count]
            }
        }

        let hasWeatherDeviation = (chosenArchetype == .ifrWeatherAvoidance)
        let deviationDistance = hasWeatherDeviation ? (abs(chosenSeed) % 2 == 0 ? "one five" : "two zero") : nil
        let deviationDirection = hasWeatherDeviation ? (abs(chosenSeed) % 2 == 0 ? "left" : "right") : nil

        let missionContext = FlightMissionContext(
            missionID: UUID(),
            profile: chosenProfile,
            archetype: chosenArchetype,
            aircraftType: aircraftType,
            callsign: callsign,
            originAirport: originAirport,
            destinationAirport: destinationAirport,
            depRunway: depRunway,
            arrRunway: arrRunway,
            depWeather: depWeather,
            arrWeather: arrWeather,
            depAtisId: depAtisId,
            arrAtisId: arrAtisId,
            cruisingLevel: cruisingLevel,
            squawkCode: squawkCode,
            initialAlt: initialAlt,
            sidProcedure: sidName,
            starProcedure: starName,
            departureHeading: depHeading,
            standOrigin: standOrigin,
            standDestination: standDest,
            taxiOutRoute: taxiOutRoute,
            taxiInRoute: taxiInRoute,
            weatherDeviationDistance: deviationDistance,
            weatherDeviationDirection: deviationDirection
        )

        var phaseScripts: [PhaseScript] = []
        var globalTurn = 1

        for phase in Phase.allCases {
            let templates = try templateRepository.templates(for: phase)
            let templateMap = Dictionary(uniqueKeysWithValues: templates.map { ($0.id, $0) })
            var chain: [ScenarioTemplate] = []

            switch chosenArchetype {
            case .ifrRoutineDirect:
                switch phase {
                case .preDeparture: chain = ["PD-01", "PD-02", "PD-04", "PD-06"].compactMap { templateMap[$0] }
                case .departure: chain = ["DP-01", "DP-03", "DP-05", "DP-06"].compactMap { templateMap[$0] }
                case .enRoute: chain = ["ER-01", "ER-02", "ER-04", "ER-05"].compactMap { templateMap[$0] }
                case .arrival: chain = ["AR-01", "AR-02", "AR-04"].compactMap { templateMap[$0] }
                case .approach: chain = ["AP-01", "AP-02", "AP-06"].compactMap { templateMap[$0] }
                case .landing: chain = ["LD-01", "LD-02", "LD-03", "LD-04"].compactMap { templateMap[$0] }
                }

            case .ifrWeatherAvoidance:
                switch phase {
                case .preDeparture: chain = ["PD-01", "PD-02", "PD-04", "PD-06"].compactMap { templateMap[$0] }
                case .departure: chain = ["DP-01", "DP-04", "DP-06"].compactMap { templateMap[$0] }
                case .enRoute: chain = ["ER-01", "ER-03", "ER-02", "ER-05"].compactMap { templateMap[$0] }
                case .arrival: chain = ["AR-01", "AR-02", "AR-04"].compactMap { templateMap[$0] }
                case .approach: chain = ["AP-01", "AP-02", "AP-06"].compactMap { templateMap[$0] }
                case .landing: chain = ["LD-01", "LD-02", "LD-03", "LD-04"].compactMap { templateMap[$0] }
                }

            case .ifrAirspaceCongestion:
                switch phase {
                case .preDeparture: chain = ["PD-01", "PD-02", "PD-04", "PD-06"].compactMap { templateMap[$0] }
                case .departure: chain = ["DP-01", "DP-03", "DP-04", "DP-06"].compactMap { templateMap[$0] }
                case .enRoute: chain = ["ER-01", "ER-02", "ER-05"].compactMap { templateMap[$0] }
                case .arrival: chain = ["AR-01", "AR-02", "AR-04"].compactMap { templateMap[$0] }
                case .approach: chain = ["AP-01", "AP-08", "AP-06"].compactMap { templateMap[$0] }
                case .landing: chain = ["LD-01", "LD-02", "LD-03", "LD-04"].compactMap { templateMap[$0] }
                }

            case .ifrHoldingPattern:
                switch phase {
                case .preDeparture: chain = ["PD-01", "PD-02", "PD-04", "PD-06"].compactMap { templateMap[$0] }
                case .departure: chain = ["DP-01", "DP-03", "DP-05", "DP-06"].compactMap { templateMap[$0] }
                case .enRoute: chain = ["ER-01", "ER-02", "ER-04", "ER-05"].compactMap { templateMap[$0] }
                case .arrival: chain = ["AR-01", "AR-05", "AR-02", "AR-04"].compactMap { templateMap[$0] }
                case .approach: chain = ["AP-01", "AP-02", "AP-06"].compactMap { templateMap[$0] }
                case .landing: chain = ["LD-01", "LD-02", "LD-03", "LD-04"].compactMap { templateMap[$0] }
                }

            case .ifrGoAroundReApproach:
                switch phase {
                case .preDeparture: chain = ["PD-01", "PD-02", "PD-04", "PD-06"].compactMap { templateMap[$0] }
                case .departure: chain = ["DP-01", "DP-04", "DP-06"].compactMap { templateMap[$0] }
                case .enRoute: chain = ["ER-01", "ER-02", "ER-05"].compactMap { templateMap[$0] }
                case .arrival: chain = ["AR-01", "AR-02", "AR-04"].compactMap { templateMap[$0] }
                case .approach: chain = ["AP-01", "AP-02", "AP-07", "AP-08", "AP-06"].compactMap { templateMap[$0] }
                case .landing: chain = ["LD-01", "LD-02", "LD-03", "LD-04"].compactMap { templateMap[$0] }
                }

            case .vfrTrainingAreaAirwork:
                switch phase {
                case .preDeparture: chain = ["PD-01", "PD-03", "PD-06"].compactMap { templateMap[$0] }
                case .departure: chain = ["DP-01", "DP-05", "DP-06"].compactMap { templateMap[$0] }
                case .enRoute: chain = ["ER-01", "ER-02"].compactMap { templateMap[$0] }
                case .arrival: chain = ["AR-01", "AR-03"].compactMap { templateMap[$0] }
                case .approach: chain = ["AP-03", "AP-06"].compactMap { templateMap[$0] }
                case .landing: chain = ["LD-01", "LD-02", "LD-03", "LD-04"].compactMap { templateMap[$0] }
                }

            case .vfrCircuitTouchAndGo:
                switch phase {
                case .preDeparture: chain = ["PD-01", "PD-03", "PD-06"].compactMap { templateMap[$0] }
                case .departure: chain = ["DP-01", "DP-03", "DP-04"].compactMap { templateMap[$0] }
                case .enRoute: chain = ["ER-01"].compactMap { templateMap[$0] }
                case .arrival: chain = ["AR-01", "AR-03"].compactMap { templateMap[$0] }
                case .approach: chain = ["AP-03", "AP-06"].compactMap { templateMap[$0] }
                case .landing: chain = ["LD-01", "LD-02", "LD-03", "LD-04"].compactMap { templateMap[$0] }
                }

            case .vfrSimulatedEngineOut:
                switch phase {
                case .preDeparture: chain = ["PD-01", "PD-03", "PD-06"].compactMap { templateMap[$0] }
                case .departure: chain = ["DP-01", "DP-04", "DP-06"].compactMap { templateMap[$0] }
                case .enRoute: chain = ["ER-01"].compactMap { templateMap[$0] }
                case .arrival: chain = ["AR-01", "AR-03"].compactMap { templateMap[$0] }
                case .approach: chain = ["AP-03", "AP-07", "AP-06"].compactMap { templateMap[$0] }
                case .landing: chain = ["LD-01", "LD-02", "LD-03", "LD-04"].compactMap { templateMap[$0] }
                }
            }

            let slotContext = buildMissionSlotContext(
                missionContext: missionContext,
                phase: phase,
                depHoldingPoint: depHoldingPoint,
                arrExitTaxiway: arrExitTaxiway
            )

            var phaseExchanges: [FilledExchange] = []
            for template in chain {
                for exchange in template.exchanges {
                    let filledText = fillTemplateSlots(exchange.template, context: slotContext)
                    let resolvedCritical = resolveCriticalSlots(exchange.criticalReadback, context: slotContext)

                    let filledExchange = FilledExchange(
                        exchangeID: "\(template.id)-t\(exchange.turn)-g\(globalTurn)",
                        templateID: template.id,
                        turn: globalTurn,
                        speaker: exchange.speaker,
                        isUserTurn: exchange.isUserTurn,
                        text: filledText,
                        criticalSlots: resolvedCritical
                    )
                    phaseExchanges.append(filledExchange)
                    globalTurn += 1
                }
            }

            let title: String
            let goal: String
            switch phase {
            case .preDeparture:
                title = "Phase 1: Pre-Departure"
                goal = "Penerimaan paket ATIS, CRAFT IFR clearance / engine start, koordinasi pushback, dan izin taxi menuju holding point."
            case .departure:
                title = "Phase 2: Departure"
                goal = "Transfer frekuensi Tower, line-up and wait, izin lepas landas (take-off clearance), dan transisi airborne handoff."
            case .enRoute:
                title = "Phase 3: En-Route"
                goal = "Radar contact, position report waypoint, dynamic weather deviation (CB avoidance), dan transfer antar sektor ACC."
            case .arrival:
                title = "Phase 4: Arrival"
                goal = "Penerimaan ATIS kedatangan, clearance descent bertahap, STAR arrival routing, dan transfer ke Approach Control."
            case .approach:
                title = "Phase 5: Approach"
                goal = "Otorisasi ILS / Visual Approach, laporan established di localizer, final call Tower, dan cleared to land."
            case .landing:
                title = "Phase 6: Landing & Shutdown"
                goal = "Instruksi keluar landasan (vacate runway), transfer ke Ground, taxi menuju gate/apron, dan penutupan flight plan."
            }

            phaseScripts.append(
                PhaseScript(
                    phase: phase,
                    title: title,
                    educationalGoal: goal,
                    exchanges: phaseExchanges
                )
            )
        }

        return FlightMissionScript(
            id: UUID(),
            seed: chosenSeed,
            profile: chosenProfile,
            archetype: chosenArchetype,
            originAirport: originAirport,
            destinationAirport: destinationAirport,
            callsign: callsign,
            missionContext: missionContext,
            phaseScripts: phaseScripts
        )
    }

    private func buildMissionSlotContext(
        missionContext: FlightMissionContext,
        phase: Phase,
        depHoldingPoint: String,
        arrExitTaxiway: String
    ) -> SlotContext {
        let isArrivalOrLater = (phase == .arrival || phase == .approach || phase == .landing)
        let activeAirport = isArrivalOrLater ? missionContext.destinationAirport : missionContext.originAirport
        let activeRunway = isArrivalOrLater ? missionContext.arrRunway : missionContext.depRunway
        let activeWeather = isArrivalOrLater ? missionContext.arrWeather : missionContext.depWeather
        let activeAtis = isArrivalOrLater ? missionContext.arrAtisId : missionContext.depAtisId

        return SlotContext(
            airport: activeAirport,
            selectedRunway: activeRunway,
            holdingPoint: depHoldingPoint,
            taxiRoute: missionContext.taxiOutRoute,
            callsign: missionContext.callsign,
            weather: activeWeather,
            atisId: activeAtis,
            unitGround: activeAirport.units.ground,
            unitTower: activeAirport.units.tower,
            unitApproach: activeAirport.units.approach,
            unitDeparture: activeAirport.units.departure,
            unitDelivery: activeAirport.units.delivery,
            unitControl: activeAirport.units.center,
            stand: missionContext.standOrigin,
            aircraftType: missionContext.aircraftType,
            pob: missionContext.profile == .vfrLocal ? 2 : 168,
            airportName: activeAirport.name,
            destinationName: missionContext.destinationAirport.name,
            sidProcedure: missionContext.sidProcedure,
            starProcedure: missionContext.starProcedure,
            squawk: missionContext.squawkCode,
            depFreq: SpokenFormFormatter.frequency(missionContext.originAirport.units.departure?.frequency ?? "119.550"),
            approachFreq: SpokenFormFormatter.frequency(missionContext.destinationAirport.units.approach?.frequency ?? "119.500"),
            controlFreq: SpokenFormFormatter.frequency(missionContext.originAirport.units.center?.frequency ?? "127.900"),
            arrRunway: SpokenFormFormatter.runway(missionContext.arrRunway.designator),
            arrAtisId: missionContext.arrAtisId,
            visibility: "eight kilometres",
            cloudCondition: "scattered one thousand eight hundred feet",
            temperature: "three zero",
            dewPoint: "two five",
            turnDirection: "left",
            heading: missionContext.departureHeading,
            initialAlt: missionContext.initialAlt,
            levelStatus: "maintaining",
            currentLevel: missionContext.cruisingLevel,
            routeContext: "flight planned route via airway",
            currentPosition: "BUNTA",
            timeUTC: "zero one two zero",
            nextPosition: "DOLTA",
            nextETA: "zero one four five",
            requestedLevel: "flight level three seven zero",
            requestedDeviationDistance: missionContext.weatherDeviationDistance ?? "two zero",
            requestedDeviationDirection: missionContext.weatherDeviationDirection ?? "right",
            approvedDeviationDistance: missionContext.weatherDeviationDistance ?? "two zero",
            approvedDeviationDirection: missionContext.weatherDeviationDirection ?? "right",
            descentLevel: "altitude five thousand feet",
            holdingFix: missionContext.destinationAirport.procedures.holdings.first?.fix ?? "BLI VOR",
            holdingLevel: "seven thousand feet",
            inboundTrack: "zero niner zero",
            eat: "zero three zero five",
            goAroundReason: "traffic still on runway",
            missedAlt: "three thousand feet",
            missedInstruction: "climb straight ahead and contact Approach",
            exitDirection: "left",
            exitTaxiway: arrExitTaxiway,
            destinationStand: missionContext.standDestination,
            taxiInRoute: missionContext.taxiInRoute
        )
    }

    private func resolveContext(airport: Airport, request: ScriptRequest, callsign: String) -> SlotContext {
        let runwayHeadings = Dictionary(uniqueKeysWithValues: airport.runways.map { ($0.designator, $0.headingDegT) })
        let runwayPair = airport.runways.first?.pair ?? [airport.runways.first?.designator ?? "08"]

        let baseRwy = airport.runways.first!
        let weather = WeatherEngine.alignedWeather(
            runway: baseRwy.designator,
            heading: baseRwy.headingDegT,
            seed: request.seed
        )

        let selectedRwyDesignator = WeatherEngine.bestRunway(
            pair: runwayPair,
            headings: runwayHeadings,
            windDirection: Double(weather.windDirection),
            windSpeed: Double(weather.windSpeed)
        ).runway

        let selectedRunway = airport.runways.first(where: { $0.designator == selectedRwyDesignator }) ?? airport.runways.first!
        let atisLetter = ATISGenerator.letter(seed: request.seed)
        let aircraftType = AircraftGenerator.generate(profile: request.profile, seed: request.seed)
        let holdingPoint = Self.pickHoldingPoint(from: selectedRunway.holdingPoints, defaultPoint: "A1", seed: request.seed)
        let taxiRoute = Self.composeTaxiRoute(from: airport.taxiways, seed: request.seed)
        let stand = StandGenerator.originStand(icao: airport.icao, seed: request.seed)

        return SlotContext(
            airport: airport,
            selectedRunway: selectedRunway,
            holdingPoint: holdingPoint,
            taxiRoute: taxiRoute,
            callsign: callsign,
            weather: weather,
            atisId: atisLetter,
            unitGround: airport.units.ground,
            unitTower: airport.units.tower,
            unitApproach: airport.units.approach,
            unitDeparture: airport.units.departure,
            unitDelivery: airport.units.delivery,
            unitControl: airport.units.center,
            stand: stand,
            aircraftType: aircraftType,
            pob: request.profile == .vfrLocal ? 2 : 150,
            airportName: airport.name,
            destinationName: "Denpasar",
            sidProcedure: airport.procedures.sids.first?.name ?? "DOLTA One Alfa",
            starProcedure: airport.procedures.stars.first?.name ?? "ELANG One Alfa",
            squawk: "four two one five",
            depFreq: SpokenFormFormatter.frequency(airport.units.departure?.frequency ?? "119.550"),
            approachFreq: SpokenFormFormatter.frequency(airport.units.approach?.frequency ?? "119.500"),
            controlFreq: SpokenFormFormatter.frequency(airport.units.center?.frequency ?? "127.900"),
            arrRunway: SpokenFormFormatter.runway(selectedRunway.designator),
            arrAtisId: "Mike",
            visibility: "eight kilometres",
            cloudCondition: "scattered one thousand eight hundred feet",
            temperature: "three zero",
            dewPoint: "two five",
            turnDirection: "left",
            heading: Int(selectedRunway.headingDegT),
            initialAlt: "altitude four thousand feet",
            levelStatus: "maintaining",
            currentLevel: "flight level one five zero",
            routeContext: "direct DOLTA",
            currentPosition: "BUNTA",
            timeUTC: "zero three one zero",
            nextPosition: "DOLTA",
            nextETA: "zero three four zero",
            requestedLevel: "flight level one niner zero",
            requestedDeviationDistance: "two zero",
            requestedDeviationDirection: "right",
            approvedDeviationDistance: "two zero",
            approvedDeviationDirection: "right",
            descentLevel: "altitude five thousand feet",
            holdingFix: airport.procedures.holdings.first?.fix ?? "BLI",
            holdingLevel: "seven thousand feet",
            inboundTrack: "zero niner zero",
            eat: "zero three zero five",
            goAroundReason: "traffic still on runway",
            missedAlt: "three thousand feet",
            missedInstruction: "contact Approach",
            exitDirection: "left",
            exitTaxiway: airport.taxiways.first?.spoken ?? "Bravo",
            destinationStand: stand,
            taxiInRoute: taxiRoute
        )
    }

    private func buildTemplateChain(
        availableTemplates: [ScenarioTemplate],
        request: ScriptRequest,
        context: SlotContext
    ) -> [ScenarioTemplate] {
        let templateMap = Dictionary(uniqueKeysWithValues: availableTemplates.map { ($0.id, $0) })

        switch request.phase {
        case .preDeparture:
            let ids = ["PD-01", "PD-03", "PD-06"]
            return ids.compactMap { templateMap[$0] }

        case .departure:
            let ids = ["DP-01", "DP-03", "DP-04", "DP-06"]
            return ids.compactMap { templateMap[$0] }

        case .enRoute:
            let ids = ["ER-01", "ER-02", "ER-03", "ER-05"]
            return ids.compactMap { templateMap[$0] }

        case .arrival:
            if request.includeAbnormal || request.forcedEventID == "ABN-05" {
                return ["AR-01", "AR-05", "AR-02", "AR-04"].compactMap { templateMap[$0] }
            }
            return ["AR-01", "AR-02", "AR-04"].compactMap { templateMap[$0] }

        case .approach:
            if request.includeAbnormal || request.forcedEventID == "ABN-06" {
                return ["AP-01", "AP-02", "AP-07", "AP-08", "AP-06"].compactMap { templateMap[$0] }
            }
            return ["AP-01", "AP-02", "AP-06"].compactMap { templateMap[$0] }

        case .landing:
            return ["LD-01", "LD-02", "LD-03", "LD-04"].compactMap { templateMap[$0] }
        }
    }

    private func fillTemplateSlots(_ template: String, context: SlotContext) -> String {
        var text = template

        let spokenRwy = SpokenFormFormatter.runway(context.selectedRunway.designator)
        let spokenQnh = SpokenFormFormatter.qnh(context.weather.qnh)
        let spokenWindHdg = SpokenFormFormatter.heading(context.weather.windDirection)
        let spokenWindSpd = SpokenFormFormatter.digitWords(String(context.weather.windSpeed))
        let groundFreq = SpokenFormFormatter.frequency(context.unitGround?.frequency ?? "121.600")
        let towerFreq = SpokenFormFormatter.frequency(context.unitTower?.frequency ?? "118.100")
        let spokenHdg = SpokenFormFormatter.heading(context.heading)

        // Clean double "stand" bug
        let cleanStand = context.stand.replacingOccurrences(of: "stand ", with: "", options: [.caseInsensitive])
        let cleanDestStand = context.destinationStand.replacingOccurrences(of: "stand ", with: "", options: [.caseInsensitive])

        let replacements: [String: String] = [
            "{AIRPORT_NAME}": context.airportName,
            "{DESTINATION_NAME}": context.destinationName,
            "{CALLSIGN}": context.callsign,
            "{RUNWAY}": spokenRwy,
            "{ARR_RUNWAY}": context.arrRunway,
            "{UNIT_GROUND}": context.unitGround?.callsign ?? "Ground",
            "{UNIT_TOWER}": context.unitTower?.callsign ?? "Tower",
            "{UNIT_CONTROL}": context.unitControl?.callsign ?? "Control",
            "{UNIT_DELIVERY}": context.unitDelivery?.callsign ?? "Delivery",
            "{UNIT_DEPARTURE}": context.unitDeparture?.callsign ?? "Departure",
            "{UNIT_APPROACH}": context.unitApproach?.callsign ?? "Approach",
            "{GROUND_FREQ}": groundFreq,
            "{TOWER_FREQ}": towerFreq,
            "{DEP_FREQ}": context.depFreq,
            "{APPROACH_FREQ}": context.approachFreq,
            "{CONTROL_FREQ}": context.controlFreq,
            "{HOLDING_POINT}": context.holdingPoint,
            "{TAXI_ROUTE}": context.taxiRoute,
            "{QNH}": spokenQnh,
            "{WIND_DIRECTION}": spokenWindHdg,
            "{WIND_SPEED}": spokenWindSpd,
            "{ATIS_ID}": context.atisId,
            "{ARR_ATIS_ID}": context.arrAtisId,
            "{VISIBILITY}": context.visibility,
            "{CLOUD_CONDITION}": context.cloudCondition,
            "{TEMPERATURE}": context.temperature,
            "{DEW_POINT}": context.dewPoint,
            "{STAND}": cleanStand,
            "{AIRCRAFT_TYPE}": context.aircraftType,
            "{POB}": String(context.pob),
            "{SID_PROCEDURE}": context.sidProcedure,
            "{STAR_PROCEDURE}": context.starProcedure,
            "{SQUAWK}": context.squawk,
            "{TURN_DIRECTION}": context.turnDirection,
            "{PUSHBACK_DIRECTION}": context.turnDirection == "left" ? "west" : "east",
            "{HEADING}": spokenHdg,
            "{INITIAL_ALT}": context.initialAlt,
            "{PASSING_ALT}": "one thousand five hundred feet",
            "{CLIMBING_ALT}": context.initialAlt,
            "{DEPARTURE_ROUTING}": context.sidProcedure,
            "{ASSIGNED_ALT}": context.currentLevel,
            "{LEVEL_STATUS}": context.levelStatus,
            "{CURRENT_LEVEL}": context.currentLevel,
            "{ROUTE_CONTEXT}": context.routeContext,
            "{CURRENT_POSITION}": context.currentPosition,
            "{TIME_UTC}": context.timeUTC,
            "{NEXT_POSITION}": context.nextPosition,
            "{NEXT_ETA}": context.nextETA,
            "{REQUESTED_LEVEL}": context.requestedLevel,
            "{REQUESTED_DEVIATION_DISTANCE}": context.requestedDeviationDistance,
            "{REQUESTED_DEVIATION_DIRECTION}": context.requestedDeviationDirection,
            "{APPROVED_DEVIATION_DISTANCE}": context.approvedDeviationDistance,
            "{APPROVED_DEVIATION_DIRECTION}": context.approvedDeviationDirection,
            "{DESCENT_LEVEL}": context.descentLevel,
            "{HOLDING_FIX}": context.holdingFix,
            "{HOLDING_LEVEL}": context.holdingLevel,
            "{INBOUND_TRACK}": context.inboundTrack,
            "{EAT}": context.eat,
            "{GO_AROUND_REASON}": context.goAroundReason,
            "{MISSED_ALT}": context.missedAlt,
            "{MISSED_INSTRUCTION}": context.missedInstruction,
            "{DOWNWIND_HEADING}": "two seven zero",
            "{INTERCEPT_ALT}": "two thousand five hundred feet",
            "{EXIT_DIRECTION}": context.exitDirection,
            "{EXIT_TAXIWAY}": context.exitTaxiway,
            "{DESTINATION_STAND}": "stand \(cleanDestStand)",
            "{TAXI_IN_ROUTE}": context.taxiInRoute
        ]

        for (slot, value) in replacements {
            text = text.replacingOccurrences(of: slot, with: value)
        }
        return text
    }

    private func resolveCriticalSlots(
        _ rules: [CriticalReadbackRule],
        context: SlotContext
    ) -> [CriticalSlot] {
        let cleanStand = context.stand.replacingOccurrences(of: "stand ", with: "", options: [.caseInsensitive])
        let cleanDestStand = context.destinationStand.replacingOccurrences(of: "stand ", with: "", options: [.caseInsensitive])

        return rules.map { rule in
            let expectedValue: String
            switch rule.slot {
            case "RUNWAY":
                expectedValue = SpokenFormFormatter.runway(context.selectedRunway.designator)
            case "ARR_RUNWAY":
                expectedValue = context.arrRunway
            case "TOWER_FREQ":
                expectedValue = SpokenFormFormatter.frequency(context.unitTower?.frequency ?? "118.100")
            case "GROUND_FREQ":
                expectedValue = SpokenFormFormatter.frequency(context.unitGround?.frequency ?? "121.600")
            case "DEP_FREQ":
                expectedValue = context.depFreq
            case "APPROACH_FREQ":
                expectedValue = context.approachFreq
            case "CONTROL_FREQ":
                expectedValue = context.controlFreq
            case "LINE_UP_WAIT":
                expectedValue = rule.keyword ?? "line up and wait"
            case "TAKEOFF_CLEARANCE":
                expectedValue = rule.keyword ?? "cleared for take-off"
            case "CLEARED_TO_LAND":
                expectedValue = rule.keyword ?? "cleared to land"
            case "GOING_AROUND":
                expectedValue = rule.keyword ?? "going around"
            case "APPROVAL":
                expectedValue = rule.keyword ?? "start-up approved"
            case "HOLD_SHORT_RUNWAY":
                expectedValue = rule.keyword ?? "hold short runway"
            case "CALLSIGN":
                expectedValue = context.callsign
            case "QNH":
                expectedValue = SpokenFormFormatter.qnh(context.weather.qnh)
            case "ATIS_ID":
                expectedValue = context.atisId
            case "ARR_ATIS_ID":
                expectedValue = context.arrAtisId
            case "DESTINATION_NAME":
                expectedValue = context.destinationName
            case "SID_PROCEDURE":
                expectedValue = context.sidProcedure
            case "STAR_PROCEDURE":
                expectedValue = context.starProcedure
            case "SQUAWK":
                expectedValue = context.squawk
            case "HOLDING_POINT":
                expectedValue = context.holdingPoint
            case "TAXI_ROUTE":
                expectedValue = context.taxiRoute
            case "HEADING":
                expectedValue = SpokenFormFormatter.heading(context.heading)
            case "INITIAL_ALT":
                expectedValue = context.initialAlt
            case "TURN_DIRECTION":
                expectedValue = context.turnDirection
            case "CURRENT_LEVEL":
                expectedValue = context.currentLevel
            case "CURRENT_POSITION":
                expectedValue = context.currentPosition
            case "TIME_UTC":
                expectedValue = context.timeUTC
            case "NEXT_POSITION":
                expectedValue = context.nextPosition
            case "NEXT_ETA":
                expectedValue = context.nextETA
            case "DOWNWIND_HEADING":
                expectedValue = "two seven zero"
            case "INTERCEPT_ALT":
                expectedValue = "two thousand five hundred feet"
            case "DESCENT_LEVEL":
                expectedValue = context.descentLevel
            case "HOLDING_FIX":
                expectedValue = context.holdingFix
            case "HOLDING_LEVEL":
                expectedValue = context.holdingLevel
            case "INBOUND_TRACK":
                expectedValue = context.inboundTrack
            case "EAT":
                expectedValue = context.eat
            case "MISSED_ALT":
                expectedValue = context.missedAlt
            case "MISSED_INSTRUCTION":
                expectedValue = context.missedInstruction
            case "EXIT_TAXIWAY":
                expectedValue = context.exitTaxiway
            case "STAND":
                expectedValue = cleanStand
            case "DESTINATION_STAND":
                expectedValue = "stand \(cleanDestStand)"
            case "TAXI_IN_ROUTE":
                expectedValue = context.taxiInRoute
            case "APPROVED_DEVIATION_DISTANCE":
                expectedValue = context.approvedDeviationDistance
            case "APPROVED_DEVIATION_DIRECTION":
                expectedValue = context.approvedDeviationDirection
            default:
                expectedValue = rule.keyword ?? rule.slot
            }

            return CriticalSlot(
                slot: rule.slot,
                expectedValue: expectedValue,
                type: rule.type,
                position: rule.position
            )
        }
    }

    // MARK: - Combination Helpers
    private static func composeTaxiRoute(from taxiways: [Taxiway], seed: Int) -> String {
        guard !taxiways.isEmpty else { return "Alfa" }
        if taxiways.count == 1 {
            return taxiways[0].spoken
        }
        if abs(seed) % 2 == 0 && taxiways.count >= 2 {
            let idx1 = abs(seed) % taxiways.count
            var idx2 = abs(seed + 1) % taxiways.count
            if idx1 == idx2 { idx2 = (idx1 + 1) % taxiways.count }
            return "\(taxiways[idx1].spoken) and \(taxiways[idx2].spoken)"
        }
        return taxiways[abs(seed) % taxiways.count].spoken
    }

    private static func pickStand(from stands: [Stand], defaultStand: String, seed: Int) -> String {
        guard !stands.isEmpty else { return defaultStand }
        return stands[abs(seed) % stands.count].spoken
    }

    private static func pickHoldingPoint(from holdingPoints: [String], defaultPoint: String, seed: Int) -> String {
        guard !holdingPoints.isEmpty else { return defaultPoint }
        return holdingPoints[abs(seed) % holdingPoints.count]
    }

    // MARK: - Level-Based Mission Generator (5 Progressive Curriculum Levels)
    public func generateLevelMission(
        level: CurriculumLevel,
        role: UserRole = .pilot,
        mode: SimulationMode = .practice,
        seed: Int? = nil,
        selectedContingencies: Set<ContingencySelection>
    ) throws -> FlightMissionScript {
        let chosenSeed = seed ?? Int.random(in: 1000...9999)
        let originAirport = try airportRepository.airport(icao: level.originICAO)
        let destinationAirport = try airportRepository.airport(icao: level.destinationICAO)

        let profile = level.defaultProfile
        let callsign = CallsignGenerator.generate(profile: profile, seed: chosenSeed)
        let aircraftType = AircraftGenerator.generate(profile: profile, level: level, seed: chosenSeed)

        // Dynamic Wind and Runways for Origin
        let depRwyHeadings = Dictionary(uniqueKeysWithValues: originAirport.runways.map { ($0.designator, $0.headingDegT) })
        let depRwyPair = originAirport.runways.first?.pair ?? [originAirport.runways.first?.designator ?? "08"]
        let depWeather = WeatherEngine.alignedWeather(
            runway: originAirport.runways.first?.designator ?? "08",
            heading: originAirport.runways.first?.headingDegT ?? 80,
            seed: chosenSeed
        )
        let depRwyDesignator = WeatherEngine.bestRunway(
            pair: depRwyPair,
            headings: depRwyHeadings,
            windDirection: Double(depWeather.windDirection),
            windSpeed: Double(depWeather.windSpeed)
        ).runway
        let depRunway = originAirport.runways.first(where: { $0.designator == depRwyDesignator }) ?? originAirport.runways.first!

        // Destination Runways
        let arrRwyHeadings = Dictionary(uniqueKeysWithValues: destinationAirport.runways.map { ($0.designator, $0.headingDegT) })
        let arrRwyPair = destinationAirport.runways.first?.pair ?? [destinationAirport.runways.first?.designator ?? "09"]
        let arrWeather = WeatherEngine.alignedWeather(
            runway: destinationAirport.runways.first?.designator ?? "09",
            heading: destinationAirport.runways.first?.headingDegT ?? 90,
            seed: chosenSeed + 101
        )
        let arrRwyDesignator = WeatherEngine.bestRunway(
            pair: arrRwyPair,
            headings: arrRwyHeadings,
            windDirection: Double(arrWeather.windDirection),
            windSpeed: Double(arrWeather.windSpeed)
        ).runway
        let arrRunway = destinationAirport.runways.first(where: { $0.designator == arrRwyDesignator }) ?? destinationAirport.runways.first!

        let depAtisId = ATISGenerator.letter(seed: chosenSeed)
        let arrAtisId = ATISGenerator.letter(seed: chosenSeed + 5)
        let depHeading = Int(depRunway.headingDegT)

        // Level-specific Flight Level & Procedures
        let cruisingLevel: String
        let initialAlt: String
        switch level {
        case .level1:
            cruisingLevel = "three thousand feet"
            initialAlt = "two thousand five hundred feet"
        case .level2:
            cruisingLevel = "flight level zero eight zero"
            initialAlt = "altitude four thousand feet"
        case .level3:
            cruisingLevel = "flight level two four zero"
            initialAlt = "flight level one zero zero"
        case .level4:
            cruisingLevel = "flight level two eight zero"
            initialAlt = "flight level one zero zero"
        case .level5:
            cruisingLevel = "flight level three six zero"
            initialAlt = "flight level one zero zero"
        }

        let sidName = level.sidName
        let starName = level.starName

        let standOrigin = StandGenerator.originStand(icao: originAirport.icao, seed: chosenSeed)
        let standDest = StandGenerator.destinationStand(icao: destinationAirport.icao, seed: chosenSeed)
        let taxiOutRoute = Self.composeTaxiRoute(from: originAirport.taxiways, seed: chosenSeed)
        let taxiInRoute = Self.composeTaxiRoute(from: destinationAirport.taxiways, seed: chosenSeed + 7)
        let depHoldingPoint = Self.pickHoldingPoint(from: depRunway.holdingPoints, defaultPoint: "A1", seed: chosenSeed)

        // Dynamic Exit Taxiway and Direction based on Airport & Runway orientation
        let exitInfo = resolveExitTaxiwayAndDirection(
            airport: destinationAirport,
            runwayDesignator: arrRunway.designator,
            seed: chosenSeed
        )
        let arrExitTaxiway = exitInfo.taxiway
        let arrExitDirection = exitInfo.direction

        let squawkCode: String = profile == .vfrLocal ? "one two zero zero" : SpokenFormFormatter.digitWords(String(4200 + (abs(chosenSeed) % 500)))

        // Multi-Contingency Resolution with Independent 50% Dice Roll per Selected Item
        let chosenContingencies: [InjectedContingency] = resolveMultipleContingencies(
            selectedOptions: selectedContingencies,
            level: level,
            seed: chosenSeed
        )

        let archetype: MissionArchetype
        if chosenContingencies.contains(where: { $0.severity == .distress }) {
            archetype = (level == .level1) ? .vfrSimulatedEngineOut : .ifrGoAroundReApproach
        } else if chosenContingencies.contains(where: { $0.severity == .urgency }) {
            archetype = (level == .level3) ? .ifrHoldingPattern : .ifrWeatherAvoidance
        } else if chosenContingencies.contains(where: { $0.severity == .abnormal }) {
            archetype = .ifrAirspaceCongestion
        } else {
            archetype = (level == .level1) ? .vfrCircuitTouchAndGo : .ifrRoutineDirect
        }

        let hasWeatherDeviation = chosenContingencies.contains(where: { $0.title.contains("Weather") })
        let deviationDistance = hasWeatherDeviation ? "one five" : nil
        let deviationDirection = hasWeatherDeviation ? "right" : nil

        let missionContext = FlightMissionContext(
            missionID: UUID(),
            profile: profile,
            archetype: archetype,
            aircraftType: aircraftType,
            callsign: callsign,
            originAirport: originAirport,
            destinationAirport: destinationAirport,
            depRunway: depRunway,
            arrRunway: arrRunway,
            depWeather: depWeather,
            arrWeather: arrWeather,
            depAtisId: depAtisId,
            arrAtisId: arrAtisId,
            cruisingLevel: cruisingLevel,
            squawkCode: squawkCode,
            initialAlt: initialAlt,
            sidProcedure: sidName,
            starProcedure: starName,
            departureHeading: depHeading,
            standOrigin: standOrigin,
            standDestination: standDest,
            taxiOutRoute: taxiOutRoute,
            taxiInRoute: taxiInRoute,
            weatherDeviationDistance: deviationDistance,
            weatherDeviationDirection: deviationDirection
        )

        var phaseScripts: [PhaseScript] = []
        var globalTurn = 1

        // Mutatable runtime state across phases
        var activeDepRunway = depRunway
        var activeHoldingPoint = depHoldingPoint
        var activeWeather = depWeather
        var isFlightTerminatedEarly = false
        var executedContingencies: [InjectedContingency] = []

        for phase in Phase.allCases {
            // Create Slot Context with dynamic mutated state & exit parameters
            let depExit = originAirport.taxiways.first?.spoken ?? "Alfa"
            let slotContext = buildMissionSlotContext(
                missionContext: missionContext,
                phase: phase,
                depHoldingPoint: activeHoldingPoint,
                arrExitTaxiway: isFlightTerminatedEarly ? depExit : arrExitTaxiway,
                exitDirection: isFlightTerminatedEarly ? "left" : arrExitDirection,
                customDepRunway: activeDepRunway,
                customWeather: activeWeather,
                isEarlyTerminatedOnGround: isFlightTerminatedEarly
            )

            var phaseExchanges: [FilledExchange] = []
            var title: String = ""
            var goal: String = ""

            if isFlightTerminatedEarly && phase != .preDeparture && phase != .departure {
                // ADAPTIVE NON-EMPTY PHASES FOR GROUND/ABORTED CONTINGENCIES
                let termCont = executedContingencies.first(where: { $0.title.contains("Abort") || $0.title.contains("EFATO") })
                let adaptive = buildTerminatedEarlyPhaseExchanges(
                    phase: phase,
                    contingency: termCont,
                    context: slotContext,
                    role: role,
                    currentGlobalTurn: &globalTurn
                )
                phaseExchanges = adaptive.exchanges
                title = adaptive.title
                goal = adaptive.goal
            } else {
                phaseExchanges = buildDynamicPhaseExchanges(
                    phase: phase,
                    level: level,
                    seed: chosenSeed,
                    role: role,
                    context: slotContext,
                    contingencies: chosenContingencies,
                    activeDepRunway: &activeDepRunway,
                    activeHoldingPoint: &activeHoldingPoint,
                    activeWeather: &activeWeather,
                    isFlightTerminatedEarly: &isFlightTerminatedEarly,
                    executedContingencies: &executedContingencies,
                    globalTurn: &globalTurn
                )

                switch phase {
                case .preDeparture:
                    title = "Phase 1: Pre-Departure"
                    goal = "Penerimaan ATIS, \(level == .level1 ? "Engine start & local brief" : "IFR route clearance via \(sidName)"), pushback & taxi hold short."
                case .departure:
                    title = "Phase 2: Departure"
                    goal = isFlightTerminatedEarly
                        ? "Handoff Tower, take-off roll, dan penanganan kondisi darurat sebelum/sesaat setelah airborne."
                        : "Handoff Tower, \(level == .level1 ? "circuit ready call" : "conditional line-up"), take-off clearance, dan airborne handoff."
                case .enRoute:
                    title = "Phase 3: En-Route"
                    goal = "Radar contact, position report over waypoint, cruising level \(cruisingLevel), transfer sektor."
                case .arrival:
                    title = "Phase 4: Arrival"
                    goal = "Penerimaan ATIS kedatangan, descent clearance, rute \(starName), transfer Approach."
                case .approach:
                    title = "Phase 5: Approach"
                    goal = "\(level == .level1 ? "Visual circuit report (downwind/final)" : "ILS approach established report"), cleared to land."
                case .landing:
                    title = "Phase 6: Landing & Shutdown"
                    goal = "Vacate runway via \(arrExitTaxiway) (\(arrExitDirection)), transfer Ground, taxi in ke \(standDest), penutupan flight plan."
                }
            }

            phaseScripts.append(
                PhaseScript(
                    phase: phase,
                    title: title,
                    educationalGoal: goal,
                    exchanges: phaseExchanges
                )
            )
        }

        // Generate Diagnostic Report
        let diagScore = 80 + (abs(chosenSeed) % 18)
        let readbackAcc = 85 + (abs(chosenSeed) % 15)
        let phraseScore = 82 + (abs(chosenSeed) % 16)
        let discScore = 80 + (abs(chosenSeed) % 17)
        let isPass = diagScore >= 80

        let report = DiagnosticReport(
            overallScore: diagScore,
            readbackAccuracyPercent: readbackAcc,
            phraseologyScorePercent: phraseScore,
            disciplineScorePercent: discScore,
            isPassed: isPass,
            summaryFeedback: isPass
                ? "Selamat! Anda memenuhi standar kecakapan ICAO (skor \(diagScore)%). Kelayakan prosedur navigasi dan readback keselamatan terpenuhi."
                : "Skor Anda \(diagScore)%. Tingkatkan akurasi pembacaan kembali angka keselamatan kritis dan tempo transmisi.",
            improvementAreas: [
                "Pastikan nomor runway selalu diucapkan di awal readback izin take-off / landing.",
                "Perhatikan instruksi STOP IMMEDIATELY dan konfirmasi status 'stopping/aborting take-off' tanpa jeda.",
                "Gunakan istilah baku ICAO tanpa penambahan filler kata santai."
            ]
        )

        return FlightMissionScript(
            id: UUID(),
            seed: chosenSeed,
            level: level,
            role: role,
            mode: mode,
            profile: profile,
            archetype: archetype,
            originAirport: originAirport,
            destinationAirport: destinationAirport,
            callsign: callsign,
            missionContext: missionContext,
            phaseScripts: phaseScripts,
            diagnosticReport: report,
            contingencies: executedContingencies
        )
    }

    // Overload: Single contingency selection
    public func generateLevelMission(
        level: CurriculumLevel,
        role: UserRole = .pilot,
        mode: SimulationMode = .practice,
        seed: Int? = nil,
        contingencyOption: ContingencySelection = .auto
    ) throws -> FlightMissionScript {
        let set: Set<ContingencySelection>
        if contingencyOption == .auto {
            set = Set(level.allowedScenarios)
        } else if contingencyOption == .routineOnly {
            set = []
        } else {
            set = [contingencyOption]
        }
        return try generateLevelMission(
            level: level,
            role: role,
            mode: mode,
            seed: seed,
            selectedContingencies: set
        )
    }

    // Overload for backward compatibility
    public func generateLevelMission(
        level: CurriculumLevel,
        role: UserRole = .pilot,
        mode: SimulationMode = .practice,
        seed: Int? = nil,
        forceEmergency: Bool
    ) throws -> FlightMissionScript {
        return try generateLevelMission(
            level: level,
            role: role,
            mode: mode,
            seed: seed,
            contingencyOption: forceEmergency ? .abortTakeoff : .auto
        )
    }

    private func buildMissionSlotContext(
        missionContext: FlightMissionContext,
        phase: Phase,
        depHoldingPoint: String,
        arrExitTaxiway: String,
        exitDirection: String = "left",
        customDepRunway: Runway? = nil,
        customWeather: AlignedWeather? = nil,
        isEarlyTerminatedOnGround: Bool = false
    ) -> SlotContext {
        let isArrivalOrLater = (!isEarlyTerminatedOnGround) && (phase == .arrival || phase == .approach || phase == .landing)
        let activeAirport = isArrivalOrLater ? missionContext.destinationAirport : missionContext.originAirport
        let activeRunway = isArrivalOrLater ? missionContext.arrRunway : (customDepRunway ?? missionContext.depRunway)
        let activeWeather = isArrivalOrLater ? missionContext.arrWeather : (customWeather ?? missionContext.depWeather)
        let activeAtis = isArrivalOrLater ? missionContext.arrAtisId : missionContext.depAtisId

        let waypoints: (curr: String, next: String)
        switch missionContext.originAirport.icao {
        case "WADY": waypoints = ("Point Alfa", "Point Charlie")
        case "WADD": waypoints = ("POSOP", "BLI VOR")
        case "WARR": waypoints = ("SURBA", "GANDI")
        case "WAHI": waypoints = ("JOG VOR", "PRAMB")
        case "WIII": waypoints = ("BUNTA", "DOLTA")
        default: waypoints = ("BUNTA", "DOLTA")
        }

        return SlotContext(
            airport: activeAirport,
            selectedRunway: activeRunway,
            holdingPoint: depHoldingPoint,
            taxiRoute: missionContext.taxiOutRoute,
            callsign: missionContext.callsign,
            weather: activeWeather,
            atisId: activeAtis,
            unitGround: activeAirport.units.ground,
            unitTower: activeAirport.units.tower,
            unitApproach: activeAirport.units.approach,
            unitDeparture: activeAirport.units.departure,
            unitDelivery: activeAirport.units.delivery,
            unitControl: activeAirport.units.center,
            stand: missionContext.standOrigin,
            aircraftType: missionContext.aircraftType,
            pob: missionContext.profile == .vfrLocal ? 2 : 168,
            airportName: activeAirport.name,
            destinationName: missionContext.destinationAirport.name,
            sidProcedure: missionContext.sidProcedure,
            starProcedure: missionContext.starProcedure,
            squawk: missionContext.squawkCode,
            depFreq: SpokenFormFormatter.frequency(missionContext.originAirport.units.departure?.frequency ?? "119.550"),
            approachFreq: SpokenFormFormatter.frequency(missionContext.destinationAirport.units.approach?.frequency ?? "119.500"),
            controlFreq: SpokenFormFormatter.frequency(missionContext.originAirport.units.center?.frequency ?? "127.900"),
            arrRunway: SpokenFormFormatter.runway(missionContext.arrRunway.designator),
            arrAtisId: missionContext.arrAtisId,
            visibility: "eight kilometres",
            cloudCondition: "scattered one thousand eight hundred feet",
            temperature: "three zero",
            dewPoint: "two five",
            turnDirection: "left",
            heading: missionContext.departureHeading,
            initialAlt: missionContext.initialAlt,
            levelStatus: "maintaining",
            currentLevel: missionContext.cruisingLevel,
            routeContext: "flight planned route via airway",
            currentPosition: waypoints.curr,
            timeUTC: "zero one two zero",
            nextPosition: waypoints.next,
            nextETA: "zero one four five",
            requestedLevel: "flight level three seven zero",
            requestedDeviationDistance: missionContext.weatherDeviationDistance ?? "two zero",
            requestedDeviationDirection: missionContext.weatherDeviationDirection ?? "right",
            approvedDeviationDistance: missionContext.weatherDeviationDistance ?? "two zero",
            approvedDeviationDirection: missionContext.weatherDeviationDirection ?? "right",
            descentLevel: "altitude five thousand feet",
            holdingFix: missionContext.destinationAirport.procedures.holdings.first?.fix ?? "BLI VOR",
            holdingLevel: "seven thousand feet",
            inboundTrack: "zero niner zero",
            eat: "zero three zero five",
            goAroundReason: "traffic still on runway",
            missedAlt: "three thousand feet",
            missedInstruction: "climb straight ahead and contact Approach",
            exitDirection: exitDirection,
            exitTaxiway: arrExitTaxiway,
            destinationStand: missionContext.standDestination,
            taxiInRoute: missionContext.taxiInRoute
        )
    }

    // MARK: - Dynamic Exit Taxiway & Direction Resolution
    private func resolveExitTaxiwayAndDirection(
        airport: Airport,
        runwayDesignator: String,
        seed: Int
    ) -> (taxiway: String, direction: String) {
        let cleanRwy = runwayDesignator.trimmingCharacters(in: .whitespaces)

        switch airport.icao {
        case "WADD":
            if cleanRwy.contains("09") {
                let options = ["Charlie One", "Charlie Three", "Bravo One", "Echo"]
                return (options[abs(seed) % options.count], "left")
            } else {
                let options = ["Charlie Two", "Delta", "Foxtrot"]
                return (options[abs(seed) % options.count], "right")
            }
        case "WARR":
            if cleanRwy.contains("10") {
                let options = ["November Three", "November One", "Bravo"]
                return (options[abs(seed) % options.count], "left")
            } else {
                let options = ["November Four", "November Six"]
                return (options[abs(seed) % options.count], "right")
            }
        case "WAHI":
            if cleanRwy.contains("11") {
                let options = ["Bravo", "Charlie"]
                return (options[abs(seed) % options.count], "left")
            } else {
                let options = ["Delta", "Echo"]
                return (options[abs(seed) % options.count], "right")
            }
        case "WIII":
            if cleanRwy.contains("25R") {
                let options = ["November Four", "November Five", "November Six"]
                return (options[abs(seed) % options.count], "left")
            } else if cleanRwy.contains("07L") {
                let options = ["November Six", "November Seven"]
                return (options[abs(seed) % options.count], "right")
            } else if cleanRwy.contains("25L") {
                let options = ["Sierra Four", "Sierra Five"]
                return (options[abs(seed) % options.count], "right")
            } else {
                let options = ["Sierra Six", "Sierra Seven"]
                return (options[abs(seed) % options.count], "left")
            }
        default:
            if cleanRwy.contains("08") {
                let options = ["Bravo", "Alfa Two"]
                return (options[abs(seed) % options.count], "left")
            } else {
                let options = ["Alfa", "Alfa One"]
                return (options[abs(seed) % options.count], "right")
            }
        }
    }

    // MARK: - Multi-Contingency Resolution Engine (Fair Pedagogical Distribution)
    private func resolveMultipleContingencies(
        selectedOptions: Set<ContingencySelection>,
        level: CurriculumLevel,
        seed: Int
    ) -> [InjectedContingency] {
        var optionsToEvaluate: [ContingencySelection] = []

        if selectedOptions.contains(.auto) {
            optionsToEvaluate = level.allowedScenarios
        } else if selectedOptions.contains(.routineOnly) || selectedOptions.isEmpty {
            return []
        } else {
            optionsToEvaluate = level.allowedScenarios.filter { selectedOptions.contains($0) }
        }

        if optionsToEvaluate.isEmpty {
            return []
        }

        // CASE A: User manually picked a specific subset in the picker sheet (Targeted Drill Mode)
        let isUserCustomSubset = selectedOptions.count < level.allowedScenarios.count

        if isUserCustomSubset {
            // When the user deliberately selects specific scenarios to practice, guarantee they trigger!
            // If 1 scenario is chosen, trigger it 100%. If multiple are chosen, pick between them deterministically.
            let pickedIndex = abs(seed) % optionsToEvaluate.count
            return sanitizeRolledContingencies([optionsToEvaluate[pickedIndex]])
        }

        // CASE B: DEFAULT "ALL SCENARIOS ACTIVE" — FAIR PEDAGOGICAL FLIGHT DISTRIBUTION
        // Distribution per 10 seeds:
        // - 40% (Seed mod 10 in 0, 1, 2, 3) : ROUTINE FLIGHT (100% normal end-to-end flight, zero contingencies)
        // - 50% (Seed mod 10 in 4, 5, 6, 7, 8) : SINGLE FOCUSED CONTINGENCY FLIGHT (1 realistic level-appropriate scenario)
        // - 10% (Seed mod 10 == 9)            : DUAL COHERENT CONTINGENCY FLIGHT (max 2 non-conflicting minor events)

        let rollCategory = abs(seed) % 10

        // 1. Routine Flight (40% Probability: End-to-End Clean Flight)
        if rollCategory < 4 {
            return []
        }

        // 2. Dual Contingency Flight (10% Probability)
        if rollCategory == 9 {
            let preDep = optionsToEvaluate.filter { $0.triggerPhase == .preDeparture }
            let airborne = optionsToEvaluate.filter { $0.triggerPhase != .preDeparture && $0.triggerPhase != .departure }

            var dualRolled: [ContingencySelection] = []
            if !preDep.isEmpty {
                let idx1 = abs(seed &* 31) % preDep.count
                dualRolled.append(preDep[idx1])
            }
            if !airborne.isEmpty {
                let idx2 = abs(seed &* 47) % airborne.count
                dualRolled.append(airborne[idx2])
            }
            let fallback = [optionsToEvaluate[abs(seed) % optionsToEvaluate.count]]
            return sanitizeRolledContingencies(dualRolled.isEmpty ? fallback : dualRolled)
        }

        // 3. Single Focused Contingency Flight (50% Probability)
        var pool = optionsToEvaluate

        // Ensure take-off aborts don't dominate Level 1 and Level 5:
        // Only 1 in 6 contingency seeds (approx 16%) is eligible for abort
        let abortItems: [ContingencySelection] = [.abortTakeoff, .birdStrikeAbort, .efato]
        let isAbortEligible = (abs(seed / 10) % 6 == 0)
        if !isAbortEligible {
            pool.removeAll(where: { abortItems.contains($0) })
        }

        if pool.isEmpty {
            pool = optionsToEvaluate
        }

        let chosenIndex = abs(seed &* 43) % pool.count
        return sanitizeRolledContingencies([pool[chosenIndex]])
    }

    private func sanitizeRolledContingencies(_ rawRolled: [ContingencySelection]) -> [InjectedContingency] {
        var rolled = rawRolled

        // 1. Take-off Early Termination Mutual Exclusion:
        let abortOptions: [ContingencySelection] = [.birdStrikeAbort, .abortTakeoff, .efato]
        let rolledAborts = rolled.filter { abortOptions.contains($0) }
        if rolledAborts.count > 1 {
            let prioritizedAbort = rolledAborts.sorted { a, b in
                let rank: [ContingencySelection: Int] = [.birdStrikeAbort: 3, .abortTakeoff: 2, .efato: 1]
                return (rank[a] ?? 0) > (rank[b] ?? 0)
            }.first!
            rolled.removeAll(where: { abortOptions.contains($0) && $0 != prioritizedAbort })
        }

        // 2. Bird Hazard Mutual Exclusion:
        if rolled.contains(.birdStrikeAbort) {
            rolled.removeAll(where: { $0 == .birdHazardHold })
        }

        // 3. Pre-Lineup Hazard Mutual Exclusion:
        if rolled.contains(.emergencyLandingHold) && rolled.contains(.birdHazardHold) {
            rolled.removeAll(where: { $0 == .birdHazardHold })
        }

        // 4. Line-Up Delay Mutual Exclusion:
        if rolled.contains(.cancelLineUp) && rolled.contains(.wakeTurbulenceLineUp) {
            rolled.removeAll(where: { $0 == .wakeTurbulenceLineUp })
        }

        // 5. Approach Emergency Mutual Exclusion:
        let approachOptions = rolled.filter { $0.triggerPhase == .approach }
        if approachOptions.count > 1 {
            let prioritized = approachOptions.sorted { (a, b) -> Bool in
                let sevRank: [EventSeverity: Int] = [.distress: 3, .urgency: 2, .abnormal: 1, .normal: 0]
                return (sevRank[a.defaultSeverity] ?? 0) > (sevRank[b.defaultSeverity] ?? 0)
            }.first!
            rolled.removeAll(where: { $0.triggerPhase == .approach && $0 != prioritized })
        }

        var result: [InjectedContingency] = []
        for opt in rolled {
            if let cont = resolveSingleContingency(option: opt) {
                result.append(cont)
            }
        }
        return result.sorted { $0.triggerPhase.rawValue < $1.triggerPhase.rawValue }
    }

    private func resolveSelectedContingency(
        option: ContingencySelection,
        level: CurriculumLevel,
        seed: Int,
        mode: SimulationMode
    ) -> InjectedContingency? {
        let list = resolveMultipleContingencies(selectedOptions: [option], level: level, seed: seed)
        return list.first
    }

    private func resolveSingleContingency(option: ContingencySelection) -> InjectedContingency? {
        switch option {
        case .routineOnly, .auto:
            return nil

        case .birdHazardHold:
            return InjectedContingency(
                title: "Bird Hazard on Runway (Dispersal Hold)",
                severity: .abnormal,
                triggerPhase: .departure,
                summary: "Menara ATC mendeteksi kawanan burung besar di atas landasan pacu. Pesawat diinstruksikan menahan di holding point sementara armada pengusir burung bandara beroperasi.",
                downstreamEffect: "Izin lepas landas ditunda sesaat. Setelah pemeriksaan landasan bersih, ATC menerbitkan izin take-off normal."
            )

        case .birdStrikeAbort:
            return InjectedContingency(
                title: "Bird Strike on Take-off Roll (Abort)",
                severity: .distress,
                triggerPhase: .departure,
                summary: "Saat melaju di landasan pada kecepatan 80 knot sebelum V1, pesawat menabrak kawanan burung pada mesin. Pilot membatalkan take-off, ATC menerbitkan STOP IMMEDIATELY.",
                downstreamEffect: "Pesawat batal terbang. Seluruh fase berikutnya dialihkan ke penanganan darurat darat: inspeksi armada ARFF, evaluasi rem, pengosongan landasan, dan taxi ke apron pemeliharaan."
            )

        case .emergencyLandingHold:
            return InjectedContingency(
                title: "Inbound Emergency Priority (Hold Short / Cancel TO)",
                severity: .urgency,
                triggerPhase: .departure,
                summary: "Pesawat di holding point atau line up and wait harus menunda keberangkatan karena ada pesawat komersial lain di short final mendeklarasikan MAYDAY pendaratan darurat.",
                downstreamEffect: "Izin masuk landasan atau take-off clearance dibatalkan. Pesawat menahan di posisi aman hingga pesawat darurat mendarat selamat."
            )

        case .runwayChange:
            return InjectedContingency(
                title: "Runway Change Before Departure (Wind Shift 180°)",
                severity: .abnormal,
                triggerPhase: .preDeparture,
                summary: "Saat taxi menuju holding point, arah angin berbalik 180 derajat. ATC membatalkan izin taxi awal dan mengalihkan runway aktif ke reciprocal.",
                downstreamEffect: "Holding point dan runway keberangkatan diubah. Seluruh perizinan take-off menyesuaikan nomor runway baru."
            )

        case .forgottenLandingClearancePrompt:
            return InjectedContingency(
                title: "Late Landing Clearance (Short Final Prompt)",
                severity: .abnormal,
                triggerPhase: .approach,
                summary: "Pada short final 500 ft AGL, ATC belum memberikan izin mendarat (terdistraksi/koordinasi traffic). Pilot secara proaktif memanggil konfirmasi izin mendarat. ATC menyadari keterlambatan dan menerbitkan clearance tepat sebelum decision height.",
                downstreamEffect: "ATC meminta maaf dan segera menerbitkan 'cleared to land' dengan info angin terkini. Pilot membaca kembali izin mendarat dan melanjutkan touch-and-go / pendaratan."
            )

        case .abortTakeoff:
            return InjectedContingency(
                title: "Abort Take-Off (Ground Roll Stop)",
                severity: .abnormal,
                triggerPhase: .departure,
                summary: "Saat pesawat melaju di landasan pada take-off roll, terdeteksi runway incursion. ATC menerbitkan instruksi 'STOP IMMEDIATELY'. Pilot membatalkan take-off sebelum V1 dan berhenti di landasan.",
                downstreamEffect: "Pesawat batal terbang. Fase En-Route, Arrival, dan Approach dibatalkan. Pesawat backtrack dan vacate via exit taxiway menuju maintenance stand untuk inspeksi rem."
            )

        case .efato:
            return InjectedContingency(
                title: "EFATO (Engine Failure After Takeoff 500ft)",
                severity: .distress,
                triggerPhase: .departure,
                summary: "Pada ketinggian 500 ft AGL sesaat setelah lepas landas, mesin mati mendadak. Pilot mendeklarasikan MAYDAY dan mendarat darurat lurus di sisa landasan pacu.",
                downstreamEffect: "Fase En-Route dan Arrival dibatalkan. Pesawat mendarat darurat langsung di landasan keberangkatan, armada pemadam ARFF siaga penuh."
            )

        case .cancelLineUp:
            return InjectedContingency(
                title: "Cancel Line-Up and Wait (Preceding Traffic Delay)",
                severity: .abnormal,
                triggerPhase: .departure,
                summary: "Pesawat diperintahkan line up, namun dibatalkan mendadak oleh ATC karena pesawat di depan mengalami keterlambatan lepas landas.",
                downstreamEffect: "Pilot membatalkan masuk landasan dan menahan di holding point short of runway hingga separasi terpenuhi."
            )

        case .lowPassInspection:
            return InjectedContingency(
                title: "Low Pass Inspection (Kencana 191 Style)",
                severity: .abnormal,
                triggerPhase: .approach,
                summary: "Pesawat meminta izin terbang rendah di atas landasan pacu (Low Pass) untuk kalibrasi instrumen atau inspeksi visual roda pendaratan oleh personil menara ATC.",
                downstreamEffect: "ATC mengizinkan low pass tidak di bawah 200 ft. Setelah lewat depan menara, ATC mengonfirmasi roda terkunci dan memandu pesawat bergabung kembali ke sirkuit untuk mendarat."
            )

        case .weatherDeviation:
            return InjectedContingency(
                title: "Weather Deviation En-Route (CB Avoidance)",
                severity: .abnormal,
                triggerPhase: .enRoute,
                summary: "Prakiraan radar cuaca mendeteksi sel awan Cumulonimbus (CB) aktif di koridor rute. Pilot meminta deviasi 15 NM ke kanan dari jalur airway.",
                downstreamEffect: "ATC menyetujui deviasi dan menginstruksikan pilot melapor saat dapat kembali ke navigasi mandiri direct fix."
            )

        case .flapFailure:
            return InjectedContingency(
                title: "Flap System Failure (Approach DPS PAN PAN)",
                severity: .urgency,
                triggerPhase: .approach,
                summary: "Sistem flap gagal berekspansi saat mendekati Bali DPS. Pilot mendeklarasikan PAN PAN karena butuh kecepatan pendaratan tinggi 160 knot tanpa flap.",
                downstreamEffect: "ATC memberikan prioritas straight-in approach Runway 09 tanpa holding dan menyiagakan tim keselamatan."
            )

        case .unsafeGear:
            return InjectedContingency(
                title: "Unsafe Landing Gear Indication (VOR Holding)",
                severity: .urgency,
                triggerPhase: .approach,
                summary: "Indikator roda pendaratan tidak terkunci hijau saat final approach. Pilot melakukan go-around dan meminta holding pattern di atas VOR untuk troubleshooting checklist roda manual.",
                downstreamEffect: "Pesawat masuk holding pattern untuk checklist darurat. Setelah tiga lampu hijau terkonfirmasi, ATC memandu radar vectors kedua untuk pendaratan."
            )

        case .unclearedGoAround:
            return InjectedContingency(
                title: "Uncleared Missed Approach (No Clearance Received)",
                severity: .urgency,
                triggerPhase: .approach,
                summary: "Pesawat menembus batas decision height 200 ft tanpa menerima 'Cleared to Land' (runway terhalang / frekuensi tertimpa). Pilot wajib membatalkan pendaratan secara mandiri (Go-Around) demi keselamatan.",
                downstreamEffect: "Pesawat climb missed approach procedure. ATC Approach mengambil alih pemanduan vektor radar kedua menuju final ILS untuk pendaratan kedua."
            )

        case .midAirEngineOut:
            return InjectedContingency(
                title: "Mid-Air Engine Failure (Diversion ASSIST)",
                severity: .distress,
                triggerPhase: .enRoute,
                summary: "Di tengah rute jelajah en-route, mesin nomor 1 mengalami kegagalan mekanis. Pilot mendeklarasikan MAYDAY dan meminta rekomendasi bandara terdekat. ATC menerapkan protokol ASSIST (vektor radar ke bandara terdekat, QNH, siagakan ARFF).",
                downstreamEffect: "Pesawat dialihkan (divert) ke bandara terdekat viable. Rute STAR reguler dibatalkan dan digantikan dengan radar vectors prioritas langsung menuju final ILS."
            )

        case .holdShortCrossing:
            return InjectedContingency(
                title: "Runway Incursion Mitigation (Hold Short Crossing)",
                severity: .abnormal,
                triggerPhase: .preDeparture,
                summary: "Rute taxi menuju holding point melintasi landasan aktif saat ada pesawat mendarat. ATC menginstruksikan hold short crossing.",
                downstreamEffect: "Pilot wajib melakukan readback hold short di persimpangan landasan aktif sebelum diberikan otorisasi crossing."
            )

        case .engineFailureFinal:
            return InjectedContingency(
                title: "Engine Failure on Final (MAYDAY 4 DME)",
                severity: .distress,
                triggerPhase: .approach,
                summary: "Pada 4 DME final, mesin nomor 1 mengalami kegagalan mekanis. Pilot mendeklarasikan MAYDAY dan melanjutkan pendaratan darurat.",
                downstreamEffect: "ATC memberikan prioritas izin mendarat darurat langsung dan menyiagakan armada ARFF di runway."
            )

        case .tcasRA:
            return InjectedContingency(
                title: "TCAS Resolution Advisory (TCAS RA)",
                severity: .distress,
                triggerPhase: .enRoute,
                summary: "Instrumen kokpit TCAS membunyikan peringatan tabrakan 'CLIMB, CLIMB'. Pilot melakukan manuver menghindar vertikal darurat mengesampingkan ATC sesaat, lalu melapor 'TCAS RA'.",
                downstreamEffect: "Setelah 'clear of conflict', pilot meminta kembali ke cruising level dan melanjutkan navigasi normal."
            )

        case .rnavFailure:
            return InjectedContingency(
                title: "RNAV / GPS Failure (Radar Vectors)",
                severity: .abnormal,
                triggerPhase: .arrival,
                summary: "Sistem satelit GNSS kokpit mengalami degradasi saat kedatangan TMA. Pilot melapor 'Unable RNAV arrival'.",
                downstreamEffect: "Prosedur kedatangan STAR satelit dibatalkan. ATC mengambil alih menggunakan vektor radar konvensional heading 250 menuju ILS."
            )

        case .parallelBreakout:
            return InjectedContingency(
                title: "Parallel Breakout (Simultaneous ILS Hazard)",
                severity: .distress,
                triggerPhase: .approach,
                summary: "Pesawat di landasan paralel memotong non-transgression zone (NTZ). ATC menerbitkan instruksi breakout darurat belok segera.",
                downstreamEffect: "Pilot langsung berbelok tajam heading 200 climb 4.000 ft menjauhi bahaya tabrakan di jalur pendekatan paralel."
            )

        case .visualOrbitSpacing:
            return InjectedContingency(
                title: "Visual Orbit for Spacing (360° Turn)",
                severity: .abnormal,
                triggerPhase: .approach,
                summary: "Pada sirkuit visual downwind, pesawat terlalu dekat dengan traffic di depan. Tower menginstruksikan manuver putaran 360 derajat (orbit) untuk menjaga separasi.",
                downstreamEffect: "Pilot melakukan orbit 360 derajat di posisi sebelum diizinkan belok ke base leg dan final approach."
            )

        case .extendDownwind:
            return InjectedContingency(
                title: "Extend Downwind (Traffic Spacing)",
                severity: .abnormal,
                triggerPhase: .approach,
                summary: "Landasan pacu masih terisi pesawat lain yang sedang lepas landas. ATC menginstruksikan pilot memperpanjang downwind leg sebelum dipanggil untuk belok base leg.",
                downstreamEffect: "Base turn ditunda hingga ATC memanggil 'turn base leg', pilot mempertahankan ketinggian sirkuit."
            )

        case .nordoBlindTransmission:
            return InjectedContingency(
                title: "Transmitting Blind (NORDO Receiver Fail)",
                severity: .urgency,
                triggerPhase: .enRoute,
                summary: "Radio penerima kokpit gagal menerima audio ATC. Pilot menerapkan prosedur resmi ICAO Bab 9.5: Squawk 7600 dan memancarkan laporan buta (transmitting blind) dua kali.",
                downstreamEffect: "ATC merespons via instruksi pengamatan radar (squawk ident / lampu) dan menyiapkan lampu suar hijau (green pyrotechnic light) dari menara."
            )

        case .wakeTurbulenceLineUp:
            return InjectedContingency(
                title: "Wake Turbulence Line-Up (2 Min Delay)",
                severity: .abnormal,
                triggerPhase: .departure,
                summary: "Pesawat bersiap lepas landas tepat di belakang pesawat berbadan besar (Heavy B777). ATC mewajibkan jeda waktu separasi turbulensi vorteks 2 menit sebelum take-off.",
                downstreamEffect: "Pesawat line up and wait di runway selama 2 menit penuh sebelum diizinkan take-off clearance."
            )

        case .immediateTakeoffOrVacate:
            return InjectedContingency(
                title: "Immediate Take-off or Vacate Runway",
                severity: .abnormal,
                triggerPhase: .departure,
                summary: "Pesawat berada di runway saat traffic lain mendekat pada 2 NM short final. ATC memberikan pilihan cepat: take off segera tanpa jeda atau kosongkan runway.",
                downstreamEffect: "Pilot memilih immediate take-off roll cepat untuk menjaga keselamatan arus pergerakan landasan."
            )

        case .radarAvoidingAction:
            return InjectedContingency(
                title: "Radar Avoiding Action (Near-Miss Turn)",
                severity: .urgency,
                triggerPhase: .enRoute,
                summary: "Radar mendeteksi pesawat tak teridentifikasi berlawanan arah pada jarak 2 NM. ATC menerbitkan instruksi manuver darurat belok segera (avoiding action).",
                downstreamEffect: "Pilot langsung berbelok tajam heading 270 menghindari tabrakan udara sebelum diizinkan kembali ke rute semula."
            )

        case .emergencyDescentDecompression:
            return InjectedContingency(
                title: "Emergency Descent (Cabin Decompression)",
                severity: .distress,
                triggerPhase: .enRoute,
                summary: "Kabin mengalami dekompresi mendadak di FL360. Pilot mendeklarasikan MAYDAY dan melakukan emergency descent menukik ke FL100. ATC mem-broadcast peringatan ke airway.",
                downstreamEffect: "Pesawat menukik turun ke FL100. ATC mengosongkan jalur penerbangan di bawahnya dan mengarahkan pengalihan darurat ke bandara terdekat."
            )

        case .impositionOfSilence:
            return InjectedContingency(
                title: "Imposition of Silence (MAYDAY Traffic)",
                severity: .urgency,
                triggerPhase: .approach,
                summary: "Frekuensi radio mengalami interferensi saat ada pesawat lain darurat. ATC membungkam seluruh stasiun dengan frasa resmi 'STOP TRANSMITTING, MAYDAY'.",
                downstreamEffect: "Seluruh pilot wajib menjaga keheningan frekuensi radio hingga ATC menyiarkan 'DISTRESS TRAFFIC ENDED'."
            )

        case .passengerMedicalEmergency:
            return InjectedContingency(
                title: "Medical Priority PAN PAN (Heart Attack)",
                severity: .urgency,
                triggerPhase: .arrival,
                summary: "Penumpang mengalami serangan jantung kritis di kabin. Pilot mendeklarasikan PAN PAN meminta prioritas straight-in approach dan armada medis di apron.",
                downstreamEffect: "Rute STAR dipersingkat menjadi direct final approach dengan prioritas pendaratan nomor satu dan ambulans siaga di stand."
            )

        case .lowVisibilityRVR:
            return InjectedContingency(
                title: "Low Visibility RVR Breakdown (Cat II ILS)",
                severity: .abnormal,
                triggerPhase: .approach,
                summary: "Hujan sangat lebat menurunkan jarak pandang landasan. ATC mentransmisikan tiga nilai RVR resmi (touchdown, midpoint, stop-end).",
                downstreamEffect: "Pilot mengonfirmasi kemampuan sistem instrumen Cat II/III dan melanjutkan pendekatan presisi ILS."
            )

        case .contaminatedRunwayBraking:
            return InjectedContingency(
                title: "Contaminated Runway & Braking Action Poor",
                severity: .abnormal,
                triggerPhase: .approach,
                summary: "Genangan air di landasan pacu menyebabkan risiko hydroplaning. ATC meneruskan laporan daya cengkeram rem buruk (braking action poor) dari pesawat sebelumnya.",
                downstreamEffect: "Pilot mempersiapkan pengereman thrust reverser maksimum dan mengantisipasi jarak henti lebih panjang."
            )

        }
    }

    // MARK: - Adaptive 6-Phase Pipeline for Aborted / EFATO Flights (Eliminates Empty Phases)
    private func buildTerminatedEarlyPhaseExchanges(
        phase: Phase,
        contingency: InjectedContingency?,
        context: SlotContext,
        role: UserRole,
        currentGlobalTurn: inout Int
    ) -> (title: String, goal: String, exchanges: [FilledExchange]) {
        var exchanges: [FilledExchange] = []
        let callsign = context.callsign
        let twrUnit = context.unitTower?.callsign ?? "Tower"
        let gndUnit = context.unitGround?.callsign ?? "Ground"
        let gndFreq = SpokenFormFormatter.frequency(context.unitGround?.frequency ?? "121.700")
        let isAbort = contingency?.title.contains("Abort") == true
        let title: String
        let goal: String

        switch phase {
        case .preDeparture, .departure:
            title = ""
            goal = ""

        case .enRoute:
            if isAbort {
                title = "Phase 3: Runway Assessment & Brake Inspection"
                goal = "Koordinasi darat di runway pasca-abort, penilaian suhu rem panas (hot brakes), dan instruksi penahanan lalu lintas di final."

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P3-1", templateID: "ABT-P3", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), \(twrUnit), verify stopped on runway, advise if fire indication or assistance required.",
                    criticalSlots: [], severity: .abnormal, eventTag: "RUNWAY OCCUPIED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P3-2", templateID: "ABT-P3", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Stopped on runway, brakes hot, tires intact, no fire indication, requesting two minutes on runway for brake cooling checklist, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "STATUS", expectedValue: "stopped on runway", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CHECKLIST", expectedValue: "brake cooling checklist", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .abnormal, eventTag: "BRAKE COOLING"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P3-3", templateID: "ABT-P3", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), roger, take your time, holding approaching traffic on five miles final, advise when ready to vacate.",
                    criticalSlots: [], severity: .normal, eventTag: "TRAFFIC HOLDING"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P3-4", templateID: "ABT-P3", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Wilco, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "WILCO", expectedValue: "wilco", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "WILCO"
                ))
                currentGlobalTurn += 1
            } else {
                title = "Phase 3: Immediate Ground Safety & Evacuation Assessment"
                goal = "Pengamanan pesawat di runway pasca-EFATO forced landing, evaluasi kebocoran bahan bakar, dan konfirmasi kondisi penumpang."

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P3-1", templateID: "EFA-P3", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), \(twrUnit), emergency equipment on scene, advise souls on board and hazardous cargo.",
                    criticalSlots: [], severity: .distress, eventTag: "ARFF ON SCENE"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P3-2", templateID: "EFA-P3", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Two persons on board, zero hazardous cargo, master switch off, no fire, precautionary evacuation in progress, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "POB", expectedValue: "two persons on board", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "EVACUATION", expectedValue: "evacuation in progress", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .distress, eventTag: "EVACUATION IN PROGRESS"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P3-3", templateID: "EFA-P3", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), roger, fire crew in attendance, runway closed, advise when passengers safely clear.",
                    criticalSlots: [], severity: .distress, eventTag: "RUNWAY CLOSED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P3-4", templateID: "EFA-P3", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Passengers safely clear, standing by with Incident Commander, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "STATUS", expectedValue: "passengers safely clear", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "PASSENGERS CLEAR"
                ))
                currentGlobalTurn += 1
            }

        case .arrival:
            if isAbort {
                title = "Phase 4: ARFF & Safety Operations Escort"
                goal = "Inspeksi eksternal visual roda dan rem oleh armada ARFF (Tender One), konfirmasi tidak ada deflasi ban atau kebocoran hidrolik."

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P4-1", templateID: "ABT-P4", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), airport safety vehicle Tender One is in position alongside your main gear on taxiway, advise status.",
                    criticalSlots: [], severity: .normal, eventTag: "ARFF INSPECTION"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P4-2", templateID: "ABT-P4", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Checklist completed, brake temperature stabilizing, tires intact, ready to backtrack and vacate runway, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "READY_VACATE", expectedValue: "ready to backtrack", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "READY VACATE"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P4-3", templateID: "ABT-P4", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), Tender One confirms no smoke or fluid leaks, backtrack approved runway, vacate via \(context.exitTaxiway).",
                    criticalSlots: [], severity: .normal, eventTag: "BACKTRACK VACATE"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P4-4", templateID: "ABT-P4", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Backtrack approved, vacate via \(context.exitTaxiway), \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "VACATE_TAXIWAY", expectedValue: context.exitTaxiway, type: "mandatoryTaxiway"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "READBACK VACATE"
                ))
                currentGlobalTurn += 1
            } else {
                title = "Phase 4: Crash Site Containment & Runway Sterilization"
                goal = "Koordinasi pengamanan lokasi insiden oleh Chief Fire Officer, sterilisasi debris, dan penyiapan evakuasi airframe."

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P4-1", templateID: "EFA-P4", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), Chief Fire Officer reports all occupants evacuated to safety zone, foam blanket applied.",
                    criticalSlots: [], severity: .distress, eventTag: "FOAM BLANKET APPLIED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P4-2", templateID: "EFA-P4", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Affirm, occupants safe, awaiting towing crew, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "AFFIRM", expectedValue: "affirm", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .distress, eventTag: "OCCUPANTS SAFE"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P4-3", templateID: "EFA-P4", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), tow tug and salvage team en route, airport incident command established.",
                    criticalSlots: [], severity: .normal, eventTag: "SALVAGE TEAM EN ROUTE"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P4-4", templateID: "EFA-P4", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Wilco, standing by with incident command, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "WILCO", expectedValue: "wilco", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "WILCO SALVAGE"
                ))
                currentGlobalTurn += 1
            }

        case .approach:
            if isAbort {
                title = "Phase 5: Runway Vacated & Aerodrome Reopening"
                goal = "Laporan pengosongan landasan pacu, pembukaan kembali landasan untuk trafik, dan transfer ke frekuensi Ground."

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P5-1", templateID: "ABT-P5", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), \(twrUnit), report runway vacated.",
                    criticalSlots: [], severity: .normal, eventTag: "REPORT VACATED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P5-2", templateID: "ABT-P5", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "\(twrUnit), \(callsign), runway vacated via \(context.exitTaxiway).",
                    criticalSlots: [
                        CriticalSlot(slot: "VACATED", expectedValue: "runway vacated", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "RUNWAY VACATED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P5-3", templateID: "ABT-P5", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), runway vacated confirmed, runway now reopened for traffic. Contact Ground \(gndFreq).",
                    criticalSlots: [], severity: .normal, eventTag: "RUNWAY REOPENED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P5-4", templateID: "ABT-P5", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Ground \(gndFreq), \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "GROUND_FREQ", expectedValue: gndFreq, type: "mandatoryFrequency"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "TRANSFER GROUND"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P5-5", templateID: "ABT-P5", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), \(gndUnit), taxi to maintenance apron via Bravo, maintenance crew will meet you.",
                    criticalSlots: [], severity: .normal, eventTag: "GROUND TAXI CLEARANCE"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P5-6", templateID: "ABT-P5", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Taxi to maintenance apron via Bravo, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "STAND", expectedValue: "maintenance apron", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "READBACK TAXI"
                ))
                currentGlobalTurn += 1
            } else {
                title = "Phase 5: Airfield NOTAM & Runway Closure Coordination"
                goal = "Penerbitan NOTAM penutupan aerodrome sementara, pengalihan penerbangan masuk (inbound holding/diversion)."

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P5-1", templateID: "EFA-P5", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), \(twrUnit), runway disabled, NOTAM issued closing aerodrome to fixed-wing traffic for two hours.",
                    criticalSlots: [], severity: .distress, eventTag: "NOTAM ISSUED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P5-2", templateID: "EFA-P5", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Information received, aircraft secured on grass verge, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "INFO", expectedValue: "information received", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "AIRCRAFT SECURED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P5-3", templateID: "EFA-P5", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), airport safety vehicle escorting crew to flight operations building.",
                    criticalSlots: [], severity: .normal, eventTag: "CREW ESCORT"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P5-4", templateID: "EFA-P5", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Wilco, following escort, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "WILCO", expectedValue: "wilco", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "WILCO ESCORT"
                ))
                currentGlobalTurn += 1
            }

        case .landing:
            if isAbort {
                title = "Phase 6: Maintenance Stand & Flight Plan Cancellation"
                goal = "Parkir di stand perawatan teknis, pendinginan rem total, dan penutupan/pembatalan resmi flight plan."

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P6-1", templateID: "ABT-P6", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), \(gndUnit), report on maintenance stand with engines shut down.",
                    criticalSlots: [], severity: .normal, eventTag: "REPORT SHUTDOWN"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P6-2", templateID: "ABT-P6", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "\(gndUnit), \(callsign), on maintenance stand, parking brake set, engines shut down, request cancel flight plan.",
                    criticalSlots: [
                        CriticalSlot(slot: "ENGINES_SHUTDOWN", expectedValue: "engines shut down", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CANCEL_FP", expectedValue: "cancel flight plan", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "CANCEL FLIGHT PLAN"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P6-3", templateID: "ABT-P6", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), flight plan cancelled at zero two zero zero UTC, safety occurrence report logged, good day.",
                    criticalSlots: [], severity: .normal, eventTag: "PLAN CANCELLED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABT-P6-4", templateID: "ABT-P6", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Flight plan cancelled, good day, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "GOOD DAY"
                ))
                currentGlobalTurn += 1
            } else {
                title = "Phase 6: Accident Investigation Handover & Official Filing"
                goal = "Serah terima lokasi kejadian kepada tim investigasi kecelakaan (KNKT/DGCA) dan penutupan resmi rencana penerbangan."

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P6-1", templateID: "EFA-P6", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), Air Traffic Services has filed air safety occurrence report, flight plan officially terminated at zero two zero zero UTC.",
                    criticalSlots: [], severity: .distress, eventTag: "OCCURRENCE FILED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P6-2", templateID: "EFA-P6", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Occurrence report acknowledged, flight plan terminated, crew standing by for safety interview, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "ACKNOWLEDGED", expectedValue: "acknowledged", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "SAFETY ACKNOWLEDGED"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P6-3", templateID: "EFA-P6", turn: currentGlobalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), thank you for professional handling, all units standing down.",
                    criticalSlots: [], severity: .normal, eventTag: "STAND DOWN"
                ))
                currentGlobalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "EFA-P6-4", templateID: "EFA-P6", turn: currentGlobalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Standing down, good day, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "GOOD DAY"
                ))
                currentGlobalTurn += 1
            }
        }

        return (title: title, goal: goal, exchanges: exchanges)
    }

    // MARK: - Integrated Dynamic Phase Builders (Chronological FSM Architecture)
    private func buildDynamicPhaseExchanges(
        phase: Phase,
        level: CurriculumLevel,
        seed: Int,
        role: UserRole,
        context: SlotContext,
        contingencies: [InjectedContingency],
        activeDepRunway: inout Runway,
        activeHoldingPoint: inout String,
        activeWeather: inout AlignedWeather,
        isFlightTerminatedEarly: inout Bool,
        executedContingencies: inout [InjectedContingency],
        globalTurn: inout Int
    ) -> [FilledExchange] {
        switch phase {
        case .preDeparture:
            return buildPreDepartureExchanges(
                level: level,
                seed: seed,
                role: role,
                context: context,
                contingencies: contingencies,
                activeDepRunway: &activeDepRunway,
                activeHoldingPoint: &activeHoldingPoint,
                activeWeather: &activeWeather,
                executedContingencies: &executedContingencies,
                globalTurn: &globalTurn
            )
        case .departure:
            return buildDepartureExchanges(
                level: level,
                seed: seed,
                role: role,
                context: context,
                contingencies: contingencies,
                activeDepRunway: &activeDepRunway,
                activeHoldingPoint: &activeHoldingPoint,
                activeWeather: &activeWeather,
                isFlightTerminatedEarly: &isFlightTerminatedEarly,
                executedContingencies: &executedContingencies,
                globalTurn: &globalTurn
            )
        case .enRoute:
            return buildEnRouteExchanges(
                level: level,
                seed: seed,
                role: role,
                context: context,
                contingencies: contingencies,
                executedContingencies: &executedContingencies,
                globalTurn: &globalTurn
            )
        case .arrival:
            return buildArrivalExchanges(
                level: level,
                seed: seed,
                role: role,
                context: context,
                contingencies: contingencies,
                executedContingencies: &executedContingencies,
                globalTurn: &globalTurn
            )
        case .approach:
            return buildApproachExchanges(
                level: level,
                seed: seed,
                role: role,
                context: context,
                contingencies: contingencies,
                executedContingencies: &executedContingencies,
                globalTurn: &globalTurn
            )
        case .landing:
            return buildLandingExchanges(
                level: level,
                seed: seed,
                role: role,
                context: context,
                globalTurn: &globalTurn
            )
        }
    }

    // MARK: - Phase 1: Pre-Departure Builder
    private func buildPreDepartureExchanges(
        level: CurriculumLevel,
        seed: Int,
        role: UserRole,
        context: SlotContext,
        contingencies: [InjectedContingency],
        activeDepRunway: inout Runway,
        activeHoldingPoint: inout String,
        activeWeather: inout AlignedWeather,
        executedContingencies: inout [InjectedContingency],
        globalTurn: inout Int
    ) -> [FilledExchange] {
        var exchanges: [FilledExchange] = []
        let callsign = context.callsign
        let atisLetter = context.atisId
        let qnhSpoken = SpokenFormFormatter.qnh(context.weather.qnh)
        let depRwySpoken = SpokenFormFormatter.runway(activeDepRunway.designator)
        let standOrig = context.stand
        let acftType = context.aircraftType
        let sidName = context.sidProcedure
        let destName = context.destinationName
        let delUnit = context.unitDelivery?.callsign ?? (context.unitGround?.callsign ?? "Ground")
        let _ = context.unitGround?.callsign ?? "Ground"
        let gndFreq = SpokenFormFormatter.frequency(context.unitGround?.frequency ?? "121.700")

        if level == .level1 {
            // Turn 1: PILOT Initial Contact with Tower incorporating ATIS code
            exchanges.append(FilledExchange(
                exchangeID: "PD-VFR-INIT-1", templateID: "PD-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(context.unitTower?.callsign ?? "Tower"), \(callsign), \(acftType) at GA apron, information \(atisLetter) received, QNH \(qnhSpoken), request taxi for local circuit touch-and-go.",
                criticalSlots: [
                    CriticalSlot(slot: "ATIS_ID", expectedValue: atisLetter, type: "mandatoryAtis"),
                    CriticalSlot(slot: "QNH", expectedValue: qnhSpoken, type: "mandatoryQnh"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "INITIAL CONTACT & TAXI REQ"
            ))
            globalTurn += 1

            // Turn 2: ATC Taxi to Holding Point
            exchanges.append(FilledExchange(
                exchangeID: "PD-VFR-TXI-1", templateID: "PD-04", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), taxi to holding point \(activeHoldingPoint) runway \(depRwySpoken) via Alfa, hold short runway \(depRwySpoken).",
                criticalSlots: [], severity: .normal, eventTag: "TAXI TO HOLDING POINT"
            ))
            globalTurn += 1

            // Turn 3: PILOT Readback Taxi
            exchanges.append(FilledExchange(
                exchangeID: "PD-VFR-TXI-2", templateID: "PD-04", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Taxi to holding point \(activeHoldingPoint) runway \(depRwySpoken) via Alfa, hold short runway \(depRwySpoken), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "HOLDING_POINT", expectedValue: activeHoldingPoint, type: "mandatoryHoldingPoint"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: depRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "HOLD_SHORT_RUNWAY", expectedValue: "hold short runway", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK TAXI"
            ))
            globalTurn += 1

        } else if level == .level5 {
            // Turn 1: PILOT Initial Contact with Delivery (TSAT A-CDM)
            exchanges.append(FilledExchange(
                exchangeID: "PD-CD-REQ-1", templateID: "PD-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(delUnit), \(callsign), \(standOrig), information \(atisLetter) received, QNH \(qnhSpoken), TSAT zero four one zero, request IFR clearance to \(destName), ready to copy.",
                criticalSlots: [
                    CriticalSlot(slot: "ATIS_ID", expectedValue: atisLetter, type: "mandatoryAtis"),
                    CriticalSlot(slot: "DESTINATION", expectedValue: destName, type: "mandatoryAirport"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "IFR CLEARANCE REQ"
            ))
            globalTurn += 1

            // Turn 2: ATC Standby
            exchanges.append(FilledExchange(
                exchangeID: "PD-CD-STB-1", templateID: "PD-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(delUnit), standby.",
                criticalSlots: [], severity: .normal, eventTag: "STANDBY"
            ))
            globalTurn += 1

            // Turn 3: PILOT Standby
            exchanges.append(FilledExchange(
                exchangeID: "PD-CD-STB-2", templateID: "PD-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Standing by, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK STANDBY"
            ))
            globalTurn += 1

            // Turn 4: ATC IFR Clearance
            exchanges.append(FilledExchange(
                exchangeID: "PD-CD-CLR-1", templateID: "PD-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(delUnit), cleared to \(destName) via \(sidName) departure, flight planned route. Climb initially flight level one zero zero, departure frequency \(context.depFreq), squawk \(context.squawk), TSAT zero four one zero.",
                criticalSlots: [], severity: .normal, eventTag: "IFR CLEARANCE ISSUED"
            ))
            globalTurn += 1

            // Turn 5: PILOT Readback Clearance
            exchanges.append(FilledExchange(
                exchangeID: "PD-CD-CLR-2", templateID: "PD-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Cleared to \(destName) via \(sidName) departure, flight planned route, climb initially flight level one zero zero, departure frequency \(context.depFreq), squawk \(context.squawk), TSAT zero four one zero, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "DESTINATION", expectedValue: destName, type: "mandatoryAirport"),
                    CriticalSlot(slot: "SID", expectedValue: sidName, type: "mandatorySid"),
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "flight level one zero zero", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "SQUAWK", expectedValue: context.squawk, type: "mandatorySquawk"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CLEARANCE"
            ))
            globalTurn += 1

            // Turn 6: ATC Readback correct & Pushback instruction
            exchanges.append(FilledExchange(
                exchangeID: "PD-CD-CORR-1", templateID: "PD-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), readback correct. Start-up and pushback approved, face north, QNH \(qnhSpoken). Contact Ground \(gndFreq) when ready to taxi.",
                criticalSlots: [], severity: .normal, eventTag: "READBACK CORRECT & PUSH"
            ))
            globalTurn += 1

            // Turn 7: PILOT Readback Pushback & Ground freq
            exchanges.append(FilledExchange(
                exchangeID: "PD-CD-CORR-2", templateID: "PD-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Start-up and pushback approved, face north, QNH \(qnhSpoken), Ground \(gndFreq) when ready, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "APPROVAL", expectedValue: "start-up and pushback approved", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "QNH", expectedValue: qnhSpoken, type: "mandatoryQnh"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK PUSH & GROUND"
            ))
            globalTurn += 1

            // Turn 8: ATC Ground taxi clearance (with crossing if triggered)
            if let crossCont = contingencies.first(where: { $0.title.contains("Hold Short Crossing") }) {
                let crossRwy = activeDepRunway.designator == "11" ? "one zero" : "two eight"
                exchanges.append(FilledExchange(
                    exchangeID: "ABN-RWY-X-1", templateID: "ABN-RWY-X", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), Ground, taxi via Alfa, hold short of runway \(crossRwy), traffic on short final.",
                    criticalSlots: [], severity: .abnormal, eventTag: "HOLD SHORT RUNWAY CROSSING"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABN-RWY-X-2", templateID: "ABN-RWY-X", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Hold short runway \(crossRwy) via Alfa, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "HOLD_SHORT_RUNWAY", expectedValue: "hold short runway", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .abnormal, eventTag: "HOLD SHORT CROSSING READBACK"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABN-RWY-X-3", templateID: "ABN-RWY-X", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), cross runway \(crossRwy), continue taxi via \(context.taxiRoute), hold short runway \(depRwySpoken).",
                    criticalSlots: [], severity: .normal, eventTag: "CROSS RUNWAY APPROVED"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABN-RWY-X-4", templateID: "ABN-RWY-X", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Cross runway \(crossRwy), continue via \(context.taxiRoute), hold short runway \(depRwySpoken), \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "CROSS_RUNWAY", expectedValue: "cross runway", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "RUNWAY", expectedValue: depRwySpoken, type: "mandatoryRunway"),
                        CriticalSlot(slot: "HOLD_SHORT_RUNWAY", expectedValue: "hold short runway", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "CROSS APPROVED READBACK"
                ))
                globalTurn += 1
                executedContingencies.append(crossCont)

            } else {
                exchanges.append(FilledExchange(
                    exchangeID: "PD-GND-TXI-2", templateID: "PD-04", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), Ground, taxi to holding point \(activeHoldingPoint) runway \(depRwySpoken) via \(context.taxiRoute), hold short runway \(depRwySpoken).",
                    criticalSlots: [], severity: .normal, eventTag: "TAXI TO HOLDING POINT"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "PD-GND-TXI-3", templateID: "PD-04", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Taxi to holding point \(activeHoldingPoint) runway \(depRwySpoken) via \(context.taxiRoute), hold short runway \(depRwySpoken), \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "HOLDING_POINT", expectedValue: activeHoldingPoint, type: "mandatoryHoldingPoint"),
                        CriticalSlot(slot: "RUNWAY", expectedValue: depRwySpoken, type: "mandatoryRunway"),
                        CriticalSlot(slot: "HOLD_SHORT_RUNWAY", expectedValue: "hold short runway", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "READBACK TAXI"
                ))
                globalTurn += 1
            }

        } else {
            // Levels 2, 3, 4: IFR Standard
            // Turn 1: PILOT Initial Contact with Delivery / Ground
            exchanges.append(FilledExchange(
                exchangeID: "PD-IFR-INIT-1", templateID: "PD-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(delUnit), \(callsign), \(standOrig), information \(atisLetter) received, QNH \(qnhSpoken), request IFR clearance to \(destName), ready to copy.",
                criticalSlots: [
                    CriticalSlot(slot: "ATIS_ID", expectedValue: atisLetter, type: "mandatoryAtis"),
                    CriticalSlot(slot: "DESTINATION", expectedValue: destName, type: "mandatoryAirport"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "IFR CLEARANCE REQ"
            ))
            globalTurn += 1

            // Turn 2: ATC Route Clearance
            let initAlt = level == .level2 ? "flight level zero eight zero" : "flight level one zero zero"
            exchanges.append(FilledExchange(
                exchangeID: "PD-IFR-CLR-1", templateID: "PD-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(delUnit), cleared to \(destName) via \(sidName) departure, flight planned route. Climb initially \(initAlt), squawk \(context.squawk). Start-up and pushback approved, face west, QNH \(qnhSpoken).",
                criticalSlots: [], severity: .normal, eventTag: "CLEARANCE & PUSHBACK APPROVED"
            ))
            globalTurn += 1

            // Turn 3: PILOT Readback
            exchanges.append(FilledExchange(
                exchangeID: "PD-IFR-CLR-2", templateID: "PD-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Cleared to \(destName) via \(sidName) departure, climb initially \(initAlt), squawk \(context.squawk), start-up and pushback approved, face west, QNH \(qnhSpoken), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "DESTINATION", expectedValue: destName, type: "mandatoryAirport"),
                    CriticalSlot(slot: "SID", expectedValue: sidName, type: "mandatorySid"),
                    CriticalSlot(slot: "SQUAWK", expectedValue: context.squawk, type: "mandatorySquawk"),
                    CriticalSlot(slot: "QNH", expectedValue: qnhSpoken, type: "mandatoryQnh"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CLEARANCE & PUSH"
            ))
            globalTurn += 1

            // Turn 4: ATC Ground taxi clearance
            if let crossCont = contingencies.first(where: { $0.title.contains("Hold Short Crossing") }) {
                let crossRwy = activeDepRunway.designator == "10" ? "two six" : "zero eight"
                exchanges.append(FilledExchange(
                    exchangeID: "ABN-RWY-X-1", templateID: "ABN-RWY-X", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), Ground, taxi via Alfa, hold short of runway \(crossRwy), traffic on short final.",
                    criticalSlots: [], severity: .abnormal, eventTag: "HOLD SHORT RUNWAY CROSSING"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABN-RWY-X-2", templateID: "ABN-RWY-X", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Hold short runway \(crossRwy) via Alfa, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "HOLD_SHORT_RUNWAY", expectedValue: "hold short runway", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .abnormal, eventTag: "HOLD SHORT CROSSING READBACK"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABN-RWY-X-3", templateID: "ABN-RWY-X", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), cross runway \(crossRwy), continue taxi via \(context.taxiRoute), hold short runway \(depRwySpoken).",
                    criticalSlots: [], severity: .normal, eventTag: "CROSS RUNWAY APPROVED"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABN-RWY-X-4", templateID: "ABN-RWY-X", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Cross runway \(crossRwy), continue via \(context.taxiRoute), hold short runway \(depRwySpoken), \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "CROSS_RUNWAY", expectedValue: "cross runway", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "RUNWAY", expectedValue: depRwySpoken, type: "mandatoryRunway"),
                        CriticalSlot(slot: "HOLD_SHORT_RUNWAY", expectedValue: "hold short runway", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "CROSS APPROVED READBACK"
                ))
                globalTurn += 1
                executedContingencies.append(crossCont)

            } else {
                exchanges.append(FilledExchange(
                    exchangeID: "PD-GND-TXI-2", templateID: "PD-04", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), Ground, taxi to holding point \(activeHoldingPoint) runway \(depRwySpoken) via \(context.taxiRoute), hold short runway \(depRwySpoken).",
                    criticalSlots: [], severity: .normal, eventTag: "TAXI TO HOLDING POINT"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "PD-GND-TXI-3", templateID: "PD-04", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Taxi to holding point \(activeHoldingPoint) runway \(depRwySpoken) via \(context.taxiRoute), hold short runway \(depRwySpoken), \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "HOLDING_POINT", expectedValue: activeHoldingPoint, type: "mandatoryHoldingPoint"),
                        CriticalSlot(slot: "RUNWAY", expectedValue: depRwySpoken, type: "mandatoryRunway"),
                        CriticalSlot(slot: "HOLD_SHORT_RUNWAY", expectedValue: "hold short runway", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "READBACK TAXI"
                ))
                globalTurn += 1
            }
        }

        // Mid-Taxi Runway Change (Wind Shift 180 degrees)
        if let rwyChange = contingencies.first(where: { $0.title.contains("Runway Change") }) {
            let reciprocalDesignator = activeDepRunway.reciprocal
            let reciprocalSpoken = SpokenFormFormatter.runway(reciprocalDesignator)
            let newHP = activeDepRunway.holdingPoints.last ?? "A2"

            exchanges.append(FilledExchange(
                exchangeID: "ABN-RWY-CHG-1", templateID: "ABN-RWY-CHG", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), wind shifted two six zero degrees one five knots, runway change, runway \(reciprocalSpoken) now in use. Taxi to holding point \(newHP) runway \(reciprocalSpoken) via Bravo, hold short runway \(reciprocalSpoken).",
                criticalSlots: [], severity: .abnormal, eventTag: "RUNWAY CHANGE INSTRUCTION"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-RWY-CHG-2", templateID: "ABN-RWY-CHG", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Taxi to holding point \(newHP) runway \(reciprocalSpoken) via Bravo, hold short runway \(reciprocalSpoken), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "HOLDING_POINT", expectedValue: newHP, type: "mandatoryHoldingPoint"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: reciprocalSpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "HOLD_SHORT_RUNWAY", expectedValue: "hold short runway", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .abnormal, eventTag: "RUNWAY CHANGE READBACK"
            ))
            globalTurn += 1

            // INVERT activeDepRunway OBJECT SO DESIGNATOR BECOMES RECIPROCAL!
            if let rwyObj = context.airport.runways.first(where: { $0.designator == reciprocalDesignator }) {
                activeDepRunway = rwyObj
            } else {
                activeDepRunway = Runway(
                    pair: activeDepRunway.pair,
                    designator: reciprocalDesignator,
                    reciprocal: activeDepRunway.designator,
                    headingDegT: (activeDepRunway.headingDegT + 180.0).truncatingRemainder(dividingBy: 360.0),
                    holdingPoints: activeDepRunway.holdingPoints
                )
            }
            activeHoldingPoint = newHP
            activeWeather = AlignedWeather(
                runway: reciprocalSpoken,
                heading: (activeWeather.heading + 180.0).truncatingRemainder(dividingBy: 360.0),
                windDirection: 260,
                windSpeed: 15,
                headwindKnots: 15,
                crosswindKnots: 0,
                qnh: activeWeather.qnh
            )
            executedContingencies.append(rwyChange)
        }

        return exchanges
    }

    // MARK: - Phase 2: Departure Builder (Sequential FSM Flow)
    private func buildDepartureExchanges(
        level: CurriculumLevel,
        seed: Int,
        role: UserRole,
        context: SlotContext,
        contingencies: [InjectedContingency],
        activeDepRunway: inout Runway,
        activeHoldingPoint: inout String,
        activeWeather: inout AlignedWeather,
        isFlightTerminatedEarly: inout Bool,
        executedContingencies: inout [InjectedContingency],
        globalTurn: inout Int
    ) -> [FilledExchange] {
        var exchanges: [FilledExchange] = []
        let callsign = context.callsign
        let twrUnit = context.unitTower?.callsign ?? "Tower"
        let rwySpoken = SpokenFormFormatter.runway(activeDepRunway.designator)
        let windSpoken = SpokenFormFormatter.wind(direction: activeWeather.windDirection, knots: activeWeather.windSpeed)

        // STEP 1: ATC TOWER INITIAL CONTACT AT HOLDING POINT
        exchanges.append(FilledExchange(
            exchangeID: "DP-TWR-INIT-1", templateID: "DP-01", turn: globalTurn, speaker: "ATC",
            isUserTurn: (role == .atc),
            text: "\(callsign), \(twrUnit), holding point \(activeHoldingPoint), report ready for departure.",
            criticalSlots: [], severity: .normal, eventTag: "REPORT READY FOR DEPARTURE"
        ))
        globalTurn += 1

        exchanges.append(FilledExchange(
            exchangeID: "DP-RDY-1", templateID: "DP-01", turn: globalTurn, speaker: "PILOT",
            isUserTurn: (role == .pilot),
            text: "Ready for departure, \(callsign).",
            criticalSlots: [
                CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
            ], severity: .normal, eventTag: "READY FOR DEPARTURE"
        ))
        globalTurn += 1

        // STEP 2: PRE-LINEUP HAZARDS (Bird Hazard or Inbound Emergency Priority)
        var prefixConditionText = ""
        if let birdHazard = contingencies.first(where: { $0.title.contains("Bird Hazard") }) {
            exchanges.append(FilledExchange(
                exchangeID: "ABN-BRD-HAZ-1", templateID: "ABN-BRD-HAZ", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), hold position, caution large flock of birds reported over runway \(rwySpoken) near threshold, airport bird dispersal vehicle dispatched.",
                criticalSlots: [], severity: .abnormal, eventTag: "BIRD HAZARD WARNING"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-BRD-HAZ-2", templateID: "ABN-BRD-HAZ", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Holding position, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "HOLD_POSITION", expectedValue: "holding position", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .abnormal, eventTag: "HOLD POSITION"
            ))
            globalTurn += 1

            prefixConditionText = "bird dispersal completed, runway \(rwySpoken) clear of birds. "
            executedContingencies.append(birdHazard)

        } else if let emgInbound = contingencies.first(where: { $0.title.contains("Inbound Emergency Priority") }) {
            exchanges.append(FilledExchange(
                exchangeID: "URG-EMG-LAND-1", templateID: "URG-EMG-LAND", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), hold position, cancel take-off preparation, inbound traffic Boeing seven three seven MAYDAY engine failure on two miles final, hold short of runway \(rwySpoken)!",
                criticalSlots: [], severity: .urgency, eventTag: "CANCEL PREPARATION: MAYDAY INBOUND"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "URG-EMG-LAND-2", templateID: "URG-EMG-LAND", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Holding position, holding short runway \(rwySpoken), \(callsign)!",
                criticalSlots: [
                    CriticalSlot(slot: "HOLD_POSITION", expectedValue: "holding position", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "HOLD_SHORT_RUNWAY", expectedValue: "holding short runway", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .urgency, eventTag: "HOLD SHORT"
            ))
            globalTurn += 1

            prefixConditionText = "emergency aircraft safely landed on runway \(rwySpoken), runway clear. "
            executedContingencies.append(emgInbound)
        }

        // STEP 3: LINE UP AND WAIT
        if let canLineUp = contingencies.first(where: { $0.title.contains("Cancel Line-Up") }) {
            exchanges.append(FilledExchange(
                exchangeID: "ABN-CAN-LU-1", templateID: "ABN-CAN-LU", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(prefixConditionText)runway \(rwySpoken), line up and wait.",
                criticalSlots: [], severity: .normal, eventTag: prefixConditionText.isEmpty ? "LINE UP AND WAIT" : "RUNWAY CLEAR & LINE UP"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-CAN-LU-2", templateID: "ABN-CAN-LU", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(rwySpoken), line up and wait, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "LINE_UP_WAIT", expectedValue: "line up and wait", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK LINE UP"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-CAN-LU-3", templateID: "ABN-CAN-LU", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), cancel line up, hold short of runway \(rwySpoken), preceding traffic delayed.",
                criticalSlots: [], severity: .abnormal, eventTag: "CANCEL LINE UP"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-CAN-LU-4", templateID: "ABN-CAN-LU", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Cancel line up, holding short runway \(rwySpoken), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "CANCEL_LINE_UP", expectedValue: "cancel line up", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "HOLD_SHORT_RUNWAY", expectedValue: "holding short runway", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .abnormal, eventTag: "READBACK CANCEL LINE UP"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-CAN-LU-5", templateID: "ABN-CAN-LU", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), runway \(rwySpoken), line up and wait.",
                criticalSlots: [], severity: .normal, eventTag: "RE-CLEARED LINE UP"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-CAN-LU-6", templateID: "ABN-CAN-LU", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(rwySpoken), line up and wait, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "LINE_UP_WAIT", expectedValue: "line up and wait", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK RE-CLEARED LINE UP"
            ))
            globalTurn += 1
            executedContingencies.append(canLineUp)

        } else if let wakeCont = contingencies.first(where: { $0.title.contains("Wake Turbulence Line-Up") }) {
            exchanges.append(FilledExchange(
                exchangeID: "ABN-WK-LU-1", templateID: "ABN-WK-LU", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(prefixConditionText)runway \(rwySpoken), caution wake turbulence behind departing Boeing seven seven seven, line up and wait, expect two minutes delay.",
                criticalSlots: [], severity: .abnormal, eventTag: "WAKE TURBULENCE 2MIN"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-WK-LU-2", templateID: "ABN-WK-LU", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(rwySpoken), line up and wait, caution wake turbulence, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "LINE_UP_WAIT", expectedValue: "line up and wait", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .abnormal, eventTag: "READBACK WAKE LINE UP"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-WK-LU-3", templateID: "ABN-WK-LU", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), two minutes elapsed, runway \(rwySpoken), wind \(windSpoken), be ready for departure.",
                criticalSlots: [], severity: .normal, eventTag: "WAKE INTERVAL ELAPSED"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-WK-LU-4", templateID: "ABN-WK-LU", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Ready for departure, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READY FOR DEPARTURE"
            ))
            globalTurn += 1
            executedContingencies.append(wakeCont)

        } else if level == .level1 {
            exchanges.append(FilledExchange(
                exchangeID: "DP-VFR-LU-1", templateID: "DP-03", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(prefixConditionText)backtrack runway \(rwySpoken), line up and wait.",
                criticalSlots: [], severity: .normal, eventTag: prefixConditionText.isEmpty ? "BACKTRACK & LINE UP" : "RUNWAY CLEAR & LINE UP"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "DP-VFR-LU-2", templateID: "DP-03", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Backtrack runway \(rwySpoken), line up and wait, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "LINE_UP_WAIT", expectedValue: "line up and wait", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK BACKTRACK & LINE UP"
            ))
            globalTurn += 1

        } else {
            // IFR Levels 2–5
            let variant = seed % 3
            if variant == 0 {
                exchanges.append(FilledExchange(
                    exchangeID: "DP-IFR-LU-1", templateID: "DP-03", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), \(prefixConditionText)runway \(rwySpoken), line up and wait.",
                    criticalSlots: [], severity: .normal, eventTag: prefixConditionText.isEmpty ? "LINE UP AND WAIT" : "RUNWAY CLEAR & LINE UP"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "DP-IFR-LU-2", templateID: "DP-03", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Runway \(rwySpoken), line up and wait, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                        CriticalSlot(slot: "LINE_UP_WAIT", expectedValue: "line up and wait", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "READBACK LINE UP"
                ))
                globalTurn += 1

            } else if variant == 1 {
                exchanges.append(FilledExchange(
                    exchangeID: "DP-IFR-CND-1", templateID: "DP-03", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), \(prefixConditionText)behind landing Airbus three two zero, line up and wait runway \(rwySpoken) behind.",
                    criticalSlots: [], severity: .normal, eventTag: "CONDITIONAL LINE-UP"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "DP-IFR-CND-2", templateID: "DP-03", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Behind landing Airbus three two zero, line up and wait runway \(rwySpoken) behind, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                        CriticalSlot(slot: "LINE_UP_WAIT", expectedValue: "line up and wait", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "READBACK CONDITIONAL LINE-UP"
                ))
                globalTurn += 1

            } else {
                exchanges.append(FilledExchange(
                    exchangeID: "DP-IFR-IMM-1", templateID: "DP-03", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), \(prefixConditionText)traffic on three miles final, are you ready for immediate departure?",
                    criticalSlots: [], severity: .normal, eventTag: "READY IMMEDIATE QUERY"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "DP-IFR-IMM-2", templateID: "DP-03", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "AFFIRM, ready for immediate, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "AFFIRM", expectedValue: "affirm", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "CONFIRM IMMEDIATE"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "DP-IFR-IMM-3", templateID: "DP-03", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), line up, be ready for immediate departure.",
                    criticalSlots: [], severity: .normal, eventTag: "LINE UP IMMEDIATE"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "DP-IFR-IMM-4", templateID: "DP-03", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "Line up, ready for immediate, \(callsign).",
                    criticalSlots: [
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .normal, eventTag: "READBACK LINE UP IMMEDIATE"
                ))
                globalTurn += 1
            }
        }

        // STEP 4: TAKE-OFF CLEARANCE
        if let immCont = contingencies.first(where: { $0.title.contains("Immediate Take-off or Vacate") }) {
            exchanges.append(FilledExchange(
                exchangeID: "ABN-IMM-TO-1", templateID: "ABN-IMM-TO", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), traffic Boeing seven three seven on two miles final, take off immediately or vacate runway!",
                criticalSlots: [], severity: .abnormal, eventTag: "TAKEOFF IMMEDIATELY OR VACATE"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-IMM-TO-2", templateID: "ABN-IMM-TO", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Taking off immediately, \(callsign)!",
                criticalSlots: [
                    CriticalSlot(slot: "TAKING_OFF", expectedValue: "taking off immediately", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .abnormal, eventTag: "TAKING OFF IMMEDIATELY"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-IMM-TO-3", templateID: "ABN-IMM-TO", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), runway \(rwySpoken), wind \(windSpoken), cleared for immediate take-off.",
                criticalSlots: [], severity: .normal, eventTag: "CLEARED IMMEDIATE TAKE-OFF"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-IMM-TO-4", templateID: "ABN-IMM-TO", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(rwySpoken), cleared for immediate take-off, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CLEARED_TAKEOFF", expectedValue: "cleared for immediate take-off", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK IMMEDIATE TAKE-OFF"
            ))
            globalTurn += 1
            executedContingencies.append(immCont)

        } else {
            let toText = (level == .level1) ? "cleared touch-and-go, make left traffic" : "cleared for take-off"
            exchanges.append(FilledExchange(
                exchangeID: "DP-TO-CLR-1", templateID: "DP-04", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), runway \(rwySpoken), wind \(windSpoken), \(toText).",
                criticalSlots: [], severity: .normal, eventTag: "CLEARED FOR TAKE-OFF"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "DP-TO-CLR-2", templateID: "DP-04", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(rwySpoken), \(toText), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CLEARED_TAKEOFF", expectedValue: toText, type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK TAKE-OFF"
            ))
            globalTurn += 1
        }

        // STEP 5: TAKE-OFF ROLL EMERGENCIES (ABORT / EFATO)
        if let abtCont = contingencies.first(where: { $0.title.contains("Abort Take-Off") }) {
            isFlightTerminatedEarly = true

            // ATC-Initiated Abort (ICAO Doc 9432 Bab 4.5.11): Vehicle entering runway
            exchanges.append(FilledExchange(
                exchangeID: "ABN-ABT-TO-1", templateID: "ABN-ABT-TO", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "STOP IMMEDIATELY, \(callsign), STOP IMMEDIATELY, vehicle entering runway!",
                criticalSlots: [], severity: .distress, eventTag: "STOP IMMEDIATELY"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-ABT-TO-2", templateID: "ABN-ABT-TO", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "STOPPING, ABORTING TAKE-OFF, \(callsign)!",
                criticalSlots: [
                    CriticalSlot(slot: "STOPPING", expectedValue: "stopping", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "ABORT_TAKEOFF", expectedValue: "aborting take-off", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "STOPPING & ABORTING"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-ABT-TO-3", templateID: "ABN-ABT-TO", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), roger stopping, emergency equipment alerted and rolling to your position, advise when stopped.",
                criticalSlots: [], severity: .abnormal, eventTag: "ARFF ALERTED"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-ABT-TO-4", templateID: "ABN-ABT-TO", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Stopped on runway \(rwySpoken), brakes hot, tires intact, no assistance required, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "STOPPED_RUNWAY", expectedValue: "stopped on runway", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .abnormal, eventTag: "STOPPED ON RUNWAY REPORT"
            ))
            globalTurn += 1

            executedContingencies.append(abtCont)
            return exchanges

        } else if let bStrikeCont = contingencies.first(where: { $0.title.contains("Bird Strike on Take-off") }) {
            isFlightTerminatedEarly = true

            // Pilot-Initiated Abort (ICAO Doc 9432 Bab 4.5.12): Flock crossing alert -> Bird strike reject
            exchanges.append(FilledExchange(
                exchangeID: "DIS-BRD-STRK-1", templateID: "DIS-BRD-STRK", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), caution large flock of birds crossing runway ahead near threshold!",
                criticalSlots: [], severity: .abnormal, eventTag: "FLOCK CROSSING WARNING"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "DIS-BRD-STRK-2", templateID: "DIS-BRD-STRK", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "STOPPING, ABORTING TAKE-OFF, BIRD STRIKE ENGINE NUMBER TWO, \(callsign)!",
                criticalSlots: [
                    CriticalSlot(slot: "STOPPING", expectedValue: "stopping", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "ABORT_TAKEOFF", expectedValue: "aborting take-off", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "BIRD STRIKE ABORT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "DIS-BRD-STRK-3", templateID: "DIS-BRD-STRK", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "STOP IMMEDIATELY, \(callsign), STOP IMMEDIATELY, emergency equipment alerted and rolling to your position!",
                criticalSlots: [], severity: .distress, eventTag: "STOP IMMEDIATELY & ARFF"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "DIS-BRD-STRK-4", templateID: "DIS-BRD-STRK", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Stopped on runway \(rwySpoken), bird strike engine number two, vibration, engine shut down, brakes hot, request fire crew inspection, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "STOPPED_RUNWAY", expectedValue: "stopped on runway", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "STOPPED BIRD STRIKE"
            ))
            globalTurn += 1

            executedContingencies.append(bStrikeCont)
            return exchanges

        } else if let efatoCont = contingencies.first(where: { $0.title.contains("EFATO") }) {
            isFlightTerminatedEarly = true

            exchanges.append(FilledExchange(
                exchangeID: "DIS-EFA-1", templateID: "DIS-EFA", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), verify airborne, smoke reported from engine!",
                criticalSlots: [], severity: .distress, eventTag: "SMOKE REPORTED"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "DIS-EFA-2", templateID: "DIS-EFA", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "MAYDAY MAYDAY MAYDAY, \(twrUnit), \(callsign), engine failure after takeoff at five hundred feet, forced landing straight ahead runway \(rwySpoken), two persons on board!",
                criticalSlots: [
                    CriticalSlot(slot: "DISTRESS", expectedValue: "mayday mayday mayday", type: "mandatoryDistress"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "MAYDAY EFATO"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "DIS-EFA-3", templateID: "DIS-EFA", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(twrUnit), roger MAYDAY, runway \(rwySpoken), wind \(windSpoken), cleared to land, emergency equipment rolling.",
                criticalSlots: [], severity: .distress, eventTag: "CLEARED TO LAND EMERGENCY"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "DIS-EFA-4", templateID: "DIS-EFA", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(rwySpoken), cleared to land, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: rwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CLEARED_TO_LAND", expectedValue: "cleared to land", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "READBACK EMERGENCY LANDING"
            ))
            globalTurn += 1

            executedContingencies.append(efatoCont)
            return exchanges
        }

        // STEP 6: AIRBORNE HANDOFF (Continuing flights)
        exchanges.append(FilledExchange(
            exchangeID: "DP-ABN-1", templateID: "DP-05", turn: globalTurn, speaker: "ATC",
            isUserTurn: (role == .atc),
            text: "\(callsign), airborne time zero four, contact Departure \(context.depFreq).",
            criticalSlots: [], severity: .normal, eventTag: "AIRBORNE HANDOFF"
        ))
        globalTurn += 1

        exchanges.append(FilledExchange(
            exchangeID: "DP-ABN-2", templateID: "DP-05", turn: globalTurn, speaker: "PILOT",
            isUserTurn: (role == .pilot),
            text: "Departure \(context.depFreq), \(callsign).",
            criticalSlots: [
                CriticalSlot(slot: "DEPARTURE_FREQ", expectedValue: context.depFreq, type: "mandatoryFrequency"),
                CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
            ], severity: .normal, eventTag: "READBACK DEPARTURE FREQ"
        ))
        globalTurn += 1

        return exchanges
    }
    // MARK: - Phase 3: En-Route Builder
    private func buildEnRouteExchanges(
        level: CurriculumLevel,
        seed: Int,
        role: UserRole,
        context: SlotContext,
        contingencies: [InjectedContingency],
        executedContingencies: inout [InjectedContingency],
        globalTurn: inout Int
    ) -> [FilledExchange] {
        var exchanges: [FilledExchange] = []
        let callsign = context.callsign
        let ctrlUnit = context.unitControl?.callsign ?? "Control"
        let cruisingLevel = context.currentLevel
        let curPos = context.currentPosition
        let nextPos = context.nextPosition

        // 1. Weather Deviation (CB Avoidance)
        if let wxCont = contingencies.first(where: { $0.title.contains("Weather Deviation") }) {
            exchanges.append(FilledExchange(
                exchangeID: "ER-WX-1", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), radar contact, climb and maintain \(cruisingLevel), advise if weather avoidance required.",
                criticalSlots: [], severity: .normal, eventTag: "RADAR CONTACT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-WX-DEV-1", templateID: "ABN-WX-DEV", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(ctrlUnit), \(callsign), request deviation one five miles right of track due weather.",
                criticalSlots: [
                    CriticalSlot(slot: "REQUEST", expectedValue: "request deviation", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "REASON", expectedValue: "weather", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .abnormal, eventTag: "WEATHER DEVIATION REQUEST"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-WX-DEV-2", templateID: "ABN-WX-DEV", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), deviation one five miles right of track approved, advise when able to resume flight planned route.",
                criticalSlots: [], severity: .normal, eventTag: "DEVIATION APPROVED"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-WX-DEV-3", templateID: "ABN-WX-DEV", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Deviation one five miles right of track approved, will report resuming navigation, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "DIRECTION", expectedValue: "right of track", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK DEVIATION"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-WX-DEV-4", templateID: "ABN-WX-DEV", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), advise clear of weather.",
                criticalSlots: [], severity: .normal, eventTag: "ADVISE CLEAR"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-WX-DEV-5", templateID: "ABN-WX-DEV", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(ctrlUnit), \(callsign), clear of weather, request resume own navigation direct \(nextPos).",
                criticalSlots: [
                    CriticalSlot(slot: "CLEAR_WX", expectedValue: "clear of weather", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "CLEAR OF WEATHER"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-WX-DEV-6", templateID: "ABN-WX-DEV", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), resume own navigation direct \(nextPos), maintain \(cruisingLevel).",
                criticalSlots: [], severity: .normal, eventTag: "RESUME OWN NAVIGATION"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-WX-DEV-7", templateID: "ABN-WX-DEV", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Resume own navigation direct \(nextPos), maintain \(cruisingLevel), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "WAYPOINT", expectedValue: nextPos, type: "mandatoryWaypoint"),
                    CriticalSlot(slot: "ALTITUDE", expectedValue: cruisingLevel, type: "mandatoryAltitude"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK RESUME NAVIGATION"
            ))
            globalTurn += 1

            executedContingencies.append(wxCont)
            return exchanges

        // 2. Radar Avoiding Action (Near Miss)
        } else if let avoidCont = contingencies.first(where: { $0.title.contains("Avoiding Action") }) {
            exchanges.append(FilledExchange(
                exchangeID: "ER-AVD-1", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), radar contact, climb and maintain \(cruisingLevel).",
                criticalSlots: [], severity: .normal, eventTag: "RADAR CONTACT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-AVD-2", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Climb and maintain \(cruisingLevel), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: cruisingLevel, type: "mandatoryAltitude"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CLIMB"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-AVD-1", templateID: "ABN-AVD", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), AVOIDING ACTION, turn left immediately heading two seven zero, traffic twelve o'clock four miles opposite direction converging!",
                criticalSlots: [], severity: .distress, eventTag: "RADAR AVOIDING ACTION"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-AVD-2", templateID: "ABN-AVD", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Turning left immediately heading two seven zero, avoiding action, \(callsign)!",
                criticalSlots: [
                    CriticalSlot(slot: "HEADING", expectedValue: "heading two seven zero", type: "mandatoryHeading"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "READBACK AVOIDING ACTION"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-AVD-3", templateID: "ABN-AVD", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), clear of traffic, resume own navigation direct \(nextPos), maintain \(cruisingLevel).",
                criticalSlots: [], severity: .normal, eventTag: "CLEAR OF TRAFFIC"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-AVD-4", templateID: "ABN-AVD", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Resume own navigation direct \(nextPos), maintain \(cruisingLevel), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "WAYPOINT", expectedValue: nextPos, type: "mandatoryWaypoint"),
                    CriticalSlot(slot: "ALTITUDE", expectedValue: cruisingLevel, type: "mandatoryAltitude"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CLEAR OF TRAFFIC"
            ))
            globalTurn += 1

            executedContingencies.append(avoidCont)
            return exchanges

        // 3. Mid-Air Engine Failure (Diversion ASSIST)
        } else if let engOut = contingencies.first(where: { $0.title.contains("Mid-Air Engine") }) {
            exchanges.append(FilledExchange(
                exchangeID: "ER-ENG-1", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), radar contact, maintain \(cruisingLevel).",
                criticalSlots: [], severity: .normal, eventTag: "RADAR CONTACT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-ENG-2", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "MAYDAY MAYDAY MAYDAY, \(ctrlUnit), \(callsign), engine number one failed, unable to maintain \(cruisingLevel), request descent and diversion to nearest airport, heading two four zero!",
                criticalSlots: [
                    CriticalSlot(slot: "DISTRESS", expectedValue: "mayday mayday mayday", type: "mandatoryDistress"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "MAYDAY ENGINE OUT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-ENG-3", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), roger MAYDAY, descend and maintain flight level one zero zero, turn left heading two four zero for radar vectors direct Juanda, QNH one zero one two.",
                criticalSlots: [], severity: .distress, eventTag: "DESCENT & VECTORS MAYDAY"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-ENG-4", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Descend and maintain flight level one zero zero, turn left heading two four zero, QNH one zero one two, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "flight level one zero zero", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "HEADING", expectedValue: "heading two four zero", type: "mandatoryHeading"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "READBACK DESCENT MAYDAY"
            ))
            globalTurn += 1

            executedContingencies.append(engOut)
            return exchanges

        // 4. Cabin Decompression Emergency Descent
        } else if let decompCont = contingencies.first(where: { $0.title.contains("Decompression") }) {
            exchanges.append(FilledExchange(
                exchangeID: "ER-DEC-1", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), radar contact, maintaining \(cruisingLevel).",
                criticalSlots: [], severity: .normal, eventTag: "RADAR CONTACT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-DEC-2", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "MAYDAY MAYDAY MAYDAY, \(ctrlUnit), \(callsign), rapid decompression, emergency descent flight level one zero zero, turning right heading one eight zero!",
                criticalSlots: [
                    CriticalSlot(slot: "DISTRESS", expectedValue: "mayday mayday mayday", type: "mandatoryDistress"),
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "flight level one zero zero", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "MAYDAY EMERGENCY DESCENT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-DEC-3", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), roger emergency descent, cleared flight level one zero zero, turn right heading one eight zero, QNH one zero one zero, airspace clear.",
                criticalSlots: [], severity: .distress, eventTag: "CLEARED EMERGENCY DESCENT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-DEC-4", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Cleared flight level one zero zero, heading one eight zero, QNH one zero one zero, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "flight level one zero zero", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "READBACK EMERGENCY DESCENT"
            ))
            globalTurn += 1

            executedContingencies.append(decompCont)
            return exchanges

        // 5. TCAS Resolution Advisory
        } else if let tcasCont = contingencies.first(where: { $0.title.contains("TCAS") }) {
            exchanges.append(FilledExchange(
                exchangeID: "ER-TCAS-1", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), climb and maintain flight level two eight zero.",
                criticalSlots: [], severity: .normal, eventTag: "CLIMB INSTRUCTION"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-TCAS-2", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "TCAS RA, \(callsign)!",
                criticalSlots: [
                    CriticalSlot(slot: "TCAS_RA", expectedValue: "tcas ra", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .distress, eventTag: "TCAS RA NOTIFICATION"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-TCAS-3", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), roger.",
                criticalSlots: [], severity: .normal, eventTag: "ROGER TCAS"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-TCAS-4", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Clear of conflict, flight level two six zero, resuming flight level two four zero, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "CLEAR_OF_CONFLICT", expectedValue: "clear of conflict", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "CLEAR OF CONFLICT"
            ))
            globalTurn += 1

            executedContingencies.append(tcasCont)
            return exchanges
        }

        // Routine En-Route:
        if level == .level1 {
            let activeRwy = SpokenFormFormatter.runway(context.selectedRunway.designator)
            let qnhSpoken = SpokenFormFormatter.qnh(context.weather.qnh)
            exchanges.append(FilledExchange(
                exchangeID: "ER-VFR-1", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(context.unitTower?.callsign ?? "Tower"), radar contact south training area, maintain visual flight rules three thousand feet, report maneuvers completed.",
                criticalSlots: [], severity: .normal, eventTag: "RADAR CONTACT VFR"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-VFR-2", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Maintain visual flight rules three thousand feet, will report maneuvers completed, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK VFR"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-VFR-3", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), advise intentions.",
                criticalSlots: [], severity: .normal, eventTag: "ADVISE INTENTIONS"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-VFR-4", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(context.unitTower?.callsign ?? "Tower"), \(callsign), training maneuvers completed, request inbound for circuit touch-and-go.",
                criticalSlots: [
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "REQUEST INBOUND"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-VFR-5", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), join right downwind runway \(activeRwy), QNH \(qnhSpoken), report downwind.",
                criticalSlots: [], severity: .normal, eventTag: "JOIN DOWNWIND"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-VFR-6", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Join right downwind runway \(activeRwy), QNH \(qnhSpoken), will report downwind, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: activeRwy, type: "mandatoryRunway"),
                    CriticalSlot(slot: "QNH", expectedValue: qnhSpoken, type: "mandatoryQnh"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK DOWNWIND"
            ))
            globalTurn += 1

        } else if level == .level2 {
            // BWX - DPS (55 NM, cruising FL080)
            exchanges.append(FilledExchange(
                exchangeID: "ER-L2-1", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), radar contact, climb and maintain flight level zero eight zero, report reaching.",
                criticalSlots: [], severity: .normal, eventTag: "RADAR CONTACT FL080"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-L2-2", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Climb and maintain flight level zero eight zero, will report reaching, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "flight level zero eight zero", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CLIMB"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-L2-3", templateID: "ER-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), report level flight level zero eight zero.",
                criticalSlots: [], severity: .normal, eventTag: "REPORT LEVEL"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-L2-4", templateID: "ER-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(ctrlUnit), \(callsign), reaching flight level zero eight zero.",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "flight level zero eight zero", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "REPORT REACHING LEVEL"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-L2-5", templateID: "ER-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), roger, maintain flight level zero eight zero, direct \(nextPos).",
                criticalSlots: [], severity: .normal, eventTag: "MAINTAIN CRUISE"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-L2-6", templateID: "ER-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Maintain flight level zero eight zero, direct \(nextPos), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "flight level zero eight zero", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "WAYPOINT", expectedValue: nextPos, type: "mandatoryWaypoint"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CRUISE"
            ))
            globalTurn += 1

        } else {
            // Levels 3, 4, 5: Jet transport cruising
            exchanges.append(FilledExchange(
                exchangeID: "ER-JET-1", templateID: "ER-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), radar contact, climb and maintain \(cruisingLevel), direct \(curPos).",
                criticalSlots: [], severity: .normal, eventTag: "RADAR CONTACT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-JET-2", templateID: "ER-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Climb and maintain \(cruisingLevel), direct \(curPos), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: cruisingLevel, type: "mandatoryAltitude"),
                    CriticalSlot(slot: "WAYPOINT", expectedValue: curPos, type: "mandatoryWaypoint"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CLIMB"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-JET-3", templateID: "ER-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), report reaching \(cruisingLevel).",
                criticalSlots: [], severity: .normal, eventTag: "REPORT LEVEL"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-JET-4", templateID: "ER-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(ctrlUnit), \(callsign), reaching \(cruisingLevel).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: cruisingLevel, type: "mandatoryAltitude"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "REACHING LEVEL"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-JET-5", templateID: "ER-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), roger, maintain \(cruisingLevel).",
                criticalSlots: [], severity: .normal, eventTag: "MAINTAIN LEVEL"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ER-JET-6", templateID: "ER-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Maintain \(cruisingLevel), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: cruisingLevel, type: "mandatoryAltitude"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK MAINTAIN"
            ))
            globalTurn += 1
        }

        return exchanges
    }

    // MARK: - Phase 4: Arrival Builder (Full ICAO STAR Profile & Constraints)
    private func buildArrivalExchanges(
        level: CurriculumLevel,
        seed: Int,
        role: UserRole,
        context: SlotContext,
        contingencies: [InjectedContingency],
        executedContingencies: inout [InjectedContingency],
        globalTurn: inout Int
    ) -> [FilledExchange] {
        var exchanges: [FilledExchange] = []
        let callsign = context.callsign
        let ctrlUnit = context.unitControl?.callsign ?? "Control"
        let appUnit = context.unitApproach?.callsign ?? "Approach"
        let appFreq = context.approachFreq
        let starName = context.starProcedure
        let qnhSpoken = SpokenFormFormatter.qnh(context.weather.qnh)
        let arrRwySpoken = context.arrRunway
        let _ = context.destinationName

        // Emergency / Urgency: Passenger Medical Emergency
        if let medCont = contingencies.first(where: { $0.title.contains("Medical") }) {
            exchanges.append(FilledExchange(
                exchangeID: "AR-MED-1", templateID: "AR-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), advise status for descent.",
                criticalSlots: [], severity: .normal, eventTag: "ADVISE DESCENT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-MED-1", templateID: "ABN-MED", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "PAN PAN, PAN PAN, PAN PAN, passenger suspected heart attack on board, request priority straight-in approach runway \(arrRwySpoken) and ambulance to meet aircraft at gate!",
                criticalSlots: [
                    CriticalSlot(slot: "URGENCY", expectedValue: "pan pan, pan pan, pan pan", type: "mandatoryUrgency"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .urgency, eventTag: "PAN PAN MEDICAL PRIORITY"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-MED-2", templateID: "ABN-MED", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), priority straight-in approach runway \(arrRwySpoken) approved, descend to three thousand feet, QNH \(qnhSpoken), medical ambulance standing by. Contact \(appUnit) \(appFreq).",
                criticalSlots: [], severity: .urgency, eventTag: "PRIORITY STRAIGHT-IN APPROVED"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "ABN-MED-3", templateID: "ABN-MED", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Priority straight-in approach runway \(arrRwySpoken), descend three thousand feet, QNH \(qnhSpoken), contact \(appUnit) \(appFreq), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "three thousand feet", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "QNH", expectedValue: qnhSpoken, type: "mandatoryQnh"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .urgency, eventTag: "READBACK MEDICAL"
            ))
            globalTurn += 1

            executedContingencies.append(medCont)
            return exchanges
        }

        if level == .level1 {
            // Level 1: Local VFR traffic pattern rejoin (4 turns)
            exchanges.append(FilledExchange(
                exchangeID: "AR-VFR-1", templateID: "AR-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), five miles south, descend to altitude one thousand five hundred feet, QNH \(qnhSpoken), report airfield in sight.",
                criticalSlots: [], severity: .normal, eventTag: "DESCEND PATTERN ALTITUDE"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-VFR-2", templateID: "AR-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Descend to altitude one thousand five hundred feet, QNH \(qnhSpoken), will report airfield in sight, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "one thousand five hundred feet", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "QNH", expectedValue: qnhSpoken, type: "mandatoryQnh"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK ALTITUDE & QNH"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-VFR-3", templateID: "AR-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), join right downwind runway \(arrRwySpoken), QNH \(qnhSpoken), report downwind.",
                criticalSlots: [], severity: .normal, eventTag: "JOIN RIGHT DOWNWIND"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-VFR-4", templateID: "AR-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Join right downwind runway \(arrRwySpoken), QNH \(qnhSpoken), will report downwind, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "QNH", expectedValue: qnhSpoken, type: "mandatoryQnh"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK DOWNWIND"
            ))
            globalTurn += 1

        } else if level == .level2 {
            // Level 2: Point-to-Point BWX -> DPS (Cruising FL080 -> Descent to 4000ft, BLI VOR constraint, 6 turns)
            exchanges.append(FilledExchange(
                exchangeID: "AR-L2-1", templateID: "AR-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), when ready descend to altitude four thousand feet, QNH \(qnhSpoken), cleared \(starName) arrival.",
                criticalSlots: [], severity: .normal, eventTag: "DESCENT CLEARANCE 4000FT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-L2-2", templateID: "AR-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Descend to altitude four thousand feet, QNH \(qnhSpoken), cleared \(starName) arrival, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "altitude four thousand feet", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "QNH", expectedValue: qnhSpoken, type: "mandatoryQnh"),
                    CriticalSlot(slot: "STAR", expectedValue: starName, type: "mandatoryStar"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK DESCENT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-L2-3", templateID: "AR-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), cross BLI VOR at altitude four thousand feet, speed two zero zero knots or less.",
                criticalSlots: [], severity: .normal, eventTag: "WAYPOINT & SPEED CONSTRAINT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-L2-4", templateID: "AR-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Cross BLI VOR at altitude four thousand feet, speed two zero zero knots, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "WAYPOINT", expectedValue: "BLI VOR", type: "mandatoryWaypoint"),
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "four thousand feet", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "SPEED", expectedValue: "two zero zero knots", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CONSTRAINT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-L2-5", templateID: "AR-03", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), contact \(appUnit) \(appFreq).",
                criticalSlots: [], severity: .normal, eventTag: "TRANSFER APPROACH"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-L2-6", templateID: "AR-03", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(appUnit) \(appFreq), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "APPROACH_FREQ", expectedValue: appFreq, type: "mandatoryFrequency"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK TRANSFER"
            ))
            globalTurn += 1

        } else {
            // Jet Commercial Routes (Levels 3, 4, 5): Full ICAO STAR & Descent Step-Down Profile (8 turns)
            let starFix: String
            switch level {
            case .level3: starFix = "POSOP"
            case .level4: starFix = "GANDI"
            case .level5: starFix = "BUNTA"
            default: starFix = "DOLTA"
            }

            // Step 1: Top of Descent Clearance to FL100 via STAR
            exchanges.append(FilledExchange(
                exchangeID: "AR-JET-1", templateID: "AR-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(ctrlUnit), when ready descend to flight level one zero zero, cleared \(starName) arrival.",
                criticalSlots: [], severity: .normal, eventTag: "DESCENT CLEARANCE FL100"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-JET-2", templateID: "AR-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Descend to flight level one zero zero, cleared \(starName) arrival, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "flight level one zero zero", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "STAR", expectedValue: starName, type: "mandatoryStar"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK DESCENT FL100"
            ))
            globalTurn += 1

            // Step 2: Waypoint Crossing Altitude & Speed Constraint (ICAO Doc 9432 Section 6.4)
            exchanges.append(FilledExchange(
                exchangeID: "AR-JET-3", templateID: "AR-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), cross \(starFix) at flight level one four zero, speed two two zero knots or less.",
                criticalSlots: [], severity: .normal, eventTag: "WAYPOINT & SPEED CONSTRAINT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-JET-4", templateID: "AR-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Cross \(starFix) at flight level one four zero, speed two two zero knots, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "WAYPOINT", expectedValue: starFix, type: "mandatoryWaypoint"),
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "flight level one four zero", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "SPEED", expectedValue: "two two zero knots", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CONSTRAINT"
            ))
            globalTurn += 1

            // Step 3: Transition Level Altimeter Setting & Descent to 5,000 ft (ICAO Doc 9432 Section 7.2)
            exchanges.append(FilledExchange(
                exchangeID: "AR-JET-5", templateID: "AR-03", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), descend to altitude five thousand feet, QNH \(qnhSpoken), transition level flight level zero seven zero.",
                criticalSlots: [], severity: .normal, eventTag: "ALTIMETER & TRANSITION LEVEL"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-JET-6", templateID: "AR-03", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Leaving flight level one zero zero descending altitude five thousand feet, QNH \(qnhSpoken), transition level zero seven zero, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "altitude five thousand feet", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "QNH", expectedValue: qnhSpoken, type: "mandatoryQnh"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK ALTIMETER"
            ))
            globalTurn += 1

            // Step 4: Frequency Handoff to Approach Control Unit
            exchanges.append(FilledExchange(
                exchangeID: "AR-JET-7", templateID: "AR-04", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), contact \(appUnit) \(appFreq).",
                criticalSlots: [], severity: .normal, eventTag: "TRANSFER APPROACH"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AR-JET-8", templateID: "AR-04", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(appUnit) \(appFreq), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "APPROACH_FREQ", expectedValue: appFreq, type: "mandatoryFrequency"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK TRANSFER"
            ))
            globalTurn += 1
        }

        return exchanges
    }

    // MARK: - Phase 5: Approach Builder (Full ICAO Radar Vectoring & Final Intercept)
    private func buildApproachExchanges(
        level: CurriculumLevel,
        seed: Int,
        role: UserRole,
        context: SlotContext,
        contingencies: [InjectedContingency],
        executedContingencies: inout [InjectedContingency],
        globalTurn: inout Int
    ) -> [FilledExchange] {
        var exchanges: [FilledExchange] = []
        let callsign = context.callsign
        let appUnit = context.unitApproach?.callsign ?? "Approach"
        let twrUnit = context.unitTower?.callsign ?? "Tower"
        let twrFreq = SpokenFormFormatter.frequency(context.unitTower?.frequency ?? "118.100")
        let arrRwySpoken = context.arrRunway
        let qnhSpoken = SpokenFormFormatter.qnh(context.weather.qnh)
        let windSpoken = SpokenFormFormatter.wind(direction: context.weather.windDirection, knots: context.weather.windSpeed)

        // ==========================================
        // CONTINGENCY 1: UNSAFE GEAR INDICATION (VOR HOLDING & RE-APPROACH)
        // ==========================================
        if let gearCont = contingencies.first(where: { $0.title.contains("Unsafe") || $0.title.contains("Gear") }) {
            let holdingFix = context.holdingFix

            // Turn 1: ATC Approach radar vector
            exchanges.append(FilledExchange(
                exchangeID: "AP-GEAR-1", templateID: "AP-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(appUnit), radar contact, descend and maintain two thousand five hundred feet, QNH \(qnhSpoken), vectoring for ILS runway \(arrRwySpoken).",
                criticalSlots: [], severity: .normal, eventTag: "DESCEND & VECTOR"
            ))
            globalTurn += 1

            // Turn 2: PILOT reports unsafe gear indication & requests holding over VOR
            exchanges.append(FilledExchange(
                exchangeID: "AP-GEAR-2", templateID: "AP-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "PAN PAN, PAN PAN, PAN PAN, \(appUnit), \(callsign), unsafe landing gear indication, nose gear unsafe red light, going around, request climb to four thousand feet and holding over \(holdingFix) to troubleshoot checklist!",
                criticalSlots: [
                    CriticalSlot(slot: "URGENCY", expectedValue: "pan pan, pan pan, pan pan", type: "mandatoryUrgency"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .urgency, eventTag: "PAN PAN UNSAFE GEAR"
            ))
            globalTurn += 1

            // Turn 3: ATC Approves go-around & holding over fix
            exchanges.append(FilledExchange(
                exchangeID: "AP-GEAR-3", templateID: "AP-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), roger PAN PAN, climb straight ahead to four thousand feet, proceed direct \(holdingFix) and hold as published, report ready for approach.",
                criticalSlots: [], severity: .urgency, eventTag: "HOLDING INSTRUCTION"
            ))
            globalTurn += 1

            // Turn 4: PILOT Readback holding
            exchanges.append(FilledExchange(
                exchangeID: "AP-GEAR-4", templateID: "AP-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Climb four thousand feet, direct \(holdingFix) and hold, will report ready, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "four thousand feet", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "HOLDING_FIX", expectedValue: holdingFix, type: "mandatoryWaypoint"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .urgency, eventTag: "READBACK HOLDING"
            ))
            globalTurn += 1

            // Turn 5: ATC query status
            exchanges.append(FilledExchange(
                exchangeID: "AP-GEAR-5", templateID: "AP-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), advise status and gear indication.",
                criticalSlots: [], severity: .normal, eventTag: "ADVISE GEAR STATUS"
            ))
            globalTurn += 1

            // Turn 6: PILOT reports 3 green lights & requests second ILS approach
            exchanges.append(FilledExchange(
                exchangeID: "AP-GEAR-6", templateID: "AP-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Checklist completed, manual gear extension deployed, three green lights confirmed, ready to leave holding, request radar vectors for ILS runway \(arrRwySpoken), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "THREE_GREEN", expectedValue: "three green lights", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "GEAR DOWN THREE GREEN"
            ))
            globalTurn += 1

            // Turn 7: ATC Clears ILS approach & handoff to Tower
            exchanges.append(FilledExchange(
                exchangeID: "AP-GEAR-7", templateID: "AP-03", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), leave \(holdingFix) heading zero niner zero, descend two thousand five hundred feet, cleared ILS approach runway \(arrRwySpoken), contact Tower \(twrFreq).",
                criticalSlots: [], severity: .normal, eventTag: "CLEARED ILS APPROACH"
            ))
            globalTurn += 1

            // Turn 8: PILOT Readback
            exchanges.append(FilledExchange(
                exchangeID: "AP-GEAR-8", templateID: "AP-03", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Leave \(holdingFix) heading zero niner zero, descend two thousand five hundred feet, cleared ILS runway \(arrRwySpoken), Tower \(twrFreq), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "TOWER_FREQ", expectedValue: twrFreq, type: "mandatoryFrequency"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK ILS"
            ))
            globalTurn += 1

            // Turn 9: Tower Cleared to Land
            exchanges.append(FilledExchange(
                exchangeID: "AP-GEAR-9", templateID: "AP-04", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(twrUnit), runway \(arrRwySpoken), wind \(windSpoken), cleared to land.",
                criticalSlots: [], severity: .normal, eventTag: "CLEARED TO LAND"
            ))
            globalTurn += 1

            // Turn 10: PILOT Readback Cleared to Land
            exchanges.append(FilledExchange(
                exchangeID: "AP-GEAR-10", templateID: "AP-04", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(arrRwySpoken), cleared to land, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CLEARED_TO_LAND", expectedValue: "cleared to land", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CLEARED TO LAND"
            ))
            globalTurn += 1

            executedContingencies.append(gearCont)
            return exchanges

        // ==========================================
        // CONTINGENCY 2: UNCLEARED GO-AROUND (NO CLEARANCE RECEIVED AT DH)
        // ==========================================
        } else if let gaCont = contingencies.first(where: { $0.title.contains("Uncleared") || $0.title.contains("Go-Around") }) {
            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-1", templateID: "AP-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(appUnit), radar contact, vectoring for ILS runway \(arrRwySpoken), turn heading zero seven zero, descend two thousand five hundred feet.",
                criticalSlots: [], severity: .normal, eventTag: "RADAR VECTORS"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-2", templateID: "AP-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Heading zero seven zero, descend two thousand five hundred feet, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "HEADING", expectedValue: "heading zero seven zero", type: "mandatoryHeading"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK VECTORS"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-3", templateID: "AP-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), cleared ILS approach runway \(arrRwySpoken), contact Tower \(twrFreq).",
                criticalSlots: [], severity: .normal, eventTag: "CLEARED ILS"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-4", templateID: "AP-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Cleared ILS runway \(arrRwySpoken), Tower \(twrFreq), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK ILS"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-5", templateID: "AP-03", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(twrUnit), four miles final, continue approach, preceding traffic clearing runway.",
                criticalSlots: [], severity: .normal, eventTag: "CONTINUE APPROACH"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-6", templateID: "AP-03", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Continuing approach, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "CONTINUING"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-7", templateID: "AP-04", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Going around, no landing clearance received at decision altitude, \(callsign)!",
                criticalSlots: [
                    CriticalSlot(slot: "GOING_AROUND", expectedValue: "going around", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .urgency, eventTag: "PILOT INITIATED GO-AROUND"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-8", templateID: "AP-04", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), acknowledge go-around, climb straight ahead four thousand feet, contact Approach \(context.approachFreq).",
                criticalSlots: [], severity: .urgency, eventTag: "GO-AROUND ACKNOWLEDGED"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-9", templateID: "AP-05", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Climb four thousand feet, contact Approach \(context.approachFreq), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "four thousand feet", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "APPROACH_FREQ", expectedValue: context.approachFreq, type: "mandatoryFrequency"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK GO-AROUND"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-10", templateID: "AP-05", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(twrUnit), runway \(arrRwySpoken), wind \(windSpoken), cleared to land.",
                criticalSlots: [], severity: .normal, eventTag: "CLEARED TO LAND SECOND"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-GA-11", templateID: "AP-05", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(arrRwySpoken), cleared to land, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CLEARED_TO_LAND", expectedValue: "cleared to land", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CLEARED TO LAND"
            ))
            globalTurn += 1

            executedContingencies.append(gaCont)
            return exchanges

        // ==========================================
        // CONTINGENCY 3: FLAP SYSTEM FAILURE (HIGH SPEED APPROACH)
        // ==========================================
        } else if let flapCont = contingencies.first(where: { $0.title.contains("Flap") }) {
            exchanges.append(FilledExchange(
                exchangeID: "AP-FLP-1", templateID: "AP-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(appUnit), radar contact, descend to three thousand feet, QNH \(qnhSpoken).",
                criticalSlots: [], severity: .normal, eventTag: "RADAR CONTACT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-FLP-2", templateID: "AP-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "PAN PAN, PAN PAN, PAN PAN, \(appUnit), \(callsign), flap system failure, unable to extend flaps, approach speed one six zero knots, request priority straight-in approach runway \(arrRwySpoken)!",
                criticalSlots: [
                    CriticalSlot(slot: "URGENCY", expectedValue: "pan pan, pan pan, pan pan", type: "mandatoryUrgency"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .urgency, eventTag: "PAN PAN FLAP FAILURE"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-FLP-3", templateID: "AP-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), roger PAN PAN, priority straight-in approach approved runway \(arrRwySpoken), descend two thousand five hundred feet, straight-in ILS runway \(arrRwySpoken), contact Tower \(twrFreq).",
                criticalSlots: [], severity: .urgency, eventTag: "PRIORITY STRAIGHT-IN APPROVED"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-FLP-4", templateID: "AP-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Priority straight-in ILS runway \(arrRwySpoken), Tower \(twrFreq), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "TOWER_FREQ", expectedValue: twrFreq, type: "mandatoryFrequency"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .urgency, eventTag: "READBACK STRAIGHT-IN"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-FLP-5", templateID: "AP-03", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(twrUnit), runway \(arrRwySpoken), wind \(windSpoken), cleared to land.",
                criticalSlots: [], severity: .normal, eventTag: "CLEARED TO LAND"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-FLP-6", templateID: "AP-03", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(arrRwySpoken), cleared to land, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CLEARED_TO_LAND", expectedValue: "cleared to land", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CLEARED TO LAND"
            ))
            globalTurn += 1

            executedContingencies.append(flapCont)
            return exchanges
        }

        // ==========================================
        // ROUTINE & PROCEDURAL APPROACHES (LEVEL 1 VFR vs LEVEL 2-5 IFR)
        // ==========================================
        if level == .level1 {
            // Level 1: Visual traffic pattern turning base, final, and touch-and-go (6 turns)
            exchanges.append(FilledExchange(
                exchangeID: "AP-VFR-1", templateID: "AP-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(twrUnit), report turning base runway \(arrRwySpoken).",
                criticalSlots: [], severity: .normal, eventTag: "REPORT BASE"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-VFR-2", templateID: "AP-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Turning base runway \(arrRwySpoken), gear down, three green, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "TURNING BASE"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-VFR-3", templateID: "AP-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), report final runway \(arrRwySpoken).",
                criticalSlots: [], severity: .normal, eventTag: "REPORT FINAL"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-VFR-4", templateID: "AP-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Final runway \(arrRwySpoken), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "REPORTING FINAL"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-VFR-5", templateID: "AP-03", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), runway \(arrRwySpoken), wind \(windSpoken), cleared touch-and-go, make left traffic.",
                criticalSlots: [], severity: .normal, eventTag: "CLEARED TOUCH AND GO"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-VFR-6", templateID: "AP-03", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(arrRwySpoken), cleared touch-and-go, make left traffic, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CLEARED_TOUCH_AND_GO", expectedValue: "cleared touch-and-go, make left traffic", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK TOUCH AND GO"
            ))
            globalTurn += 1

        } else {
            // Levels 2, 3, 4, 5: Full ICAO Radar Vectoring, Speed Sequencing, ILS Intercept, & Landing Clearance (10-12 turns)
            let baseHeading: String
            let interceptHeading: String
            let interceptSpeed: String

            switch level {
            case .level2:
                baseHeading = "heading zero six zero"
                interceptHeading = "heading zero seven zero"
                interceptSpeed = "one six zero knots"
            case .level3:
                baseHeading = "heading zero six zero"
                interceptHeading = "heading zero seven zero"
                interceptSpeed = "one eight zero knots"
            case .level4:
                baseHeading = "heading zero eight zero"
                interceptHeading = "heading zero niner zero"
                interceptSpeed = "one eight zero knots"
            case .level5:
                baseHeading = "heading zero one zero"
                interceptHeading = "heading two eight zero"
                interceptSpeed = "one eight zero knots"
            default:
                baseHeading = "heading zero one zero"
                interceptHeading = "heading two eight zero"
                interceptSpeed = "one eight zero knots"
            }

            // Step 1: Initial Vectoring for ILS & Base Leg Heading (ICAO Doc 9432 Section 7.5)
            exchanges.append(FilledExchange(
                exchangeID: "AP-ILS-1", templateID: "AP-01", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(appUnit), radar contact, vectoring for ILS approach runway \(arrRwySpoken), turn \(baseHeading), descend and maintain three thousand feet, QNH \(qnhSpoken).",
                criticalSlots: [], severity: .normal, eventTag: "RADAR VECTORS & BASE LEG"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-ILS-2", templateID: "AP-01", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Turn \(baseHeading), descend and maintain three thousand feet, QNH \(qnhSpoken), vectoring for ILS runway \(arrRwySpoken), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "HEADING", expectedValue: baseHeading, type: "mandatoryHeading"),
                    CriticalSlot(slot: "ALTITUDE", expectedValue: "three thousand feet", type: "mandatoryAltitude"),
                    CriticalSlot(slot: "QNH", expectedValue: qnhSpoken, type: "mandatoryQnh"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK VECTORS"
            ))
            globalTurn += 1

            // Step 2: Speed Reduction & Intercept Heading (ICAO Doc 9432 Section 7.5.1)
            exchanges.append(FilledExchange(
                exchangeID: "AP-ILS-3", templateID: "AP-02", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), reduce speed \(interceptSpeed), turn \(interceptHeading), cleared ILS approach runway \(arrRwySpoken), report established on localizer.",
                criticalSlots: [], severity: .normal, eventTag: "SPEED CONTROL & INTERCEPT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-ILS-4", templateID: "AP-02", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Reduce speed \(interceptSpeed), turn \(interceptHeading), cleared ILS runway \(arrRwySpoken), will report established, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "SPEED", expectedValue: interceptSpeed, type: "mandatoryKeyword"),
                    CriticalSlot(slot: "HEADING", expectedValue: interceptHeading, type: "mandatoryHeading"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK INTERCEPT"
            ))
            globalTurn += 1

            // Step 3: Localizer Established Confirmation Prompt & Established Call
            exchanges.append(FilledExchange(
                exchangeID: "AP-ILS-5", templateID: "AP-03", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), report localizer established.",
                criticalSlots: [], severity: .normal, eventTag: "REPORT ESTABLISHED PROMPT"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-ILS-6", templateID: "AP-03", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "\(appUnit), \(callsign), established on localizer runway \(arrRwySpoken).",
                criticalSlots: [
                    CriticalSlot(slot: "ESTABLISHED", expectedValue: "established on localizer", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "ESTABLISHED REPORT"
            ))
            globalTurn += 1

            // Step 4: Speed Restriction Cancellation & Handoff to Tower (ICAO Doc 9432 Section 7.5.1)
            exchanges.append(FilledExchange(
                exchangeID: "AP-ILS-7", templateID: "AP-04", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), no ATC speed restrictions, contact \(twrUnit) \(twrFreq).",
                criticalSlots: [], severity: .normal, eventTag: "SPEED CANCEL & CONTACT TOWER"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-ILS-8", templateID: "AP-04", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "No ATC speed restrictions, \(twrUnit) \(twrFreq), \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "TOWER_FREQ", expectedValue: twrFreq, type: "mandatoryFrequency"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK TOWER FREQ"
            ))
            globalTurn += 1

            // Step 5: Final Check & Landing Clearance (with Contingency advisories if applicable)
            var landingAdvisory = ""
            if let waterCont = contingencies.first(where: { $0.title.contains("Contaminated") || $0.title.contains("Braking") }) {
                landingAdvisory = "caution standing water on runway, braking action reported poor by preceding traffic, "
                executedContingencies.append(waterCont)
            } else if let lateClear = contingencies.first(where: { $0.title.contains("Late Landing Clearance") }) {
                // Late landing clearance prompt
                exchanges.append(FilledExchange(
                    exchangeID: "ABN-LATE-1", templateID: "ABN-LATE", turn: globalTurn, speaker: "ATC",
                    isUserTurn: (role == .atc),
                    text: "\(callsign), \(twrUnit), two miles final, continue approach, preceding traffic vacating runway.",
                    criticalSlots: [], severity: .normal, eventTag: "CONTINUE APPROACH LATE CLEARANCE"
                ))
                globalTurn += 1

                exchanges.append(FilledExchange(
                    exchangeID: "ABN-LATE-2", templateID: "ABN-LATE", turn: globalTurn, speaker: "PILOT",
                    isUserTurn: (role == .pilot),
                    text: "\(twrUnit), \(callsign), short final runway \(arrRwySpoken), confirm cleared to land?",
                    criticalSlots: [
                        CriticalSlot(slot: "CONFIRM", expectedValue: "confirm cleared to land", type: "mandatoryKeyword"),
                        CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                    ], severity: .abnormal, eventTag: "PROMPT CLEARANCE"
                ))
                globalTurn += 1
                executedContingencies.append(lateClear)
            }

            exchanges.append(FilledExchange(
                exchangeID: "AP-TWR-1", templateID: "AP-05", turn: globalTurn, speaker: "ATC",
                isUserTurn: (role == .atc),
                text: "\(callsign), \(twrUnit), four miles final, \(landingAdvisory)runway \(arrRwySpoken), wind \(windSpoken), cleared to land.",
                criticalSlots: [], severity: landingAdvisory.isEmpty ? .normal : .abnormal, eventTag: landingAdvisory.isEmpty ? "CLEARED TO LAND" : "CLEARED TO LAND & BRAKING POOR"
            ))
            globalTurn += 1

            exchanges.append(FilledExchange(
                exchangeID: "AP-TWR-2", templateID: "AP-05", turn: globalTurn, speaker: "PILOT",
                isUserTurn: (role == .pilot),
                text: "Runway \(arrRwySpoken), cleared to land, \(callsign).",
                criticalSlots: [
                    CriticalSlot(slot: "RUNWAY", expectedValue: arrRwySpoken, type: "mandatoryRunway"),
                    CriticalSlot(slot: "CLEARED_TO_LAND", expectedValue: "cleared to land", type: "mandatoryKeyword"),
                    CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
                ], severity: .normal, eventTag: "READBACK CLEARED TO LAND"
            ))
            globalTurn += 1
        }

        return exchanges
    }
    // MARK: - Phase 6: Landing Builder
    private func buildLandingExchanges(
        level: CurriculumLevel,
        seed: Int,
        role: UserRole,
        context: SlotContext,
        globalTurn: inout Int
    ) -> [FilledExchange] {
        var exchanges: [FilledExchange] = []
        let callsign = context.callsign
        let twrUnit = context.unitTower?.callsign ?? "Tower"
        let gndUnit = context.unitGround?.callsign ?? "Ground"
        let gndFreq = SpokenFormFormatter.frequency(context.unitGround?.frequency ?? "121.700")
        let exitTaxiway = context.exitTaxiway
        let exitDir = context.exitDirection
        let standDest = context.destinationStand

        // Turn 1: ATC Vacate instruction
        exchanges.append(FilledExchange(
            exchangeID: "LD-VAC-1", templateID: "LD-01", turn: globalTurn, speaker: "ATC",
            isUserTurn: (role == .atc),
            text: "\(callsign), \(twrUnit), vacate \(exitDir) via \(exitTaxiway), when vacated contact Ground \(gndFreq).",
            criticalSlots: [], severity: .normal, eventTag: "VACATE RUNWAY INSTRUCTION"
        ))
        globalTurn += 1

        // Turn 2: PILOT Readback vacate
        exchanges.append(FilledExchange(
            exchangeID: "LD-VAC-2", templateID: "LD-01", turn: globalTurn, speaker: "PILOT",
            isUserTurn: (role == .pilot),
            text: "Vacate \(exitDir) via \(exitTaxiway), contact Ground \(gndFreq), \(callsign).",
            criticalSlots: [
                CriticalSlot(slot: "VACATE_TAXIWAY", expectedValue: exitTaxiway, type: "mandatoryTaxiway"),
                CriticalSlot(slot: "GROUND_FREQ", expectedValue: gndFreq, type: "mandatoryFrequency"),
                CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
            ], severity: .normal, eventTag: "READBACK VACATE"
        ))
        globalTurn += 1

        // Turn 3: ATC Ground taxi clearance
        exchanges.append(FilledExchange(
            exchangeID: "LD-GND-1", templateID: "LD-02", turn: globalTurn, speaker: "ATC",
            isUserTurn: (role == .atc),
            text: "\(callsign), \(gndUnit), taxi to \(standDest) via \(context.taxiRoute).",
            criticalSlots: [], severity: .normal, eventTag: "TAXI TO GATE"
        ))
        globalTurn += 1

        // Turn 4: PILOT Readback taxi
        exchanges.append(FilledExchange(
            exchangeID: "LD-GND-2", templateID: "LD-02", turn: globalTurn, speaker: "PILOT",
            isUserTurn: (role == .pilot),
            text: "Taxi to \(standDest) via \(context.taxiRoute), \(callsign).",
            criticalSlots: [
                CriticalSlot(slot: "STAND", expectedValue: standDest, type: "mandatoryGate"),
                CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
            ], severity: .normal, eventTag: "READBACK TAXI TO GATE"
        ))
        globalTurn += 1

        // Turn 5: ATC Shutdown report prompt
        exchanges.append(FilledExchange(
            exchangeID: "LD-SHUT-1", templateID: "LD-03", turn: globalTurn, speaker: "ATC",
            isUserTurn: (role == .atc),
            text: "\(callsign), report on \(standDest) with engines shut down.",
            criticalSlots: [], severity: .normal, eventTag: "REPORT ON STAND"
        ))
        globalTurn += 1

        // Turn 6: PILOT Shutdown & close flight plan
        exchanges.append(FilledExchange(
            exchangeID: "LD-SHUT-2", templateID: "LD-03", turn: globalTurn, speaker: "PILOT",
            isUserTurn: (role == .pilot),
            text: "\(gndUnit), \(callsign), on \(standDest), parking brake set, engines shut down, request close flight plan.",
            criticalSlots: [
                CriticalSlot(slot: "ENGINES_SHUTDOWN", expectedValue: "engines shut down", type: "mandatoryKeyword"),
                CriticalSlot(slot: "CLOSE_FP", expectedValue: "close flight plan", type: "mandatoryKeyword"),
                CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
            ], severity: .normal, eventTag: "CLOSE FLIGHT PLAN"
        ))
        globalTurn += 1

        // Turn 7: ATC Flight plan closed
        exchanges.append(FilledExchange(
            exchangeID: "LD-SHUT-3", templateID: "LD-03", turn: globalTurn, speaker: "ATC",
            isUserTurn: (role == .atc),
            text: "\(callsign), flight plan closed at zero two zero zero UTC, good day.",
            criticalSlots: [], severity: .normal, eventTag: "FLIGHT PLAN CLOSED"
        ))
        globalTurn += 1

        // Turn 8: PILOT Good day
        exchanges.append(FilledExchange(
            exchangeID: "LD-SHUT-4", templateID: "LD-03", turn: globalTurn, speaker: "PILOT",
            isUserTurn: (role == .pilot),
            text: "Flight plan closed, good day, \(callsign).",
            criticalSlots: [
                CriticalSlot(slot: "CALLSIGN", expectedValue: callsign, type: "mandatoryIdentifier")
            ], severity: .normal, eventTag: "READBACK GOOD DAY"
        ))
        globalTurn += 1

        return exchanges
    }
}

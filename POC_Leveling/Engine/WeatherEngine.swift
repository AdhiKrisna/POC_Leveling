import Foundation

public struct SelectedRunway: Equatable, Sendable {
    public let runway: String
    public let headwindKnots: Double
    public let crosswindKnots: Double

    public init(runway: String, headwindKnots: Double, crosswindKnots: Double) {
        self.runway = runway
        self.headwindKnots = headwindKnots
        self.crosswindKnots = crosswindKnots
    }
}

public struct AlignedWeather: Equatable, Sendable {
    public let runway: String
    public let heading: Double
    public let windDirection: Int
    public let windSpeed: Int
    public let headwindKnots: Double
    public let crosswindKnots: Double
    public let qnh: Int

    public init(
        runway: String,
        heading: Double,
        windDirection: Int,
        windSpeed: Int,
        headwindKnots: Double,
        crosswindKnots: Double,
        qnh: Int
    ) {
        self.runway = runway
        self.heading = heading
        self.windDirection = windDirection
        self.windSpeed = windSpeed
        self.headwindKnots = headwindKnots
        self.crosswindKnots = crosswindKnots
        self.qnh = qnh
    }
}

public enum WeatherEngine {
    public static func windComponents(
        runwayHeading: Double,
        windDirection: Double,
        windSpeed: Double
    ) -> (headwind: Double, crosswind: Double) {
        let diffRad = abs(windDirection - runwayHeading) * .pi / 180.0
        let headwind = windSpeed * cos(diffRad)
        let crosswind = windSpeed * abs(sin(diffRad))
        return (
            (headwind * 10).rounded() / 10,
            (crosswind * 10).rounded() / 10
        )
    }

    public static func bestRunway(
        pair: [String],
        headings: [String: Double],
        windDirection: Double,
        windSpeed: Double
    ) -> SelectedRunway {
        var bestRwy = pair.first ?? ""
        var bestHw = -999.0
        var bestXw = 0.0

        for rwy in pair {
            let hdg = headings[rwy] ?? 0.0
            let (hw, xw) = windComponents(
                runwayHeading: hdg,
                windDirection: windDirection,
                windSpeed: windSpeed
            )
            if hw > bestHw {
                bestHw = hw
                bestXw = xw
                bestRwy = rwy
            }
        }

        return SelectedRunway(runway: bestRwy, headwindKnots: bestHw, crosswindKnots: bestXw)
    }

    public static func alignedWeather(
        runway: String,
        heading: Double,
        seed: Int
    ) -> AlignedWeather {
        // Linear congruential generator for deterministic pseudo-randomness
        var state = UInt64(bitPattern: Int64(seed &* 6364136223846793005 &+ 1442695040888963407))
        func nextRandom(min: Double, max: Double) -> Double {
            state = state &* 6364136223846793005 &+ 1442695040888963407
            let unit = Double(state >> 16) / Double(1 << 48)
            return min + unit * (max - min)
        }

        // Pseudo-random selection between primary heading and reciprocal runway heading
        let isReciprocalFlow = (abs(seed) % 2 == 1)
        let baseHeading = isReciprocalFlow ? (heading + 180.0) : heading
        let delta = nextRandom(min: -35.0, max: 35.0)
        let rawDir = (baseHeading + delta).truncatingRemainder(dividingBy: 360.0)
        let windDir = Int((rawDir + 360.0).truncatingRemainder(dividingBy: 360.0).rounded())
        let windSpeed = Int(nextRandom(min: 7.0, max: 18.0).rounded())
        let qnh = Int(nextRandom(min: 1008.0, max: 1016.0).rounded())

        let (hw, xw) = windComponents(
            runwayHeading: heading,
            windDirection: Double(windDir),
            windSpeed: Double(windSpeed)
        )

        return AlignedWeather(
            runway: runway,
            heading: heading,
            windDirection: windDir,
            windSpeed: windSpeed,
            headwindKnots: hw,
            crosswindKnots: xw,
            qnh: qnh
        )
    }
}

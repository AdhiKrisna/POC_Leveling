import Foundation

public enum RepositoryError: Error, LocalizedError {
    case resourceNotFound(String)

    public var errorDescription: String? {
        switch self {
        case let .resourceNotFound(name): "Resource not found: \(name)"
        }
    }
}

public final class AirportRepository {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    public func airport(icao: String) throws -> Airport {
        let resolvedName = (icao == "WAWP") ? "WADY" : icao
        let url: URL
        if let primaryURL = try? resourceURL(named: resolvedName, extension: "json") {
            url = primaryURL
        } else {
            url = try resourceURL(named: icao, extension: "json")
        }
        return try decoder.decode(Airport.self, from: Data(contentsOf: url))
    }

    private func resourceURL(named name: String, extension fileExtension: String) throws -> URL {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: fileExtension) {
            return url
        }
        #endif
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            return url
        }
        if let url = Bundle(for: AirportRepository.self).url(forResource: name, withExtension: fileExtension) {
            return url
        }
        let fallbackPath = "POC/Script_Generator/06_POC_Swift/POC_Leveling/POC_Leveling/Resources/Airports/\(name).\(fileExtension)"
        if FileManager.default.fileExists(atPath: fallbackPath) {
            return URL(fileURLWithPath: fallbackPath)
        }
        throw RepositoryError.resourceNotFound("\(name).\(fileExtension)")
    }
}

public final class TemplateRepository {
    private let decoder: JSONDecoder

    public init(decoder: JSONDecoder = JSONDecoder()) {
        self.decoder = decoder
    }

    public func templates(for phase: Phase) throws -> [ScenarioTemplate] {
        let url = try resourceURL(named: phase.resourceName, extension: "json")
        return try decoder.decode([ScenarioTemplate].self, from: Data(contentsOf: url))
    }

    public func abnormalEvents() throws -> [AbnormalEvent] {
        let url = try resourceURL(named: "abnormal_event_catalog", extension: "json")
        return try decoder.decode([AbnormalEvent].self, from: Data(contentsOf: url))
    }

    public func emergencyRules() throws -> [EmergencyRule] {
        let url = try resourceURL(named: "emergency_response_rules", extension: "json")
        return try decoder.decode([EmergencyRule].self, from: Data(contentsOf: url))
    }

    private func resourceURL(named name: String, extension fileExtension: String) throws -> URL {
        #if SWIFT_PACKAGE
        if let url = Bundle.module.url(forResource: name, withExtension: fileExtension) {
            return url
        }
        #endif
        if let url = Bundle.main.url(forResource: name, withExtension: fileExtension) {
            return url
        }
        if let url = Bundle(for: TemplateRepository.self).url(forResource: name, withExtension: fileExtension) {
            return url
        }
        throw RepositoryError.resourceNotFound("\(name).\(fileExtension)")
    }
}

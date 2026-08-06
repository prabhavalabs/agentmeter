import Foundation

public enum AgentMeterRoute: Equatable, Sendable {
    case overview
    case agents
    case provider(String)

    public init(url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme == "agentmeter",
              components.user == nil,
              components.password == nil,
              components.port == nil,
              components.query == nil,
              components.fragment == nil,
              let host = components.percentEncodedHost,
              host == "overview" || host == "agents" || host == "agent" else {
            self = .overview
            return
        }

        switch host {
        case "overview" where components.percentEncodedPath.isEmpty:
            self = .overview
        case "agents" where components.percentEncodedPath.isEmpty:
            self = .agents
        case "agent":
            let encodedPath = components.percentEncodedPath
            guard encodedPath.hasPrefix("/") else {
                self = .overview
                return
            }

            let encodedProviderID = String(encodedPath.dropFirst())
            guard encodedProviderID.isEmpty == false,
                  encodedProviderID.contains("/") == false,
                  let providerID = encodedProviderID.removingPercentEncoding,
                  Self.isValidProviderID(providerID) else {
                self = .overview
                return
            }
            self = .provider(providerID)
        default:
            self = .overview
        }
    }

    public var url: URL {
        switch self {
        case .overview:
            return Self.makeURL(host: "overview")
        case .agents:
            return Self.makeURL(host: "agents")
        case let .provider(providerID):
            guard Self.isValidProviderID(providerID) else {
                return Self.makeURL(host: "overview")
            }

            var components = URLComponents()
            components.scheme = "agentmeter"
            components.host = "agent"
            components.path = "/"
            components.path += providerID
            return components.url!
        }
    }

    private static func makeURL(host: String) -> URL {
        var components = URLComponents()
        components.scheme = "agentmeter"
        components.host = host
        return components.url!
    }

    private static func isValidProviderID(_ providerID: String) -> Bool {
        guard (1...23).contains(providerID.utf8.count) else { return false }
        return providerID.utf8.allSatisfy { byte in
            (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte)
                || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
                || byte == UInt8(ascii: "_")
                || byte == UInt8(ascii: "-")
        }
    }
}

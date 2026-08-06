import Foundation
import Testing
@testable import AgentMeterWidgetCore

@Test func routesRecognizedOverviewAndAgentsHosts() {
    #expect(AgentMeterRoute(url: URL(string: "agentmeter://overview")!) == .overview)
    #expect(AgentMeterRoute(url: URL(string: "agentmeter://agents")!) == .agents)
}

@Test func routeDecodesValidPercentEncodedProviderID() {
    let route = AgentMeterRoute(url: URL(string: "agentmeter://agent/codex%2Dteam_1")!)

    #expect(route == .provider("codex-team_1"))
}

@Test func percentEncodedApprovedHostsFallBackToOverview() {
    let encodedHostRoutes = [
        "agentmeter://%6Fverview",
        "agentmeter://%61gents",
        "agentmeter://%61gent/codex",
    ]

    for rawRoute in encodedHostRoutes {
        #expect(AgentMeterRoute(url: URL(string: rawRoute)!) == .overview)
    }
}

@Test func routeEmitsCanonicalURLsUsingValidatedProviderID() {
    #expect(AgentMeterRoute.overview.url.absoluteString == "agentmeter://overview")
    #expect(AgentMeterRoute.agents.url.absoluteString == "agentmeter://agents")
    #expect(AgentMeterRoute.provider("codex-team_1").url.absoluteString == "agentmeter://agent/codex-team_1")
}

@Test func unsafeOrAmbiguousRoutesFallBackToOverview() {
    let overlongID = String(repeating: "a", count: 24)
    let unsafeRoutes = [
        "agentmeter://unknown",
        "agentmeter://overview/extra",
        "agentmeter://agents/extra",
        "agentmeter://agent/",
        "agentmeter://agent/codex/extra",
        "agentmeter://agent/Codex",
        "agentmeter://agent/codex.team",
        "agentmeter://agent/codex%2Fteam",
        "agentmeter://agent/codex%20team",
        "agentmeter://agent/codex%0Ateam",
        "agentmeter://agent/bad%ZZ",
        "agentmeter://agent/\(overlongID)",
        "agentmeter://agent/codex?source=widget",
        "agentmeter://agent/codex#details",
    ]

    for rawRoute in unsafeRoutes {
        #expect(AgentMeterRoute(url: URL(string: rawRoute)!) == .overview)
    }
}

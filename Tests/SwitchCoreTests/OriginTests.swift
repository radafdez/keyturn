import Foundation
import Testing
@testable import SwitchCore

@Suite struct OriginTests {
    @Test func everyEventSaysWhoAskedForIt() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)

        try world.service.activate(globex.id, origin: .menu)
        try world.service.activate(acme.id, origin: .terminal)
        try world.service.activate(globex.id, origin: .agent("claude-code"))
        _ = try world.service.tokenForRun(acme.id)

        let history = world.store.state.history
        #expect(history.map(\.source) == [.menu, .terminal, .agent, .terminal])
        #expect(history.map(\.client) == [nil, nil, "claude-code", nil])
    }

    @Test func theSummaryCountsSwitchesBySourceAndByAgent() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)

        try world.service.activate(acme.id, origin: .menu)
        try world.service.activate(globex.id, origin: .agent("cursor"))
        try world.service.activate(acme.id, origin: .agent("claude-code"))
        try world.service.activate(globex.id, origin: .agent("claude-code"))

        let usage = try world.service.snapshot().usage
        #expect(usage.switchesBySource[.menu] == 1)
        #expect(usage.switchesBySource[.agent] == 3)
        #expect(usage.agentClients == [
            ClientCount(client: "claude-code", switches: 2),
            ClientCount(client: "cursor", switches: 1),
        ])
        #expect(usage.recent.first?.client == "claude-code")
        #expect(usage.recent.first?.accountID == globex.id)
        #expect(usage.recent.count == 4)
    }

    @Test func turningAgentsOffStopsThemButNotThePerson() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        try world.service.setAgentsCanSwitch(false)
        #expect(try world.service.snapshot().agentsCanSwitch == false)

        #expect(throws: SwitchError.agentsNotAllowed) {
            try world.service.activate(globex.id, origin: .agent("claude-code"))
        }
        #expect(world.cli.logins.isEmpty)
        #expect(world.store.state.history.isEmpty)

        try world.service.activate(acme.id, origin: .menu)
        #expect(try world.service.snapshot().activeAccount?.id == acme.id)
    }
}

@Suite struct UseProjectTests {
    @Test func itSwitchesToTheAccountThatOwnsTheProject() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        try world.service.activate(acme.id)

        let use = try world.service.useProject("globexstaging", origin: .agent("claude-code"))

        #expect(use.switched)
        #expect(use.account.id == globex.id)
        #expect(use.project.ref == "globexstaging")
        #expect(try world.service.snapshot().activeAccount?.id == globex.id)
        #expect(world.store.state.history.last?.client == "claude-code")
    }

    @Test func itDoesNothingWhenTheCLIIsAlreadyThere() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        try world.service.activate(acme.id)
        try world.service.renameProject("acmeprod", in: acme.id, to: "Acme prod")
        let logins = world.cli.logins.count
        let events = world.store.state.history.count

        let use = try world.service.useProject("acme prod", origin: .agent("claude-code"))

        #expect(!use.switched)
        #expect(world.cli.logins.count == logins)
        #expect(world.store.state.history.count == events)
    }

    @Test func anUnknownProjectIsReported() throws {
        let world = World()
        _ = try world.service.addAccount(token: tokenA)
        #expect(throws: SwitchError.unknownProject("nope")) {
            try world.service.useProject("nope", origin: .agent(nil))
        }
    }
}

@Suite struct StateFile12CompatibilityTests {
    @Test func aFileFrom11OpensWithAgentsAllowed() throws {
        let json = """
        {"accounts":[],"history":[{"accountID":"6F9619FF-8B86-D011-B42D-00C04FC964FF","kind":"switched","date":"2027-01-15T08:00:00Z"}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let state = try decoder.decode(SwitchState.self, from: Data(json.utf8))
        #expect(state.agentsCanSwitch)
        #expect(state.history.first?.source == nil)
    }
}

@Suite struct DemoTests {
    @Test func theDemoHasThreeMadeUpAccountsAndAgentHistory() throws {
        let snapshot = try Demo.service().snapshot()
        #expect(snapshot.accounts.map(\.name) == ["Acme", "Globex", "Initech"])
        #expect(snapshot.activeAccount?.name == "Globex")
        #expect(snapshot.usage.agentClients.first?.client == "claude-code")
        #expect(snapshot.usage.recent.first?.source == .agent)
    }
}

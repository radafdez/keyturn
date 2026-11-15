import Foundation
import Testing
@testable import SwitchCore

@Suite struct ProjectAliasTests {
    @Test func aProjectCanBeRenamedLocally() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)

        try world.service.renameProject("acmeprod", in: acme.id, to: "  Acme prod  ")

        let project = try #require(world.store.state.accounts[0].projects.first)
        #expect(project.alias == "Acme prod")
        #expect(project.displayName == "Acme prod")
        #expect(project.name == "Acme acmeprod")
    }

    @Test func anEmptyAliasOrTheOriginalNameGoesBackToSupabasesName() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        try world.service.renameProject("acmeprod", in: acme.id, to: "Prod")

        try world.service.renameProject("acmeprod", in: acme.id, to: "   ")
        #expect(world.store.state.accounts[0].projects[0].alias == nil)

        try world.service.renameProject("acmeprod", in: acme.id, to: "Acme acmeprod")
        #expect(world.store.state.accounts[0].projects[0].alias == nil)
    }

    @Test func aliasesSurviveReadingTheProjectsAgain() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        try world.service.renameProject("acmestaging", in: acme.id, to: "Staging")
        world.cli.addRemote(token: tokenA, org: "org-acme", name: "Acme", projects: ["acmenew", "acmestaging"])

        let refreshed = try world.service.refreshProjects(acme.id)
        #expect(refreshed.projects.map(\.displayName) == ["Acme acmenew", "Staging"])

        // Adding the same account again also keeps them.
        // Volver a añadir la misma cuenta también los conserva.
        let again = try world.service.addAccount(token: tokenA)
        #expect(again.projects.map(\.alias) == [nil, "Staging"])
    }

    @Test func anUnknownProjectIsReported() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        #expect(throws: SwitchError.unknownProject("nope")) {
            try world.service.renameProject("nope", in: acme.id, to: "x")
        }
    }

    @Test func accountsAndProjectsAreFoundByAlias() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        try world.service.renameProject("globexprod", in: globex.id, to: "gx-prod")
        let accounts = world.store.state.accounts

        #expect(try SwitchService.resolve("gx-prod", in: accounts).id == globex.id)
        let found = try SwitchService.resolveProject("GX-PROD", in: accounts)
        #expect(found.account.id == globex.id)
        #expect(found.project.ref == "globexprod")
        #expect(try SwitchService.resolveProject("acmestaging", in: accounts).account.id == acme.id)
        #expect(throws: SwitchError.unknownProject("zzz")) { try SwitchService.resolveProject("zzz", in: accounts) }
    }
}

@Suite struct UsageTests {
    @Test func switchesAndRunsAreCounted() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)

        try world.service.activate(globex.id)
        world.clock.advance(days: 1)
        try world.service.activate(acme.id)
        world.clock.advance(days: 1)
        try world.service.activate(globex.id)
        _ = try world.service.tokenForRun(acme.id)

        let usage = try world.service.snapshot().usage
        #expect(usage.totalSwitches == 3)
        #expect(usage.totalRuns == 1)
        #expect(usage.accounts.map(\.account.id) == [globex.id, acme.id])
        #expect(usage.usage(of: globex.id)?.switches == 2)
        #expect(usage.usage(of: acme.id)?.switches == 1)
        #expect(usage.usage(of: acme.id)?.runs == 1)
        #expect(usage.usage(of: acme.id)?.lastUsed == world.clock.date)
        #expect(usage.since == Date(timeIntervalSince1970: 1_800_000_000))
    }

    @Test func thisWeekLeavesOlderSwitchesOut() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        try world.service.activate(acme.id)
        world.clock.advance(days: 10)
        try world.service.activate(acme.id)

        let usage = try #require(try world.service.snapshot().usage.usage(of: acme.id))
        #expect(usage.switches == 2)
        #expect(usage.switchesThisWeek == 1)
    }

    @Test func aFailedSwitchIsNotCounted() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        world.cli.loginIsSilentlyIgnored = true
        #expect(throws: SwitchError.self) { try world.service.activate(acme.id) }
        #expect(world.store.state.history.isEmpty)
    }

    @Test func removingAnAccountForgetsItsHistory() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        try world.service.activate(acme.id)
        try world.service.activate(globex.id)

        try world.service.remove(acme.id)

        #expect(world.store.state.history.map(\.accountID) == [globex.id])
        #expect(try world.service.snapshot().usage.totalSwitches == 1)
    }

    @Test func theHistoryIsCapped() {
        var state = SwitchState()
        let id = UUID()
        for second in 0..<(UsageEvent.limit + 5) {
            state.record(.switched, for: id, at: Date(timeIntervalSince1970: Double(second)), origin: .menu)
        }
        #expect(state.history.count == UsageEvent.limit)
        #expect(state.history.first?.date == Date(timeIntervalSince1970: 5))
    }

    @Test func newAccountsRememberWhenTheyWereAdded() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        #expect(acme.createdAt == world.clock.date)
    }
}

@Suite struct CompatibilityTests {
    /// What version 1.0 wrote: no history, no aliases, no dates.
    /// Lo que escribía la versión 1.0: sin historial, sin alias, sin fechas.
    @Test func aFileFromVersion1_0StillOpens() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("accounts.json")
        let id = UUID()
        try """
        {
          "accounts" : [ { "id" : "\(id.uuidString)", "name" : "Acme", "organizationIDs" : [ "org-acme" ],
                           "projects" : [ { "name" : "acme-prod", "ref" : "acmeprod", "region" : "us-east-1" } ] } ],
          "activeAccountID" : "\(id.uuidString)",
          "sessionStamp" : "stamp-1"
        }
        """.write(to: url, atomically: true, encoding: .utf8)

        let state = try FileStateStore(url: url).load()

        #expect(state.accounts.first?.name == "Acme")
        #expect(state.accounts.first?.createdAt == nil)
        #expect(state.accounts.first?.projects.first?.alias == nil)
        #expect(state.history.isEmpty)
        #expect(state.activeAccountID == id)
    }

    @Test func datesAreWrittenAsReadableText() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = FileStateStore(url: directory.appendingPathComponent("accounts.json"))
        var state = SwitchState()
        state.record(.switched, for: UUID(), at: Date(timeIntervalSince1970: 1_800_000_000), origin: .menu)

        try store.save(state)

        #expect(try String(contentsOf: store.url, encoding: .utf8).contains("2027-01-15T08:00:00Z"))
        #expect(try store.load() == state)
    }
}

@Suite struct LanguageTests {
    @Test func spanishSystemsGetSpanish() {
        #expect(AppLanguage.detect(environment: [:], preferred: ["es-ES", "en-US"]) == .spanish)
        #expect(AppLanguage.detect(environment: [:], preferred: ["es-419"]) == .spanish)
    }

    @Test func everythingElseGetsEnglish() {
        #expect(AppLanguage.detect(environment: [:], preferred: ["en-US", "es-ES"]) == .english)
        #expect(AppLanguage.detect(environment: [:], preferred: ["fr-FR"]) == .english)
        #expect(AppLanguage.detect(environment: [:], preferred: []) == .english)
    }

    @Test func theEnvironmentWins() {
        #expect(AppLanguage.detect(environment: ["SUPABASE_SWITCH_LANG": "ES"], preferred: ["en-US"]) == .spanish)
        #expect(AppLanguage.detect(environment: ["SUPABASE_SWITCH_LANG": "en"], preferred: ["es-ES"]) == .english)
        #expect(AppLanguage.detect(environment: ["SUPABASE_SWITCH_LANG": "de"], preferred: ["es-ES"]) == .spanish)
    }
}

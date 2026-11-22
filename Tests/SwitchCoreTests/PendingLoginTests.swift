import Foundation
import Testing
@testable import SwitchCore

/// A login of an account not registered yet must never be thrown away, and
/// when one is lost anyway the user must hear about it.
/// Una sesión de una cuenta aún sin registrar nunca se tira, y si aun así se
/// pierde, el usuario tiene que enterarse.
@Suite struct PendingLoginTests {
    /// Acme and Globex registered, the CLI logged in as Initech in a terminal.
    private func worldWithANewLogin() throws -> (World, Account, Account) {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        try world.service.activate(acme.id)
        world.cli.externalLogin(tokenC)
        return (world, acme, globex)
    }

    @Test func anAgentCannotSwitchOverALoginNotCapturedYet() throws {
        let (world, _, globex) = try worldWithANewLogin()
        let loginsBefore = world.cli.logins

        #expect(throws: SwitchError.unregisteredLogin("Initech")) {
            try world.service.activate(globex.id, origin: .agent("claude-code"))
        }
        #expect(world.cli.logins == loginsBefore)
        #expect(world.keychain.values[.supabaseCLI] == tokenC)
    }

    @Test func useProjectIsBlockedToo() throws {
        let (world, _, _) = try worldWithANewLogin()
        #expect(throws: SwitchError.unregisteredLogin("Initech")) {
            try world.service.useProject("globexprod", origin: .agent("claude-code"))
        }
        #expect(world.keychain.values[.supabaseCLI] == tokenC)
    }

    @Test func theTerminalIsBlockedToo() throws {
        let (world, _, globex) = try worldWithANewLogin()
        #expect(throws: SwitchError.unregisteredLogin("Initech")) {
            try world.service.activate(globex.id, origin: .terminal)
        }
    }

    @Test func theBlockHoldsEvenIfNobodyLookedBefore() throws {
        // No snapshot between the login and the switch: activate looks itself.
        let (world, _, globex) = try worldWithANewLogin()
        #expect(world.store.state.pendingLogin == nil)
        #expect(throws: SwitchError.unregisteredLogin("Initech")) {
            try world.service.activate(globex.id, origin: .agent(nil))
        }
    }

    @Test func theMenuCapturesTheNewLoginBeforeSwitching() throws {
        let (world, _, globex) = try worldWithANewLogin()

        let after = try world.service.activate(globex.id, origin: .menu)

        #expect(after.session == .account(globex.id))
        let initech = try #require(world.store.state.accounts.first { $0.organizationIDs == ["org-initech"] })
        #expect(world.keychain.values[.stored(initech.id)] == tokenC)
        #expect(world.store.state.pendingLogin == nil)
        #expect(world.store.state.lostLogin == nil)
    }

    @Test func whenTheCaptureFailsTheMenuChangesNothing() throws {
        let (world, _, globex) = try worldWithANewLogin()
        world.keychain.denied = [.supabaseCLI]
        let loginsBefore = world.cli.logins

        #expect(throws: SwitchError.self) { try world.service.activate(globex.id, origin: .menu) }

        #expect(world.cli.logins == loginsBefore)
        #expect(world.keychain.values[.supabaseCLI] == tokenC)
        #expect(world.store.state.accounts.count == 2)
    }

    @Test func onceCapturedAgentsMaySwitchAgain() throws {
        let (world, _, globex) = try worldWithANewLogin()
        try world.service.captureCurrent()

        try world.service.activate(globex.id, origin: .agent("claude-code"))

        #expect(try world.service.snapshot().session == .account(globex.id))
        #expect(try world.service.snapshot().lostLogin == nil)
    }

    @Test func afterALogoutTheSwitchGoesAhead() throws {
        let (world, _, globex) = try worldWithANewLogin()
        #expect(try world.service.snapshot().session == .unregistered)
        world.cli.externalLogout()

        try world.service.activate(globex.id, origin: .agent("claude-code"))

        #expect(try world.service.snapshot().session == .account(globex.id))
        #expect(try world.service.snapshot().lostLogin == nil)
    }

    @Test func aLoginReplacedInATerminalBeforeItsCaptureIsReportedLost() throws {
        let (world, _, globex) = try worldWithANewLogin()
        #expect(try world.service.snapshot().session == .unregistered)

        world.cli.externalLogin(tokenB)

        let snapshot = try world.service.snapshot()
        #expect(snapshot.session == .account(globex.id))
        #expect(snapshot.lostLogin?.name == "Initech")
    }

    @Test func capturingTheLostAccountClearsTheWarning() throws {
        let (world, _, _) = try worldWithANewLogin()
        _ = try world.service.snapshot()
        world.cli.externalLogin(tokenB)
        #expect(try world.service.snapshot().lostLogin != nil)

        world.cli.externalLogin(tokenC)
        try world.service.captureCurrent()

        #expect(try world.service.snapshot().lostLogin == nil)
    }

    @Test func theWarningCanBeDismissed() throws {
        let (world, _, _) = try worldWithANewLogin()
        _ = try world.service.snapshot()
        world.cli.externalLogin(tokenB)
        #expect(try world.service.snapshot().lostLogin != nil)

        try world.service.forgetLostLogin()

        #expect(try world.service.snapshot().lostLogin == nil)
    }

    @Test func loggingInAgainToTheSameNewAccountLosesNothing() throws {
        let (world, _, _) = try worldWithANewLogin()
        _ = try world.service.snapshot()
        let rotated = "sbp_" + String(repeating: "f", count: 40)
        world.cli.addRemote(token: rotated, org: "org-initech", name: "Initech", projects: ["initechprod"])

        world.cli.externalLogin(rotated)

        #expect(try world.service.snapshot().session == .unregistered)
        #expect(try world.service.snapshot().lostLogin == nil)
    }

    @Test func removingTheActiveAccountDoesNotBlockSwitching() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        try world.service.activate(acme.id)
        try world.service.remove(acme.id)

        try world.service.activate(globex.id, origin: .agent("claude-code"))

        #expect(try world.service.snapshot().session == .account(globex.id))
        #expect(world.store.state.accounts.count == 1)
    }

    @Test func aFileWithoutTheNewFieldsStillOpens() throws {
        let json = #"{"accounts":[],"history":[],"agentsCanSwitch":true}"#
        let state = try JSONDecoder().decode(SwitchState.self, from: Data(json.utf8))
        #expect(state.pendingLogin == nil)
        #expect(state.lostLogin == nil)
    }
}

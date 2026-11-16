import Foundation
import Testing
@testable import SwitchCore

@Suite struct SwitchServiceTests {
    @Test func noSessionWhenTheCLIHasNoLogin() throws {
        let world = World()
        #expect(try world.service.snapshot().session == .none)
        #expect(world.cli.organizationCalls == 0)
    }

    @Test func captureRegistersTheLoggedInAccount() throws {
        let world = World()
        world.cli.externalLogin(tokenA)

        let account = try world.service.captureCurrent()

        #expect(account.name == "Acme")
        #expect(account.organizationIDs == ["org-acme"])
        #expect(account.projects.map(\.ref) == ["acmeprod", "acmestaging"])
        #expect(world.keychain.values[.stored(account.id)] == tokenA)
        #expect(try world.service.snapshot().session == .account(account.id))
    }

    @Test func captureUnwrapsATokenStoredAsBase64() throws {
        let world = World()
        world.cli.externalLogin(tokenA, wrapped: true)

        let account = try world.service.captureCurrent(name: "Personal")

        #expect(account.name == "Personal")
        #expect(world.keychain.values[.stored(account.id)] == tokenA)
    }

    @Test func captureWithoutASessionFails() {
        let world = World()
        #expect(throws: SwitchError.noCLISession) { try world.service.captureCurrent() }
    }

    @Test func activateLogsTheCLIInWithTheStoredToken() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        world.cli.externalLogin(tokenA)
        #expect(try world.service.snapshot().session == .account(acme.id))

        let after = try world.service.activate(globex.id)

        #expect(world.cli.logins == [tokenB])
        #expect(after.session == .account(globex.id))
        #expect(after.activeAccount?.name == "Globex")
        #expect(try world.service.snapshot().session == .account(globex.id))
    }

    @Test func activateNeverClaimsALoginThatDidNotTake() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        world.cli.externalLogin(tokenA)
        world.cli.loginIsSilentlyIgnored = true

        #expect(throws: SwitchError.self) { try world.service.activate(globex.id) }
        #expect(try world.service.snapshot().session == .account(acme.id))
    }

    @Test func activateFailsWhenTheTokenIsGoneFromTheKeychain() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        try world.keychain.delete(.stored(acme.id))

        #expect(throws: SwitchError.missingToken("Acme")) { try world.service.activate(acme.id) }
        #expect(world.cli.logins.isEmpty)
    }

    @Test func aRevokedStoredTokenNeverReplacesAWorkingLogin() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        world.cli.externalLogin(tokenA)
        world.cli.remotes[tokenB] = nil

        #expect(throws: SwitchError.rejectedToken) { try world.service.activate(globex.id) }
        #expect(world.cli.logins.isEmpty)
        #expect(try world.service.snapshot().session == .account(acme.id))
    }

    @Test func oneCommandCanBorrowATokenWithoutSwitching() throws {
        let world = World()
        try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        world.cli.externalLogin(tokenA)

        #expect(try world.service.tokenForRun(globex.id) == tokenB)
        #expect(world.cli.logins.isEmpty)
        #expect(world.keychain.values[.supabaseCLI] == tokenA)
    }

    @Test func askingAgainIgnoresWhatWasWrittenDown() throws {
        let world = World()
        world.cli.externalLogin(tokenA)
        let acme = try world.service.captureCurrent()
        let calls = world.cli.organizationCalls

        #expect(try world.service.snapshot(askingTheCLIAgain: true).session == .account(acme.id))
        #expect(world.cli.organizationCalls == calls + 1)
    }

    @Test func accountsAreFoundByNamePrefixOrProject() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA, name: "Acme Corp")
        let globex = try world.service.addAccount(token: tokenB, name: "Globex Inc")
        try world.service.addAccount(token: tokenC, name: "Globex Labs")
        let accounts = world.store.state.accounts

        #expect(try SwitchService.resolve("acme corp", in: accounts) == acme)
        #expect(try SwitchService.resolve("acm", in: accounts) == acme)
        #expect(try SwitchService.resolve("globexstaging", in: accounts) == globex)
        #expect(try SwitchService.resolve("Globex globexprod", in: accounts) == globex)
        #expect(throws: SwitchError.ambiguous("globex", ["Globex Inc", "Globex Labs"])) {
            try SwitchService.resolve("globex", in: accounts)
        }
        #expect(throws: SwitchError.noMatch("nadie")) { try SwitchService.resolve("nadie", in: accounts) }
    }

    @Test func aLoginMadeInTheTerminalIsNoticed() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        let globex = try world.service.addAccount(token: tokenB)
        try world.service.activate(acme.id)

        world.cli.externalLogin(tokenB)

        #expect(try world.service.snapshot().session == .account(globex.id))
    }

    @Test func anUnknownLoginIsReportedAndNotAskedAboutTwice() throws {
        let world = World()
        try world.service.addAccount(token: tokenA)
        world.cli.externalLogin(tokenC)

        #expect(try world.service.snapshot().session == .unregistered)
        let callsAfterFirstLook = world.cli.organizationCalls
        #expect(try world.service.snapshot().session == .unregistered)
        #expect(world.cli.organizationCalls == callsAfterFirstLook)
    }

    @Test func theCLIIsNotAskedAgainWhileItsEntryIsUnchanged() throws {
        let world = World()
        world.cli.externalLogin(tokenA)
        let account = try world.service.captureCurrent()
        let calls = world.cli.organizationCalls

        for _ in 0..<3 { #expect(try world.service.snapshot().session == .account(account.id)) }

        #expect(world.cli.organizationCalls == calls)
    }

    @Test func aLogoutInTheTerminalClearsTheActiveAccount() throws {
        let world = World()
        world.cli.externalLogin(tokenA)
        try world.service.captureCurrent()

        world.cli.externalLogout()

        #expect(try world.service.snapshot().session == .none)
        #expect(world.store.state.activeAccountID == nil)
    }

    @Test func aCLIThatCannotAnswerIsNotWrittenDown() throws {
        let world = World()
        let acme = try world.service.addAccount(token: tokenA)
        world.cli.externalLogin(tokenA)
        world.cli.organizationsError = .cliFailed("sin red")

        guard case .unverified = try world.service.snapshot().session else {
            Issue.record("expected an unverified session")
            return
        }

        world.cli.organizationsError = nil
        #expect(try world.service.snapshot().session == .account(acme.id))
    }

    @Test func addingAnAccountLeavesTheCLISessionAlone() throws {
        let world = World()
        world.cli.externalLogin(tokenA)
        let stampBefore = world.keychain.modificationStamp(.supabaseCLI)

        let globex = try world.service.addAccount(token: "  \(tokenB)\n")

        #expect(world.cli.logins.isEmpty)
        #expect(world.keychain.modificationStamp(.supabaseCLI) == stampBefore)
        #expect(world.keychain.values[.stored(globex.id)] == tokenB)
        #expect(!world.keychain.reads.contains(.supabaseCLI))
    }

    @Test func addingTheAccountAlreadyLoggedInMarksItActive() throws {
        let world = World()
        world.cli.externalLogin(tokenA)
        #expect(try world.service.snapshot().session == .unregistered)

        let acme = try world.service.addAccount(token: tokenA)

        #expect(try world.service.snapshot().session == .account(acme.id))
    }

    @Test func aMalformedTokenIsRejectedBeforeAskingSupabase() {
        let world = World()
        #expect(throws: SwitchError.invalidToken) { try world.service.addAccount(token: "not-a-token") }
        #expect(world.cli.organizationCalls == 0)
    }

    @Test func aRevokedTokenIsRejected() {
        let world = World()
        let revoked = "sbp_" + String(repeating: "d", count: 40)
        #expect(throws: SwitchError.rejectedToken) { try world.service.addAccount(token: revoked) }
        #expect(world.store.state.accounts.isEmpty)
        #expect(world.keychain.values.isEmpty)
    }

    @Test func theSameAccountTwiceReplacesItsToken() throws {
        let world = World()
        let first = try world.service.addAccount(token: tokenA, name: "Acme Corp")
        let rotated = "sbp_" + String(repeating: "e", count: 40)
        world.cli.addRemote(token: rotated, org: "org-acme", name: "Acme", projects: ["acmeprod"])

        let second = try world.service.addAccount(token: rotated)

        #expect(second.id == first.id)
        #expect(second.name == "Acme Corp")
        #expect(world.store.state.accounts.count == 1)
        #expect(world.keychain.values[.stored(first.id)] == rotated)
    }

    @Test func namesStayUnique() throws {
        let world = World()
        try world.service.addAccount(token: tokenA, name: "Cliente")
        let second = try world.service.addAccount(token: tokenB, name: "cliente")
        #expect(second.name == "cliente 2")

        try world.service.rename(second.id, to: "Globex")
        #expect(world.store.state.accounts.map(\.name) == ["Cliente", "Globex"])
    }

    @Test func removeDeletesTheTokenButNotTheCLISession() throws {
        let world = World()
        world.cli.externalLogin(tokenA)
        let acme = try world.service.captureCurrent()

        try world.service.remove(acme.id)

        #expect(world.keychain.values[.stored(acme.id)] == nil)
        #expect(world.keychain.values[.supabaseCLI] == tokenA)
        #expect(try world.service.snapshot().session == .unregistered)
    }

    @Test func refreshProjectsUsesTheStoredToken() throws {
        let world = World()
        let globex = try world.service.addAccount(token: tokenB)
        world.cli.addRemote(token: tokenB, org: "org-globex", name: "Globex", projects: ["globexprod", "globexstaging", "globexnew"])

        let refreshed = try world.service.refreshProjects(globex.id)

        #expect(refreshed.projects.map(\.ref) == ["globexprod", "globexstaging", "globexnew"])
        #expect(world.cli.logins.isEmpty)
    }
}

@Suite struct StorageTests {
    @Test func theStateFileNeverHoldsAToken() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = FileStateStore(url: directory.appendingPathComponent("nested/accounts.json"))
        #expect(try file.load() == SwitchState())

        let keychain = FakeKeychain()
        let cli = FakeCLI(keychain: keychain)
        cli.addRemote(token: tokenA, org: "org-acme", name: "Acme", projects: ["acmeprod"])
        cli.externalLogin(tokenA)
        let service = SwitchService(store: file, secrets: keychain, cli: cli)
        let account = try service.captureCurrent()

        let text = try String(contentsOf: file.url, encoding: .utf8)
        #expect(!text.contains("sbp_"))
        #expect(try file.load().accounts == [account])
        let mode = try FileManager.default.attributesOfItem(atPath: file.url.path)[.posixPermissions] as? Int
        #expect(mode == 0o600)
    }

    @Test func keyringCodecRoundTrips() {
        #expect(KeyringCodec.decode(KeyringCodec.encode(tokenA)) == tokenA)
        #expect(KeyringCodec.decode("\(tokenA)\n") == tokenA)
        #expect(KeyringCodec.decode("go-keyring-base64:not base64") == "go-keyring-base64:not base64")
    }

    @Test func tokenShape() {
        #expect(AccessToken.isValid(tokenA))
        #expect(AccessToken.isValid("sbp_oauth_" + String(repeating: "0", count: 40)))
        #expect(!AccessToken.isValid("sbp_" + String(repeating: "a", count: 39)))
        #expect(!AccessToken.isValid("sbp_" + String(repeating: "Z", count: 40)))
        #expect(!AccessToken.isValid(tokenA + "\" -s x"))
    }

    @Test func modificationDateIsReadFromTheAttributeDump() {
        let dump = """
        keychain: "/Users/x/Library/Keychains/login.keychain-db"
        attributes:
            "acct"<blob>="supabase"
            "mdat"<timedate>=0x32303236313131353038313434335A00  "20261115081443Z\\000"
            "svce"<blob>="Supabase CLI"
        """
        #expect(SecurityToolKeychain.modificationDate(in: dump) == "0x32303236313131353038313434335A00  \"20261115081443Z\\000\"")
        #expect(SecurityToolKeychain.modificationDate(in: "attributes:\n    \"mdat\"<timedate>=<NULL>") == nil)
        #expect(SecurityToolKeychain.modificationDate(in: "") == nil)
    }

    /// Touches the real login Keychain, in this app's own service only.
    /// Run with KEYTURN_LIVE_KEYCHAIN=1.
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KEYTURN_LIVE_KEYCHAIN"] == "1"))
    func theRealKeychainStoresReplacesAndDeletes() throws {
        let keychain = SecurityToolKeychain()
        let slot = KeychainSlot.stored(UUID())
        defer { try? keychain.delete(slot) }

        #expect(try keychain.read(slot) == nil)
        #expect(keychain.modificationStamp(slot) == nil)

        try keychain.write(tokenA, to: slot)
        #expect(try keychain.read(slot) == tokenA)
        #expect(keychain.modificationStamp(slot)?.contains("Z") == true)

        try keychain.write(tokenB, to: slot)
        #expect(try keychain.read(slot) == tokenB)

        try keychain.delete(slot)
        #expect(try keychain.read(slot) == nil)
        try keychain.delete(slot)
    }

    @Test func aRejectedTokenIsRecognisedInTheCLIOutput() {
        let unauthorized = ProcessOutput(status: 1, stdout: "", stderr: "Unexpected error retrieving organizations: {\"message\":\"Unauthorized\"}")
        #expect(SupabaseCLIProcess.failure(unauthorized) == .rejectedToken)
        let loggedOut = ProcessOutput(status: 1, stdout: "", stderr: "Access token not provided. Supply an access token by running supabase login")
        #expect(SupabaseCLIProcess.failure(loggedOut) == .noCLISession)
    }
}

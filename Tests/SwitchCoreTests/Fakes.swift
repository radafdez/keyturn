import Foundation
@testable import SwitchCore

let tokenA = "sbp_" + String(repeating: "a", count: 40)
let tokenB = "sbp_" + String(repeating: "b", count: 40)
let tokenC = "sbp_" + String(repeating: "c", count: 40)

final class MemoryStore: StateStore, @unchecked Sendable {
    var state = SwitchState()
    var saves = 0

    func load() throws -> SwitchState { state }
    func save(_ state: SwitchState) throws {
        self.state = state
        saves += 1
    }
}

final class FakeKeychain: SecretStore, @unchecked Sendable {
    var values: [KeychainSlot: String] = [:]
    var stamps: [KeychainSlot: Int] = [:]
    var reads: [KeychainSlot] = []
    /// Slots whose macOS dialog the user denies. / Entradas cuyo aviso de macOS se deniega.
    var denied: Set<KeychainSlot> = []

    func read(_ slot: KeychainSlot) throws -> String? {
        reads.append(slot)
        if denied.contains(slot) { throw SwitchError.keychain("denied") }
        return values[slot].map(KeyringCodec.decode)
    }

    func write(_ secret: String, to slot: KeychainSlot) throws {
        values[slot] = secret
        stamps[slot, default: 0] += 1
    }

    func delete(_ slot: KeychainSlot) throws {
        values[slot] = nil
        stamps[slot] = nil
    }

    func modificationStamp(_ slot: KeychainSlot) -> String? {
        stamps[slot].map { "stamp-\($0)" }
    }
}

/// A CLI that keeps its login in the fake Keychain, like the real one does.
final class FakeCLI: SupabaseCLI, @unchecked Sendable {
    struct Remote {
        var organizations: [Organization]
        var projects: [Project]
    }

    let keychain: FakeKeychain
    var remotes: [String: Remote] = [:]
    var logins: [String] = []
    var organizationCalls = 0
    /// When set, `login` reports success but leaves the session as it was.
    var loginIsSilentlyIgnored = false
    var organizationsError: SwitchError?

    init(keychain: FakeKeychain) {
        self.keychain = keychain
    }

    func addRemote(token: String, org: String, name: String, projects: [String]) {
        remotes[token] = Remote(
            organizations: [Organization(id: org, name: name)],
            projects: projects.map { Project(ref: $0, name: "\(name) \($0)", region: "us-east-2") }
        )
    }

    /// What `supabase login` typed in a terminal would leave behind.
    func externalLogin(_ token: String, wrapped: Bool = false) {
        try! keychain.write(wrapped ? KeyringCodec.encode(token) : token, to: .supabaseCLI)
    }

    func externalLogout() {
        try! keychain.delete(.supabaseCLI)
    }

    func login(token: String) throws {
        logins.append(token)
        if !loginIsSilentlyIgnored { externalLogin(token) }
    }

    func organizations(token: String?) throws -> [Organization] {
        organizationCalls += 1
        if let organizationsError { throw organizationsError }
        return try remote(token).organizations
    }

    func projects(token: String?) throws -> [Project] {
        try remote(token).projects
    }

    private func remote(_ token: String?) throws -> Remote {
        guard let effective = token ?? keychain.values[.supabaseCLI].map(KeyringCodec.decode) else {
            throw SwitchError.noCLISession
        }
        guard let remote = remotes[effective] else { throw SwitchError.rejectedToken }
        return remote
    }
}

final class Clock: @unchecked Sendable {
    var date = Date(timeIntervalSince1970: 1_800_000_000)
    func advance(days: Double) { date = date.addingTimeInterval(days * 24 * 3600) }
}

struct World {
    let store = MemoryStore()
    let keychain = FakeKeychain()
    let clock = Clock()
    let cli: FakeCLI
    let service: SwitchService

    init() {
        cli = FakeCLI(keychain: keychain)
        cli.addRemote(token: tokenA, org: "org-acme", name: "Acme", projects: ["acmeprod", "acmestaging"])
        cli.addRemote(token: tokenB, org: "org-globex", name: "Globex", projects: ["globexprod", "globexstaging"])
        cli.addRemote(token: tokenC, org: "org-initech", name: "Initech", projects: ["initechprod"])
        let clock = self.clock
        service = SwitchService(store: store, secrets: keychain, cli: cli, now: { clock.date })
    }
}

import Foundation

/// Three made-up accounts that live only in memory: no file, no Keychain, no
/// CLI. For screenshots and for trying the app without touching real logins.
/// `SUPABASE_SWITCH_DEMO=1` turns it on.
///
/// Tres cuentas inventadas que viven solo en memoria: ni fichero, ni Llavero,
/// ni CLI. Para capturas de pantalla y para probar la app sin tocar sesiones
/// reales. Se enciende con `SUPABASE_SWITCH_DEMO=1`.
public enum Demo {
    public static var isOn: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["SUPABASE_SWITCH_DEMO"] == "1" || environment["SUPABASE_SWITCH_SNAPSHOTS"] != nil
    }

    public static func service(now: Date = Date()) -> SwitchService {
        let store = DemoStore()
        let secrets = DemoKeychain()
        let cli = DemoCLI(keychain: secrets)
        let service = SwitchService(store: store, secrets: secrets, cli: cli, now: { now })

        let acme = try! service.addAccount(token: DemoCLI.acme)
        let globex = try! service.addAccount(token: DemoCLI.globex)
        let initech = try! service.addAccount(token: DemoCLI.initech)
        try! service.renameProject("qkzrwbtyvmplxhndcafe", in: acme.id, to: "Acme prod")
        try! service.activate(globex.id, origin: .agent("claude-code"))

        func event(_ account: Account, _ kind: UsageEvent.Kind, hoursAgo: Double, _ origin: Origin) -> UsageEvent {
            UsageEvent(accountID: account.id, kind: kind, date: now.addingTimeInterval(-hoursAgo * 3600).rounded,
                       source: origin.source, client: origin.client)
        }
        store.state.history = [
            event(acme, .switched, hoursAgo: 190, .menu),
            event(initech, .switched, hoursAgo: 150, .terminal),
            event(initech, .ran, hoursAgo: 149, .terminal),
            event(acme, .switched, hoursAgo: 70, .agent("claude-code")),
            event(globex, .switched, hoursAgo: 52, .menu),
            event(acme, .switched, hoursAgo: 30, .agent("cursor")),
            event(acme, .ran, hoursAgo: 29, .terminal),
            event(globex, .switched, hoursAgo: 6, .menu),
            event(acme, .switched, hoursAgo: 2, .agent("claude-code")),
            event(globex, .switched, hoursAgo: 0.2, .agent("claude-code")),
        ]
        _ = initech
        return service
    }
}

private extension Date {
    var rounded: Date { Date(timeIntervalSince1970: timeIntervalSince1970.rounded(.down)) }
}

private final class DemoStore: StateStore, @unchecked Sendable {
    var state = SwitchState()
    func load() throws -> SwitchState { state }
    func save(_ state: SwitchState) throws { self.state = state }
}

private final class DemoKeychain: SecretStore, @unchecked Sendable {
    var values: [KeychainSlot: String] = [:]
    var stamps: [KeychainSlot: Int] = [:]

    func read(_ slot: KeychainSlot) throws -> String? { values[slot] }
    func write(_ secret: String, to slot: KeychainSlot) throws {
        values[slot] = secret
        stamps[slot, default: 0] += 1
    }
    func delete(_ slot: KeychainSlot) throws {
        values[slot] = nil
        stamps[slot] = nil
    }
    func modificationStamp(_ slot: KeychainSlot) -> String? { stamps[slot].map { "demo-\($0)" } }
}

private final class DemoCLI: SupabaseCLI, @unchecked Sendable {
    // Shaped like tokens so they pass the check, but all one digit: they only
    // key the made-up accounts below.
    // Con forma de token para pasar la comprobación, pero de un solo dígito:
    // solo identifican las cuentas inventadas de abajo.
    static let acme = "sbp_" + String(repeating: "1", count: 40)
    static let globex = "sbp_" + String(repeating: "2", count: 40)
    static let initech = "sbp_" + String(repeating: "3", count: 40)

    private let keychain: DemoKeychain
    private let remotes: [String: (Organization, [Project])] = [
        acme: (Organization(id: "org-acme", name: "Acme"), [
            Project(ref: "qkzrwbtyvmplxhndcafe", name: "acme-production", region: "us-east-1"),
            Project(ref: "fhtnwpqazmxkvlbrdeso", name: "acme-staging", region: "us-east-1"),
        ]),
        globex: (Organization(id: "org-globex", name: "Globex"), [
            Project(ref: "lmvqzrtckwxpbnhyadgu", name: "globex-web", region: "eu-west-2"),
        ]),
        initech: (Organization(id: "org-initech", name: "Initech"), [
            Project(ref: "zpxwnrqtkvmhbldcyeau", name: "initech-api", region: "us-west-1"),
        ]),
    ]

    init(keychain: DemoKeychain) { self.keychain = keychain }

    func login(token: String) throws { try keychain.write(token, to: .supabaseCLI) }
    func organizations(token: String?) throws -> [Organization] { [try remote(token).0] }
    func projects(token: String?) throws -> [Project] { try remote(token).1 }

    private func remote(_ token: String?) throws -> (Organization, [Project]) {
        guard let effective = token ?? keychain.values[.supabaseCLI] else { throw SwitchError.noCLISession }
        guard let remote = remotes[effective] else { throw SwitchError.rejectedToken }
        return remote
    }
}

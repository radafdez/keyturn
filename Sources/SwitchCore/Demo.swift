import Foundation

/// Three made-up accounts that live only in memory: no file, no Keychain, no
/// CLI. For screenshots and for trying the app without touching real logins.
/// `KEYTURN_DEMO=1` turns it on, and so does `KeyturnDemo` in
/// the Info.plist: a copy built to try an update, which Sparkle relaunches
/// without the environment.
///
/// Tres cuentas inventadas que viven solo en memoria: ni fichero, ni Llavero,
/// ni CLI. Para capturas de pantalla y para probar la app sin tocar sesiones
/// reales. Se enciende con `KEYTURN_DEMO=1`, y también con
/// `KeyturnDemo` en el Info.plist: una copia hecha para probar una
/// actualización, que Sparkle vuelve a abrir sin el entorno.
public enum Demo {
    public static var isOn: Bool {
        let environment = ProcessInfo.processInfo.environment
        return environment["KEYTURN_DEMO"] == "1" || environment["KEYTURN_SNAPSHOTS"] != nil
            || Bundle.main.object(forInfoDictionaryKey: "KeyturnDemo") as? Bool == true
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

// MARK: - CLIs

public extension Demo {
    /// Made-up tools running and a week of made-up history, for the CLIs pane.
    /// Herramientas inventadas corriendo y una semana de historial inventado,
    /// para el panel de CLIs.
    static func cliMonitor(now: Date = Date()) -> CLIMonitor {
        let now = now.rounded
        func ago(_ minutes: Double) -> Date { now.addingTimeInterval(-minutes * 60) }
        let terminal = "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal"
        let cursor = "/Applications/Cursor.app/Contents/MacOS/Cursor"
        let processes = DemoProcesses(list: [
            RunningProcess(pid: 400, parent: 1, started: ago(600), path: terminal),
            RunningProcess(pid: 401, parent: 400, started: ago(300), path: "/usr/bin/login", isMine: false),
            RunningProcess(pid: 402, parent: 401, started: ago(300), path: "/bin/zsh", arguments: ["-zsh"]),
            RunningProcess(pid: 403, parent: 402, started: ago(72), path: "/Users/demo/.local/share/claude/versions/2.1.0", arguments: ["claude"]),
            RunningProcess(pid: 404, parent: 403, started: ago(3), path: "/opt/homebrew/bin/supabase", arguments: ["supabase", "db", "push"]),
            RunningProcess(pid: 500, parent: 1, started: ago(900), path: cursor),
            RunningProcess(pid: 501, parent: 500, started: ago(500), path: "/bin/zsh", arguments: ["-zsh"]),
            RunningProcess(pid: 502, parent: 501, started: ago(25), path: "/opt/homebrew/bin/node",
                           arguments: ["node", "/opt/homebrew/lib/node_modules/vercel/dist/index.js", "dev"]),
            RunningProcess(pid: 503, parent: 501, started: ago(41), path: "/opt/homebrew/bin/stripe", arguments: ["stripe", "listen"]),
        ])

        func session(_ tool: String, from start: Double, minutes: Double, _ host: String, via: String? = nil) -> CLISession {
            CLISession(tool: tool, pid: Int32.random(in: 1000...9000), started: ago(start), lastSeen: ago(start - minutes),
                       ended: ago(start - minutes), host: host, via: via)
        }
        let history = CLIActivity(sessions: [
            session("claude", from: 6 * 1440, minutes: 160, "Terminal"),
            session("supabase", from: 6 * 1440 - 30, minutes: 4, "Terminal", via: "claude"),
            session("codex", from: 5 * 1440, minutes: 95, "Cursor"),
            session("gh", from: 4 * 1440, minutes: 2, "Terminal"),
            session("claude", from: 3 * 1440, minutes: 210, "Claude"),
            session("vercel", from: 2 * 1440, minutes: 48, "Cursor"),
            session("supabase", from: 1440 + 120, minutes: 35, "Terminal"),
            session("claude", from: 1440, minutes: 130, "Terminal"),
            session("gemini", from: 400, minutes: 22, "iTerm"),
            session("codex", from: 300, minutes: 64, "Cursor"),
            session("supabase", from: 160, minutes: 12, "Terminal", via: "codex"),
            session("gh", from: 120, minutes: 1, "Terminal"),
        ])
        let monitor = CLIMonitor(source: processes, store: DemoCLIStore(activity: history), ownPID: 1)
        monitor.scan(now: now)
        return monitor
    }
}

private struct DemoProcesses: ProcessSource {
    let list: [RunningProcess]
    func processes() -> [RunningProcess] { list }
}

private final class DemoCLIStore: CLIActivityStore, @unchecked Sendable {
    var activity: CLIActivity
    init(activity: CLIActivity) { self.activity = activity }
    func load() throws -> CLIActivity { activity }
    func save(_ activity: CLIActivity) throws { self.activity = activity }
}

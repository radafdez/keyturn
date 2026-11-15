import Foundation

/// A Model Context Protocol server over stdio, so an AI agent (Claude Code,
/// Codex, Cursor…) can see the accounts and switch the CLI to the one a
/// project needs. One JSON-RPC message per line; nothing else goes to stdout.
///
/// Agents get no tokens and cannot add, remove or rename accounts, nor run
/// commands through this server. Every switch is recorded with the client's
/// name, and the user can forbid switching (reading stays allowed).
///
/// Un servidor del Model Context Protocol por stdio, para que un agente de IA
/// (Claude Code, Codex, Cursor…) vea las cuentas y cambie el CLI a la que pide
/// un proyecto. Un mensaje JSON-RPC por línea; a stdout no va nada más.
///
/// Los agentes no reciben tokens ni pueden añadir, quitar o renombrar cuentas,
/// ni lanzar órdenes a través de este servidor. Cada cambio se apunta con el
/// nombre del cliente, y el usuario puede prohibir cambiar (consultar, no).
public final class MCPServer {
    public static let name = "supabase-switch"
    /// Newest first. An unknown version asked by the client gets the newest.
    /// La más nueva primero. A una versión desconocida se le responde con la más nueva.
    public static let protocolVersions = ["2025-11-25", "2025-06-18", "2025-03-26", "2024-11-05"]

    private let makeService: () throws -> SwitchService
    private var service: SwitchService?
    /// How the client named itself in `initialize`, e.g. "claude-code".
    /// Cómo se presentó el cliente en `initialize`, p. ej. «claude-code».
    public private(set) var clientName: String?

    public init(service makeService: @escaping () throws -> SwitchService) {
        self.makeService = makeService
    }

    /// Reads requests from stdin until it closes. / Lee peticiones de stdin hasta que se cierra.
    public func run() {
        while let line = readLine(strippingNewline: true) {
            guard let reply = handle(line) else { continue }
            FileHandle.standardOutput.write(Data((reply + "\n").utf8))
        }
    }

    // MARK: JSON-RPC

    /// The answer to one line, or nil for a notification.
    /// La respuesta a una línea, o nil si era una notificación.
    public func handle(_ line: String) -> String? {
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let data = line.data(using: .utf8),
              let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return Self.encode(["jsonrpc": "2.0", "id": NSNull(), "error": ["code": -32700, "message": "Parse error"]])
        }
        guard let method = message["method"] as? String else {
            // A response to something we never asked: ignore it.
            // La respuesta a algo que nunca preguntamos: se ignora.
            if message["id"] != nil, message["result"] != nil || message["error"] != nil { return nil }
            return Self.encode(["jsonrpc": "2.0", "id": message["id"] ?? NSNull(), "error": ["code": -32600, "message": "Invalid request"]])
        }
        guard let id = message["id"], !(id is NSNull) else { return nil } // notification
        let params = message["params"] as? [String: Any] ?? [:]

        do {
            let result = try dispatch(method, params)
            return Self.encode(["jsonrpc": "2.0", "id": id, "result": result])
        } catch let failure as RPCFailure {
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": failure.code, "message": failure.message]])
        } catch {
            return Self.encode(["jsonrpc": "2.0", "id": id, "error": ["code": -32603, "message": error.localizedDescription]])
        }
    }

    private struct RPCFailure: Error {
        var code: Int
        var message: String
    }

    private func dispatch(_ method: String, _ params: [String: Any]) throws -> [String: Any] {
        switch method {
        case "initialize":
            clientName = (params["clientInfo"] as? [String: Any])?["name"] as? String
            let asked = params["protocolVersion"] as? String ?? ""
            return [
                "protocolVersion": Self.protocolVersions.contains(asked) ? asked : Self.protocolVersions[0],
                "capabilities": ["tools": ["listChanged": false]],
                "serverInfo": ["name": Self.name, "title": "Supabase Switch", "version": switchVersion],
                "instructions": Self.instructions,
            ]
        case "ping":
            return [:]
        case "tools/list":
            return ["tools": Self.tools]
        case "tools/call":
            guard let name = params["name"] as? String else { throw RPCFailure(code: -32602, message: "Missing tool name") }
            let arguments = params["arguments"] as? [String: Any] ?? [:]
            return try call(name, arguments)
        default:
            throw RPCFailure(code: -32601, message: "Method not found: \(method)")
        }
    }

    // MARK: Tools

    static let instructions = """
    The Supabase CLI keeps ONE login for the whole Mac, and the user has projects in several \
    Supabase accounts. Before running a `supabase` command that targets a remote project \
    (link, db push, db pull, migration list, functions deploy, secrets, anything with \
    --project-ref), call `use_project` with that project's ref: it switches the CLI to the \
    account that owns it, or does nothing if it is already there. The ref is the 20-letter id \
    in https://<ref>.supabase.co, in supabase/.temp/project-ref after `supabase link`, or in a \
    --project-ref flag. A switch changes the login for every terminal on this Mac: tell the user \
    which account you switched to. You never see tokens, and you cannot add or remove accounts.
    """

    static let tools: [[String: Any]] = [
        [
            "name": "list_accounts",
            "title": "List Supabase accounts",
            "description": "The Supabase accounts registered in Supabase Switch, the projects of each (ref, name, local alias, region), and which account the Supabase CLI is logged in as now.",
            "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            "annotations": ["title": "List Supabase accounts", "readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "current_account",
            "title": "Current Supabase CLI account",
            "description": "Which registered account the Supabase CLI is logged in as right now (asks the CLI, so it is always up to date).",
            "inputSchema": ["type": "object", "properties": [String: Any](), "additionalProperties": false],
            "annotations": ["title": "Current Supabase CLI account", "readOnlyHint": true, "openWorldHint": false],
        ],
        [
            "name": "use_project",
            "title": "Use a Supabase project",
            "description": "Makes the Supabase CLI able to work on one project: switches to the account that owns it, or does nothing when the CLI is already on it. Call it before any supabase command that targets that project. The switch applies to every terminal on this Mac.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "project": ["type": "string", "description": "The project's ref (20 lowercase letters), its local alias or its name."],
                ],
                "required": ["project"],
                "additionalProperties": false,
            ],
            "annotations": ["title": "Use a Supabase project", "readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false],
        ],
        [
            "name": "switch_account",
            "title": "Switch Supabase account",
            "description": "Logs the Supabase CLI in as one registered account, by its name (or the start of it). Prefer use_project when you know the project. The switch applies to every terminal on this Mac.",
            "inputSchema": [
                "type": "object",
                "properties": [
                    "account": ["type": "string", "description": "The account's name as shown by list_accounts, or the start of it."],
                ],
                "required": ["account"],
                "additionalProperties": false,
            ],
            "annotations": ["title": "Switch Supabase account", "readOnlyHint": false, "destructiveHint": false, "idempotentHint": true, "openWorldHint": false],
        ],
    ]

    private func call(_ name: String, _ arguments: [String: Any]) throws -> [String: Any] {
        guard Self.tools.contains(where: { $0["name"] as? String == name }) else {
            throw RPCFailure(code: -32602, message: "Unknown tool: \(name)")
        }
        // Tool failures go back as results the model can read and act on.
        // Los fallos de una herramienta vuelven como resultado que el modelo puede leer.
        do {
            let service = try loadService()
            switch name {
            case "list_accounts":
                let snapshot = try service.snapshot()
                return Self.result(Self.describe(snapshot), structured: Self.structure(snapshot))
            case "current_account":
                let snapshot = try service.snapshot(askingTheCLIAgain: true)
                return Self.result(Self.sessionSentence(snapshot), structured: [
                    "account": snapshot.activeAccount?.name ?? NSNull(),
                    "status": Self.statusName(snapshot.session),
                    "agentsCanSwitch": snapshot.agentsCanSwitch,
                ])
            case "use_project":
                let query = try Self.argument("project", in: arguments)
                let use = try service.useProject(query, origin: .agent(clientName))
                let project = use.project.alias.map { "“\($0)” (\(use.project.ref))" } ?? "“\(use.project.name)” (\(use.project.ref))"
                let text = use.switched
                    ? "Switched the Supabase CLI to the account “\(use.account.name)”, which owns \(project). Every terminal on this Mac now uses that account."
                    : "The Supabase CLI was already on “\(use.account.name)”, which owns \(project). Nothing changed."
                return Self.result(text, structured: [
                    "account": use.account.name, "project": use.project.ref, "switched": use.switched,
                ])
            case "switch_account":
                let query = try Self.argument("account", in: arguments)
                let before = try service.snapshot()
                let target = try SwitchService.resolve(query, in: before.accounts)
                if before.activeAccount?.id == target.id {
                    return Self.result("The Supabase CLI was already on “\(target.name)”. Nothing changed.",
                                       structured: ["account": target.name, "switched": false])
                }
                try service.activate(target.id, origin: .agent(clientName))
                return Self.result("Switched the Supabase CLI to “\(target.name)”. Every terminal on this Mac now uses that account.",
                                   structured: ["account": target.name, "switched": true])
            default:
                throw RPCFailure(code: -32602, message: "Unknown tool: \(name)")
            }
        } catch let failure as RPCFailure {
            throw failure
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return ["content": [["type": "text", "text": message]], "isError": true]
        }
    }

    private func loadService() throws -> SwitchService {
        if let service { return service }
        let created = try makeService()
        service = created
        return created
    }

    // MARK: Answers

    private struct MissingArgument: LocalizedError {
        var name: String
        var errorDescription: String? { "The argument “\(name)” is required." }
    }

    private static func argument(_ name: String, in arguments: [String: Any]) throws -> String {
        guard let value = arguments[name] as? String, !value.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw MissingArgument(name: name)
        }
        return value
    }

    private static func result(_ text: String, structured: [String: Any]) -> [String: Any] {
        ["content": [["type": "text", "text": text]], "structuredContent": structured, "isError": false]
    }

    static func structure(_ snapshot: Snapshot) -> [String: Any] {
        [
            "cliAccount": snapshot.activeAccount?.name ?? NSNull(),
            "status": statusName(snapshot.session),
            "agentsCanSwitch": snapshot.agentsCanSwitch,
            "accounts": snapshot.accounts.map { account -> [String: Any] in
                [
                    "name": account.name,
                    "inUse": snapshot.activeAccount?.id == account.id,
                    "projects": account.projects.map { project -> [String: Any] in
                        var entry: [String: Any] = ["ref": project.ref, "name": project.name, "region": project.region]
                        if let alias = project.alias { entry["alias"] = alias }
                        return entry
                    },
                ]
            },
        ]
    }

    static func describe(_ snapshot: Snapshot) -> String {
        guard !snapshot.accounts.isEmpty else {
            return "No accounts are registered in Supabase Switch yet. The user registers them from its menu bar icon."
        }
        var lines = [sessionSentence(snapshot)]
        if !snapshot.agentsCanSwitch { lines.append("Switching by agents is turned off: you can read, not switch.") }
        for account in snapshot.accounts {
            lines.append("")
            lines.append("\(account.name)\(snapshot.activeAccount?.id == account.id ? " (in use)" : "")")
            for project in account.projects {
                let alias = project.alias.map { " — alias “\($0)”" } ?? ""
                lines.append("  \(project.ref)  \(project.name)\(alias)  \(project.region)")
            }
            if account.projects.isEmpty { lines.append("  (no projects)") }
        }
        return lines.joined(separator: "\n")
    }

    static func sessionSentence(_ snapshot: Snapshot) -> String {
        switch snapshot.session {
        case .none: return "The Supabase CLI has no stored login."
        case .account: return "The Supabase CLI is logged in as “\(snapshot.activeAccount?.name ?? "?")”."
        case .unregistered: return "The Supabase CLI is logged in as an account that is not registered in Supabase Switch."
        case .unverified(let detail): return "The Supabase CLI has a login, but it could not say whose: \(detail)"
        }
    }

    static func statusName(_ session: SessionStatus) -> String {
        switch session {
        case .none: return "no_login"
        case .account: return "registered"
        case .unregistered: return "unregistered"
        case .unverified: return "unverified"
        }
    }

    static func encode(_ object: [String: Any]) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }
}

import Foundation

/// Something worth counting: a switch, or one command run with `sbswitch run`.
/// Only the account, the kind and the time are kept — never the command.
///
/// Algo que merece contarse: un cambio, o una orden lanzada con `sbswitch run`.
/// Solo se guardan la cuenta, el tipo y la hora; nunca la orden.
public struct UsageEvent: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case switched
        case ran
    }

    /// Who asked. Nil for events recorded before 1.2.
    /// Quién lo pidió. Nil en los eventos anteriores a la 1.2.
    public enum Source: String, Codable, Sendable, CaseIterable {
        /// The menu bar app. / La app de la barra de menús.
        case menu
        /// `sbswitch` typed in a terminal. / `sbswitch` escrito en una terminal.
        case terminal
        /// An AI agent through `sbswitch mcp`. / Un agente de IA a través de `sbswitch mcp`.
        case agent
    }

    public var accountID: UUID
    public var kind: Kind
    public var date: Date
    public var source: Source?
    /// For agents, the MCP client that asked, as it names itself ("claude-code").
    /// En los agentes, el cliente MCP que lo pidió, como se llama a sí mismo («claude-code»).
    public var client: String?

    public init(accountID: UUID, kind: Kind, date: Date, source: Source? = nil, client: String? = nil) {
        self.accountID = accountID
        self.kind = kind
        self.date = date
        self.source = source
        self.client = client
    }

    /// Older events are dropped past this many, so the file stays small.
    /// Pasado este número se descartan los más viejos y el fichero sigue pequeño.
    public static let limit = 1000
}

/// Who is asking for a switch or a run, so the history can tell.
/// Quién pide un cambio o una orden, para que el historial lo sepa.
public struct Origin: Equatable, Sendable {
    public var source: UsageEvent.Source
    public var client: String?

    public init(source: UsageEvent.Source, client: String? = nil) {
        self.source = source
        self.client = client
    }

    public static let menu = Origin(source: .menu)
    public static let terminal = Origin(source: .terminal)
    public static func agent(_ client: String?) -> Origin { Origin(source: .agent, client: client) }
}

public struct ClientCount: Equatable, Sendable, Identifiable {
    public var client: String
    public var switches: Int
    public var id: String { client }
}

public struct AccountUsage: Equatable, Sendable, Identifiable {
    public var account: Account
    public var switches: Int
    public var runs: Int
    public var switchesThisWeek: Int
    public var lastUsed: Date?

    public var id: UUID { account.id }
}

public struct UsageSummary: Equatable, Sendable {
    /// Most switched to first, then most runs. / Primero la más cambiada, luego más órdenes.
    public var accounts: [AccountUsage]
    public var totalSwitches: Int
    public var totalRuns: Int
    /// The oldest event kept. / El evento más antiguo que se conserva.
    public var since: Date?
    /// Switches by who asked; events from before 1.2 count as `nil`.
    /// Cambios según quién los pidió; los anteriores a la 1.2 cuentan como `nil`.
    public var switchesBySource: [UsageEvent.Source?: Int]
    /// Switches made by each agent, most first.
    /// Cambios hechos por cada agente, de más a menos.
    public var agentClients: [ClientCount]
    /// The latest events, newest first. / Los últimos eventos, el más nuevo primero.
    public var recent: [UsageEvent]

    public static let recentLimit = 50

    public init(accounts: [Account], events: [UsageEvent], now: Date) {
        let weekAgo = now.addingTimeInterval(-7 * 24 * 3600)
        let byAccount = Dictionary(grouping: events, by: \.accountID)
        self.accounts = accounts.map { account in
            let own = byAccount[account.id] ?? []
            let switches = own.filter { $0.kind == .switched }
            return AccountUsage(
                account: account,
                switches: switches.count,
                runs: own.count - switches.count,
                switchesThisWeek: switches.filter { $0.date >= weekAgo }.count,
                lastUsed: own.map(\.date).max()
            )
        }
        .enumerated()
        .sorted { lhs, rhs in
            let (l, r) = (lhs.element, rhs.element)
            if l.switches != r.switches { return l.switches > r.switches }
            if l.runs != r.runs { return l.runs > r.runs }
            return lhs.offset < rhs.offset
        }
        .map(\.element)
        let known = Set(accounts.map(\.id))
        let counted = events.filter { known.contains($0.accountID) }
        totalSwitches = counted.filter { $0.kind == .switched }.count
        totalRuns = counted.count - totalSwitches
        since = counted.map(\.date).min()

        let switched = counted.filter { $0.kind == .switched }
        switchesBySource = Dictionary(grouping: switched, by: \.source).mapValues(\.count)
        agentClients = Dictionary(grouping: switched.filter { $0.source == .agent }, by: { $0.client ?? "?" })
            .map { ClientCount(client: $0.key, switches: $0.value.count) }
            .sorted { $0.switches != $1.switches ? $0.switches > $1.switches : $0.client < $1.client }
        recent = Array(counted.reversed().prefix(Self.recentLimit))
    }

    public func usage(of id: UUID) -> AccountUsage? {
        accounts.first { $0.account.id == id }
    }
}

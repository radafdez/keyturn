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

    public var accountID: UUID
    public var kind: Kind
    public var date: Date

    public init(accountID: UUID, kind: Kind, date: Date) {
        self.accountID = accountID
        self.kind = kind
        self.date = date
    }

    /// Older events are dropped past this many, so the file stays small.
    /// Pasado este número se descartan los más viejos y el fichero sigue pequeño.
    public static let limit = 1000
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
    }

    public func usage(of id: UUID) -> AccountUsage? {
        accounts.first { $0.account.id == id }
    }
}

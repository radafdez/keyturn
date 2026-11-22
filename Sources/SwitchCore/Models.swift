import Foundation

public struct Project: Codable, Equatable, Identifiable, Sendable {
    public var ref: String
    /// The name in Supabase. / El nombre en Supabase.
    public var name: String
    public var region: String
    /// A local name chosen by the user. Supabase never sees it.
    /// Un nombre local que elige el usuario. Supabase nunca lo ve.
    public var alias: String?

    public var id: String { ref }
    public var displayName: String { alias ?? name }

    public init(ref: String, name: String, region: String, alias: String? = nil) {
        self.ref = ref
        self.name = name
        self.region = region
        self.alias = alias
    }
}

public struct Organization: Codable, Equatable, Sendable {
    public var id: String
    public var name: String

    public init(id: String, name: String) {
        self.id = id
        self.name = name
    }
}

/// One Supabase login. Its token never lives here: it stays in the Keychain.
/// Un inicio de sesión de Supabase. El token no vive aquí: se queda en el Llavero.
public struct Account: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var name: String
    /// What tells one account from another without reading any token.
    /// Lo que distingue una cuenta de otra sin leer ningún token.
    public var organizationIDs: [String]
    public var projects: [Project]
    /// Nil for accounts registered before 1.1. / Nil en las registradas antes de la 1.1.
    public var createdAt: Date?

    public init(id: UUID = UUID(), name: String, organizationIDs: [String], projects: [Project], createdAt: Date? = nil) {
        self.id = id
        self.name = name
        self.organizationIDs = organizationIDs
        self.projects = projects
        self.createdAt = createdAt
    }
}

public struct SwitchState: Codable, Equatable, Sendable {
    public var accounts: [Account]
    public var activeAccountID: UUID?
    /// Modification stamp of the CLI's Keychain entry when `activeAccountID` was
    /// last confirmed. A different stamp means someone logged in outside the app.
    /// Sello de modificación de la entrada del CLI cuando se confirmó
    /// `activeAccountID`. Si cambia, alguien inició sesión fuera de la app.
    public var sessionStamp: String?
    public var history: [UsageEvent]
    /// Whether `keyturn mcp` may change the CLI's login. Reading is always allowed.
    /// Si `keyturn mcp` puede cambiar la sesión del CLI. Consultar siempre se puede.
    public var agentsCanSwitch: Bool
    /// The login the CLI has now, of an account not registered yet. Keyturn
    /// never switches over it without saving it first.
    /// La sesión que tiene ahora el CLI, de una cuenta aún sin registrar.
    /// Keyturn nunca cambia por encima de ella sin guardarla antes.
    public var pendingLogin: PendingLogin?
    /// A login that was replaced before anyone captured it: the user has to
    /// log in with it again.
    /// Una sesión que se sustituyó antes de que nadie la capturara: hay que
    /// volver a iniciarla.
    public var lostLogin: LostLogin?

    public init(accounts: [Account] = [], activeAccountID: UUID? = nil, sessionStamp: String? = nil, history: [UsageEvent] = [],
                agentsCanSwitch: Bool = true, pendingLogin: PendingLogin? = nil, lostLogin: LostLogin? = nil) {
        self.accounts = accounts
        self.activeAccountID = activeAccountID
        self.sessionStamp = sessionStamp
        self.history = history
        self.agentsCanSwitch = agentsCanSwitch
        self.pendingLogin = pendingLogin
        self.lostLogin = lostLogin
    }

    // A file written by 1.0 has no history: it must still open.
    // Un fichero escrito por la 1.0 no tiene historial: tiene que abrirse igual.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        accounts = try container.decode([Account].self, forKey: .accounts)
        activeAccountID = try container.decodeIfPresent(UUID.self, forKey: .activeAccountID)
        sessionStamp = try container.decodeIfPresent(String.self, forKey: .sessionStamp)
        history = try container.decodeIfPresent([UsageEvent].self, forKey: .history) ?? []
        agentsCanSwitch = try container.decodeIfPresent(Bool.self, forKey: .agentsCanSwitch) ?? true
        pendingLogin = try container.decodeIfPresent(PendingLogin.self, forKey: .pendingLogin)
        lostLogin = try container.decodeIfPresent(LostLogin.self, forKey: .lostLogin)
    }

    mutating func record(_ kind: UsageEvent.Kind, for id: UUID, at date: Date, origin: Origin) {
        history.append(UsageEvent(accountID: id, kind: kind, date: date, source: origin.source, client: origin.client))
        if history.count > UsageEvent.limit { history.removeFirst(history.count - UsageEvent.limit) }
    }
}

/// A login of an account Keyturn does not know, as the CLI described it.
/// Una sesión de una cuenta que Keyturn no conoce, tal como la describió el CLI.
public struct PendingLogin: Codable, Equatable, Sendable {
    /// The CLI's Keychain stamp when it was seen. / El sello del Llavero del CLI cuando se vio.
    public var stamp: String
    public var organizationIDs: [String]
    /// Its first organization's name: what a capture would call it.
    /// El nombre de su primera organización: como la llamaría una captura.
    public var name: String

    public init(stamp: String, organizationIDs: [String], name: String) {
        self.stamp = stamp
        self.organizationIDs = organizationIDs
        self.name = name
    }
}

public struct LostLogin: Codable, Equatable, Sendable {
    public var name: String
    public var organizationIDs: [String]
    public var date: Date

    public init(name: String, organizationIDs: [String], date: Date) {
        self.name = name
        self.organizationIDs = organizationIDs
        self.date = date
    }
}

public enum SessionStatus: Equatable, Sendable {
    /// The CLI has no stored login. / El CLI no tiene sesión guardada.
    case none
    case account(UUID)
    /// Logged in with an account this app does not know.
    /// Hay sesión, pero de una cuenta que la app no conoce.
    case unregistered
    /// There is a login but the CLI could not say whose it is.
    /// Hay sesión, pero el CLI no pudo decir de quién es.
    case unverified(String)
}

public struct Snapshot: Equatable, Sendable {
    public var accounts: [Account]
    public var session: SessionStatus
    public var usage: UsageSummary
    public var agentsCanSwitch: Bool
    /// Nil unless a login was replaced before it was captured.
    /// Nil salvo que una sesión se sustituyera antes de capturarla.
    public var lostLogin: LostLogin?

    public init(accounts: [Account], session: SessionStatus, usage: UsageSummary? = nil, agentsCanSwitch: Bool = true,
                lostLogin: LostLogin? = nil) {
        self.accounts = accounts
        self.session = session
        self.usage = usage ?? UsageSummary(accounts: accounts, events: [], now: Date())
        self.agentsCanSwitch = agentsCanSwitch
        self.lostLogin = lostLogin
    }

    public var activeAccount: Account? {
        guard case .account(let id) = session else { return nil }
        return accounts.first { $0.id == id }
    }
}

/// What `useProject` did. / Lo que hizo `useProject`.
public struct ProjectUse: Equatable, Sendable {
    public var account: Account
    public var project: Project
    /// False when the CLI was already on that account. / False si el CLI ya estaba en esa cuenta.
    public var switched: Bool
}

public enum SwitchError: LocalizedError, Equatable {
    case invalidToken
    case rejectedToken
    case noCLISession
    case missingToken(String)
    case unknownAccount
    case unknownProject(String)
    case cliNotFound
    case cliFailed(String)
    case keychain(String)
    case timeout(String)
    case noMatch(String)
    case ambiguous(String, [String])
    case agentsNotAllowed
    /// Switching now would throw away a login that is not registered yet.
    /// Cambiar ahora tiraría una sesión que aún no está registrada.
    case unregisteredLogin(String)
    /// The login could not be saved before switching, so nothing changed.
    /// No se pudo guardar la sesión antes de cambiar, así que no cambió nada.
    case couldNotKeepLogin(String, String)

    public var errorDescription: String? {
        switch self {
        case .invalidToken:
            return tr("That does not look like a Supabase access token (they start with “sbp_”).",
                      "Eso no parece un token de Supabase (empiezan por «sbp_»).")
        case .rejectedToken:
            return tr("Supabase rejected the token: it was revoked or copied wrong.",
                      "Supabase rechazó el token: está revocado o mal copiado.")
        case .noCLISession:
            return tr("The CLI has no stored login. Run `supabase login` first.",
                      "El CLI no tiene ninguna sesión guardada. Haz `supabase login` primero.")
        case .missingToken(let name):
            return tr("The token of “\(name)” is not in the Keychain. Add the account again.",
                      "No encuentro el token de «\(name)» en el Llavero. Vuelve a añadir la cuenta.")
        case .unknownAccount:
            return tr("That account is no longer registered.", "Esa cuenta ya no está registrada.")
        case .unknownProject(let query):
            return tr("No project is called “\(query)”.", "No hay ningún proyecto que se llame «\(query)».")
        case .cliNotFound:
            return tr("The Supabase CLI was not found (looked in /opt/homebrew/bin, /usr/local/bin and the shell's PATH).",
                      "No encuentro el CLI de Supabase (busqué en /opt/homebrew/bin, /usr/local/bin y el PATH del shell).")
        case .cliFailed(let detail):
            return tr("The Supabase CLI failed: \(detail)", "El CLI de Supabase falló: \(detail)")
        case .keychain(let detail):
            return tr("The Keychain did not answer: \(detail)", "El Llavero no respondió: \(detail)")
        case .timeout(let what):
            return tr("Timed out waiting for \(what).", "Se agotó el tiempo esperando a \(what).")
        case .noMatch(let query):
            return tr("No account or project is called “\(query)”.",
                      "No hay ninguna cuenta ni proyecto que se llame «\(query)».")
        case .ambiguous(let query, let names):
            return tr("“\(query)” matches several: \(names.joined(separator: ", ")).",
                      "«\(query)» encaja con varias: \(names.joined(separator: ", ")).")
        case .agentsNotAllowed:
            return tr("Agents may not switch accounts: that is turned off in Keyturn → Settings → Agents. Ask the user to switch, or to turn it on.",
                      "Los agentes no pueden cambiar de cuenta: está desactivado en Keyturn → Ajustes → Agentes. Pide al usuario que cambie, o que lo active.")
        case .unregisteredLogin(let name):
            return tr("The Supabase CLI is logged in as “\(name)”, an account not registered in Keyturn yet. Switching now would throw that login away, so nothing was changed. Ask the user to capture it first (Keyturn menu → Capture, or `keyturn capture`), then try again. If that login is not needed, `supabase logout` lets the switch go ahead.",
                      "El CLI de Supabase está en «\(name)», una cuenta que aún no está registrada en Keyturn. Cambiar ahora tiraría esa sesión, así que no se cambió nada. Pide al usuario que la capture primero (menú de Keyturn → Capturar, o `keyturn capture`) y vuelve a intentarlo. Si esa sesión no hace falta, `supabase logout` deja hacer el cambio.")
        case .couldNotKeepLogin(let name, let detail):
            return tr("Before switching I tried to save the login of “\(name)”, which is not registered yet, and could not: \(detail). Nothing was changed, so the login is still there. Press Capture to try again.",
                      "Antes de cambiar intenté guardar la sesión de «\(name)», que aún no está registrada, y no pude: \(detail). No se cambió nada, así que la sesión sigue ahí. Pulsa Capturar para reintentarlo.")
        }
    }
}

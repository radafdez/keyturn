import Foundation

public struct KeychainSlot: Equatable, Hashable, Sendable {
    public var service: String
    public var account: String

    public init(service: String, account: String) {
        self.service = service
        self.account = account
    }

    /// Where the Supabase CLI keeps its login (account = profile name).
    /// Donde el CLI de Supabase guarda su sesión (account = nombre del perfil).
    public static let supabaseCLI = KeychainSlot(service: "Supabase CLI", account: "supabase")

    /// Where this app keeps the token of one registered account. A separate
    /// service on purpose: `supabase logout` wipes everything under "Supabase CLI".
    /// Donde esta app guarda el token de una cuenta. Servicio aparte a propósito:
    /// `supabase logout` borra todo lo que hay bajo «Supabase CLI».
    public static func stored(_ id: UUID) -> KeychainSlot {
        KeychainSlot(service: ownService, account: id.uuidString)
    }

    public static let ownService = "Supabase Switch"
}

public protocol SecretStore: Sendable {
    func read(_ slot: KeychainSlot) throws -> String?
    func write(_ secret: String, to slot: KeychainSlot) throws
    func delete(_ slot: KeychainSlot) throws
    /// Changes whenever the entry is rewritten; nil when it does not exist.
    /// Never reveals the secret, so it never triggers a Keychain prompt.
    /// Cambia cada vez que se reescribe la entrada; nil si no existe.
    /// No revela el secreto, así que nunca provoca un aviso del Llavero.
    func modificationStamp(_ slot: KeychainSlot) -> String?
}

/// The Supabase CLI is the only thing that talks to Supabase: the app never
/// calls the API on its own, so both always agree on what an account is.
/// `token == nil` means "whatever login the CLI has right now".
/// El CLI de Supabase es lo único que habla con Supabase: la app nunca llama a
/// la API por su cuenta, así que los dos coinciden siempre en qué es una cuenta.
/// `token == nil` significa «la sesión que el CLI tenga ahora mismo».
public protocol SupabaseCLI: Sendable {
    /// Makes the CLI store `token` as its login.
    /// Hace que el CLI guarde `token` como su sesión.
    func login(token: String) throws
    func organizations(token: String?) throws -> [Organization]
    func projects(token: String?) throws -> [Project]
}

public protocol StateStore: Sendable {
    func load() throws -> SwitchState
    func save(_ state: SwitchState) throws
}

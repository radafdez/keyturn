import Foundation

/// Every operation of the app, with no UI and no real Keychain or CLI inside:
/// the three collaborators come in from outside, so the tests swap them.
/// Todas las operaciones de la app, sin interfaz y sin Llavero ni CLI reales
/// dentro: los tres colaboradores entran por fuera y los tests los sustituyen.
public final class SwitchService: @unchecked Sendable {
    private let store: StateStore
    private let secrets: SecretStore
    private let cli: SupabaseCLI
    private let now: @Sendable () -> Date
    private let lock = NSLock()

    public init(store: StateStore, secrets: SecretStore, cli: SupabaseCLI, now: @escaping @Sendable () -> Date = { Date() }) {
        self.store = store
        self.secrets = secrets
        self.cli = cli
        self.now = now
    }

    public static func live() throws -> SwitchService {
        SwitchService(store: FileStateStore.standard(), secrets: SecurityToolKeychain(), cli: try SupabaseCLIProcess.locate())
    }

    // MARK: Reading

    /// Accounts plus who the CLI is logged in as right now.
    ///
    /// The CLI is asked only when its Keychain entry changed since the last
    /// look; otherwise the answer is the one already written down. That keeps
    /// this cheap enough to run every time the menu opens.
    ///
    /// Las cuentas y con cuál tiene sesión el CLI ahora mismo.
    ///
    /// Al CLI solo se le pregunta si su entrada del Llavero cambió desde la
    /// última vez; si no, vale lo que ya estaba apuntado. Así sale lo bastante
    /// barato como para ejecutarlo cada vez que se abre el menú.
    public func snapshot(askingTheCLIAgain: Bool = false) throws -> Snapshot {
        try locked {
            var state = try store.load()
            if askingTheCLIAgain { state.sessionStamp = nil }
            let session = try resolveSession(&state)
            return makeSnapshot(state, session: session)
        }
    }

    /// The file keeps dates to the second; so must what is written to it.
    /// El fichero guarda las fechas al segundo; lo que se escribe, también.
    private func wholeSecond() -> Date {
        Date(timeIntervalSince1970: now().timeIntervalSince1970.rounded(.down))
    }

    private func makeSnapshot(_ state: SwitchState, session: SessionStatus) -> Snapshot {
        Snapshot(
            accounts: state.accounts,
            session: session,
            usage: UsageSummary(accounts: state.accounts, events: state.history, now: now())
        )
    }

    private func resolveSession(_ state: inout SwitchState) throws -> SessionStatus {
        guard let stamp = secrets.modificationStamp(.supabaseCLI) else {
            if state.activeAccountID != nil || state.sessionStamp != nil {
                state.activeAccountID = nil
                state.sessionStamp = nil
                try store.save(state)
            }
            return .none
        }

        if stamp == state.sessionStamp {
            if let id = state.activeAccountID, state.accounts.contains(where: { $0.id == id }) {
                return .account(id)
            }
            return .unregistered
        }

        let organizations: [Organization]
        do {
            organizations = try cli.organizations(token: nil)
        } catch SwitchError.noCLISession {
            return .none
        } catch {
            // Nothing is written down: the next look asks again.
            // No se apunta nada: la próxima vez se vuelve a preguntar.
            return .unverified(error.localizedDescription)
        }

        let match = Self.account(in: state.accounts, owning: organizations.map(\.id))
        state.activeAccountID = match?.id
        state.sessionStamp = stamp
        try store.save(state)
        return match.map { .account($0.id) } ?? .unregistered
    }

    // MARK: Registering accounts

    /// Registers the account the CLI is logged in as. Reading the CLI's
    /// Keychain entry makes macOS ask the user once.
    /// Registra la cuenta con la que el CLI tiene sesión. Leer la entrada del
    /// CLI en el Llavero hace que macOS pregunte al usuario una vez.
    @discardableResult
    public func captureCurrent(name: String? = nil) throws -> Account {
        try locked {
            guard let stamp = secrets.modificationStamp(.supabaseCLI),
                  let token = try secrets.read(.supabaseCLI)
            else { throw SwitchError.noCLISession }
            guard AccessToken.isValid(token) else { throw SwitchError.invalidToken }

            var state = try store.load()
            let account = try register(token: token, name: name, queryWith: nil, in: &state)
            state.activeAccountID = account.id
            state.sessionStamp = stamp
            try store.save(state)
            return account
        }
    }

    /// Registers an account from a pasted access token, without touching the
    /// CLI's current login.
    /// Registra una cuenta a partir de un token pegado, sin tocar la sesión
    /// que el CLI tenga en ese momento.
    @discardableResult
    public func addAccount(token rawToken: String, name: String? = nil) throws -> Account {
        try locked {
            let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines)
            guard AccessToken.isValid(token) else { throw SwitchError.invalidToken }

            var state = try store.load()
            let account = try register(token: token, name: name, queryWith: token, in: &state)
            // The new account may be the one already logged in: forget the
            // stamp so the next look asks the CLI again.
            // La cuenta nueva puede ser la que ya tiene sesión: se olvida el
            // sello para que la próxima vez se le vuelva a preguntar al CLI.
            state.sessionStamp = nil
            try store.save(state)
            return account
        }
    }

    private func register(token: String, name: String?, queryWith queryToken: String?, in state: inout SwitchState) throws -> Account {
        let organizations = try cli.organizations(token: queryToken)
        guard !organizations.isEmpty else {
            throw SwitchError.cliFailed(tr(
                "that account belongs to no organization, so there is no way to tell it apart",
                "esa cuenta no pertenece a ninguna organización, no hay cómo distinguirla"
            ))
        }
        var projects = try cli.projects(token: queryToken)
        let ids = organizations.map(\.id).sorted()
        let wanted = name?.trimmingCharacters(in: .whitespaces)

        // Same organizations = same account: its token is replaced, not duplicated.
        // Mismas organizaciones = misma cuenta: se le cambia el token, no se duplica.
        if let index = state.accounts.firstIndex(where: { Set($0.organizationIDs) == Set(ids) }) {
            if let wanted, !wanted.isEmpty {
                state.accounts[index].name = Self.uniqueName(wanted, among: state.accounts, except: state.accounts[index].id)
            }
            state.accounts[index].organizationIDs = ids
            projects = Self.keepingAliases(of: state.accounts[index].projects, in: projects)
            state.accounts[index].projects = projects
            try secrets.write(token, to: .stored(state.accounts[index].id))
            return state.accounts[index]
        }

        let base = (wanted?.isEmpty == false ? wanted : nil) ?? organizations[0].name
        let account = Account(
            name: Self.uniqueName(base, among: state.accounts, except: nil),
            organizationIDs: ids,
            projects: projects,
            createdAt: wholeSecond()
        )
        try secrets.write(token, to: .stored(account.id))
        state.accounts.append(account)
        return account
    }

    // MARK: Switching

    /// Logs the CLI in as `id`.
    ///
    /// The token is tried first on its own, so a revoked one never replaces a
    /// login that works. After the login the CLI is asked who it is: a login
    /// that did not take must never be shown as done.
    ///
    /// Inicia sesión en el CLI con `id`.
    ///
    /// El token se prueba antes por separado, para que uno revocado no sustituya
    /// a una sesión que funciona. Tras el login se le pregunta al CLI quién es:
    /// un login que no entró nunca se da por hecho.
    @discardableResult
    public func activate(_ id: UUID) throws -> Snapshot {
        try locked {
            var state = try store.load()
            guard let account = state.accounts.first(where: { $0.id == id }) else { throw SwitchError.unknownAccount }
            guard let token = try secrets.read(.stored(id)) else { throw SwitchError.missingToken(account.name) }

            let owned = try cli.organizations(token: token).map(\.id)
            guard Set(owned) == Set(account.organizationIDs) else {
                throw SwitchError.cliFailed(tr(
                    "the stored token of “\(account.name)” no longer belongs to that account; add it again",
                    "el token guardado de «\(account.name)» ya no es de esa cuenta; vuelve a añadirla"
                ))
            }

            try cli.login(token: token)

            let seen = try cli.organizations(token: nil).map(\.id)
            guard Set(seen) == Set(account.organizationIDs) else {
                state.sessionStamp = nil
                try store.save(state)
                throw SwitchError.cliFailed(tr(
                    "after the login the CLI is not on “\(account.name)”",
                    "tras el login el CLI no quedó en «\(account.name)»"
                ))
            }

            state.activeAccountID = id
            state.sessionStamp = secrets.modificationStamp(.supabaseCLI)
            state.record(.switched, for: id, at: wholeSecond())
            try store.save(state)
            return makeSnapshot(state, session: .account(id))
        }
    }

    /// The stored token of one account, for running a single command as that
    /// account without changing who the CLI is logged in as. Counted as a run.
    /// El token guardado de una cuenta, para lanzar una sola orden con ella sin
    /// cambiar la sesión del CLI. Cuenta como una orden lanzada.
    public func tokenForRun(_ id: UUID) throws -> String {
        try locked {
            var state = try store.load()
            guard let account = state.accounts.first(where: { $0.id == id }) else { throw SwitchError.unknownAccount }
            guard let token = try secrets.read(.stored(id)) else { throw SwitchError.missingToken(account.name) }
            state.record(.ran, for: id, at: wholeSecond())
            try store.save(state)
            return token
        }
    }

    // MARK: Editing

    public func rename(_ id: UUID, to name: String) throws {
        try locked {
            var state = try store.load()
            guard let index = state.accounts.firstIndex(where: { $0.id == id }) else { throw SwitchError.unknownAccount }
            let trimmed = name.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return }
            state.accounts[index].name = Self.uniqueName(trimmed, among: state.accounts, except: id)
            try store.save(state)
        }
    }

    /// Gives a project a local name; an empty one goes back to Supabase's.
    /// Da a un proyecto un nombre local; uno vacío vuelve al de Supabase.
    public func renameProject(_ ref: String, in accountID: UUID, to alias: String) throws {
        try locked {
            var state = try store.load()
            guard let index = state.accounts.firstIndex(where: { $0.id == accountID }) else { throw SwitchError.unknownAccount }
            guard let project = state.accounts[index].projects.firstIndex(where: { $0.ref == ref }) else {
                throw SwitchError.unknownProject(ref)
            }
            let trimmed = alias.trimmingCharacters(in: .whitespaces)
            let original = state.accounts[index].projects[project].name
            state.accounts[index].projects[project].alias = trimmed.isEmpty || trimmed == original ? nil : trimmed
            try store.save(state)
        }
    }

    /// Forgets the account and deletes its token. The CLI stays logged in as
    /// whoever it was: this app never logs anyone out.
    /// Olvida la cuenta y borra su token. El CLI sigue con la sesión que tuviera:
    /// esta app nunca cierra la sesión de nadie.
    public func remove(_ id: UUID) throws {
        try locked {
            var state = try store.load()
            guard state.accounts.contains(where: { $0.id == id }) else { throw SwitchError.unknownAccount }
            try secrets.delete(.stored(id))
            state.accounts.removeAll { $0.id == id }
            state.history.removeAll { $0.accountID == id }
            if state.activeAccountID == id { state.activeAccountID = nil }
            try store.save(state)
        }
    }

    /// Re-reads the projects of one account with its stored token.
    /// Vuelve a leer los proyectos de una cuenta con su token guardado.
    @discardableResult
    public func refreshProjects(_ id: UUID) throws -> Account {
        try locked {
            var state = try store.load()
            guard let index = state.accounts.firstIndex(where: { $0.id == id }) else { throw SwitchError.unknownAccount }
            guard let token = try secrets.read(.stored(id)) else {
                throw SwitchError.missingToken(state.accounts[index].name)
            }
            state.accounts[index].projects = Self.keepingAliases(
                of: state.accounts[index].projects,
                in: try cli.projects(token: token)
            )
            try store.save(state)
            return state.accounts[index]
        }
    }

    // MARK: Helpers

    /// Finds an account by what a person would type: its name, the start of
    /// its name, or the ref, name or alias of one of its projects.
    /// Encuentra una cuenta por lo que escribiría una persona: su nombre, el
    /// principio del nombre, o el ref, el nombre o el alias de uno de sus proyectos.
    public static func resolve(_ query: String, in accounts: [Account]) throws -> Account {
        let wanted = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !wanted.isEmpty else { throw SwitchError.noMatch(query) }

        let attempts: [(Account) -> Bool] = [
            { $0.name.lowercased() == wanted },
            { $0.projects.contains { $0.ref.lowercased() == wanted } },
            { $0.projects.contains { $0.alias?.lowercased() == wanted } },
            { $0.projects.contains { $0.name.lowercased() == wanted } },
            { $0.name.lowercased().hasPrefix(wanted) },
        ]
        for matches in attempts {
            let found = accounts.filter(matches)
            if found.count == 1 { return found[0] }
            if found.count > 1 { throw SwitchError.ambiguous(query, found.map(\.name)) }
        }
        throw SwitchError.noMatch(query)
    }

    /// Finds one project, across every account, by its ref, alias or name.
    /// Encuentra un proyecto, en cualquier cuenta, por su ref, alias o nombre.
    public static func resolveProject(_ query: String, in accounts: [Account]) throws -> (account: Account, project: Project) {
        let wanted = query.trimmingCharacters(in: .whitespaces).lowercased()
        let pairs = accounts.flatMap { account in account.projects.map { (account: account, project: $0) } }
        let attempts: [(Project) -> Bool] = [
            { $0.ref.lowercased() == wanted },
            { $0.alias?.lowercased() == wanted },
            { $0.name.lowercased() == wanted },
        ]
        for matches in attempts where !wanted.isEmpty {
            let found = pairs.filter { matches($0.project) }
            if found.count == 1 { return found[0] }
            if found.count > 1 { throw SwitchError.ambiguous(query, found.map { "\($0.account.name)/\($0.project.ref)" }) }
        }
        throw SwitchError.unknownProject(query)
    }

    /// A fresh project list from Supabase, with the aliases the user gave
    /// before, matched by ref.
    /// La lista recién leída de Supabase, con los alias que el usuario ya había
    /// puesto, emparejados por ref.
    static func keepingAliases(of old: [Project], in fresh: [Project]) -> [Project] {
        let aliases = Dictionary(old.compactMap { project in project.alias.map { (project.ref, $0) } }, uniquingKeysWith: { a, _ in a })
        return fresh.map { project in
            var copy = project
            copy.alias = aliases[project.ref]
            return copy
        }
    }

    static func account(in accounts: [Account], owning organizationIDs: [String]) -> Account? {
        guard !organizationIDs.isEmpty else { return nil }
        return accounts.first { Set($0.organizationIDs) == Set(organizationIDs) }
    }

    static func uniqueName(_ name: String, among accounts: [Account], except id: UUID?) -> String {
        let taken = Set(accounts.filter { $0.id != id }.map { $0.name.lowercased() })
        guard taken.contains(name.lowercased()) else { return name }
        var suffix = 2
        while taken.contains("\(name) \(suffix)".lowercased()) { suffix += 1 }
        return "\(name) \(suffix)"
    }

    private func locked<T>(_ body: () throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

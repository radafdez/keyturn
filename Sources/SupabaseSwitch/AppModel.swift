import AppKit
import ServiceManagement
import SwiftUI
import SwitchCore
@preconcurrency import UserNotifications

/// What the menu and the settings window show, and the only place that talks
/// to `SwitchService`.
/// Lo que enseñan el menú y la ventana de ajustes, y el único sitio que habla
/// con `SwitchService`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var session: SessionStatus = .none
    @Published private(set) var usage = UsageSummary(accounts: [], events: [], now: Date())
    @Published private(set) var agentsCanSwitch = true
    /// What is being done right now, in the user's words. Nil when idle.
    /// Lo que se está haciendo ahora, con palabras del usuario. Nil en reposo.
    @Published private(set) var activity: String?
    @Published var problem: String?
    @Published private(set) var launchesAtLogin = false
    @Published private(set) var language: LanguageChoice
    @Published private(set) var notifiesAgentSwitches: Bool
    @Published private(set) var agents: [String: AgentStatus] = [:]

    enum LanguageChoice: String, CaseIterable, Identifiable {
        case system, english, spanish
        var id: String { rawValue }

        var resolved: AppLanguage {
            switch self {
            case .system: return .system
            case .english: return .english
            case .spanish: return .spanish
            }
        }

        var title: String {
            switch self {
            case .system: return tr("Same as the system", "Como el sistema")
            case .english: return "English"
            case .spanish: return "Español"
            }
        }
    }

    enum AgentStatus: Equatable {
        case checking
        /// The tool is not on this Mac. / La herramienta no está en este Mac.
        case missing
        case disconnected(executable: String)
        case connected(executable: String)
        case working(executable: String)
        case failed(executable: String?, String)

        var executable: String? {
            switch self {
            case .checking, .missing: return nil
            case .disconnected(let path), .connected(let path), .working(let path): return path
            case .failed(let path, _): return path
            }
        }
    }

    private enum Key {
        static let language = "language"
        static let notifies = "notifiesAgentSwitches"
    }

    private var service: SwitchService?
    private var queue: Task<Void, Never>?
    private var timer: Timer?
    private var watcher: DispatchSourceFileSystemObject?
    private var pendingReload: Task<Void, Never>?
    /// The newest event already seen, so only what is new gets announced.
    /// El evento más nuevo ya visto, para anunciar solo lo nuevo.
    private var newestSeen: Date?

    init() {
        let defaults = UserDefaults.standard
        language = defaults.string(forKey: Key.language).flatMap(LanguageChoice.init) ?? .system
        notifiesAgentSwitches = defaults.object(forKey: Key.notifies) as? Bool ?? true
        AppLanguage.current = language.resolved
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        if Demo.isOn { service = Demo.service() }
        refresh()
        if !Demo.isOn { watchTheStateFile() }
        // A login made in a terminal changes the session behind the app's back.
        // Looking again is cheap: it reads one date from the Keychain, and only
        // asks the CLI when that date moved.
        // Un login hecho en una terminal cambia la sesión a espaldas de la app.
        // Volver a mirar es barato: lee una fecha del Llavero, y solo pregunta
        // al CLI cuando esa fecha se movió.
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var activeAccountID: UUID? {
        guard case .account(let id) = session else { return nil }
        return id
    }

    var menuBarTitle: String {
        switch session {
        case .account(let id):
            let name = accounts.first { $0.id == id }?.name ?? "?"
            return name.count > 18 ? String(name.prefix(17)) + "…" : name
        case .none:
            return tr("no login", "sin sesión")
        case .unregistered:
            return tr("not registered", "sin registrar")
        case .unverified:
            return "?"
        }
    }

    func accountName(_ id: UUID) -> String {
        accounts.first { $0.id == id }?.name ?? tr("a removed account", "una cuenta quitada")
    }

    /// The `sbswitch` inside this app, which is what the agents run.
    /// El `sbswitch` de dentro de esta app, que es lo que ejecutan los agentes.
    var sbswitchPath: String {
        // The demo shows the usual place, not the folder it was built in.
        // La demo enseña el sitio habitual, no la carpeta donde se compiló.
        if Demo.isOn { return "/Applications/Supabase Switch.app/Contents/MacOS/sbswitch" }
        let besideTheApp = Bundle.main.executableURL?.deletingLastPathComponent().appendingPathComponent("sbswitch")
        return besideTheApp?.path ?? "/Applications/Supabase Switch.app/Contents/MacOS/sbswitch"
    }

    var stateFileURL: URL { FileStateStore.standard().url }

    // MARK: What the user can do

    func refresh() {
        perform(nil) { _ in }
    }

    /// Waits for every request already queued. / Espera a todas las peticiones ya en cola.
    func settle() async {
        await queue?.value
    }

    func checkAgain() {
        perform(tr("Asking the CLI…", "Preguntando al CLI…"), askingTheCLIAgain: true) { _ in }
    }

    func activate(_ id: UUID) {
        let name = accounts.first { $0.id == id }?.name ?? ""
        perform(tr("Switching to \(name)…", "Cambiando a \(name)…")) { try $0.activate(id, origin: .menu) }
    }

    func captureCurrent() {
        perform(tr("Waiting for you in the macOS dialog…", "Esperando tu permiso en el aviso de macOS…")) { try $0.captureCurrent() }
    }

    func add(token: String, name: String, then done: @escaping () -> Void) {
        let name = name.trimmingCharacters(in: .whitespaces)
        perform(tr("Checking the token…", "Comprobando el token…"), then: done) {
            try $0.addAccount(token: token, name: name.isEmpty ? nil : name)
        }
    }

    func rename(_ id: UUID, to name: String) {
        perform(tr("Saving…", "Guardando…")) { try $0.rename(id, to: name) }
    }

    func remove(_ id: UUID) {
        perform(tr("Removing…", "Quitando…")) { try $0.remove(id) }
    }

    func refreshProjects(_ id: UUID) {
        perform(tr("Reading the projects…", "Leyendo los proyectos…")) { try $0.refreshProjects(id) }
    }

    func renameProject(_ ref: String, in accountID: UUID, to alias: String) {
        perform(tr("Saving…", "Guardando…")) { try $0.renameProject(ref, in: accountID, to: alias) }
    }

    func setAgentsCanSwitch(_ allowed: Bool) {
        perform(tr("Saving…", "Guardando…")) { try $0.setAgentsCanSwitch(allowed) }
    }

    func setNotifiesAgentSwitches(_ wanted: Bool) {
        notifiesAgentSwitches = wanted
        UserDefaults.standard.set(wanted, forKey: Key.notifies)
        if wanted { askToNotify() }
    }

    func setLanguage(_ choice: LanguageChoice) {
        language = choice
        UserDefaults.standard.set(choice.rawValue, forKey: Key.language)
        AppLanguage.current = choice.resolved
        // Everything on screen reads `tr` when drawn: drawing again is enough.
        // Todo lo que hay en pantalla lee `tr` al dibujarse: basta con redibujar.
        objectWillChange.send()
    }

    func setLaunchAtLogin(_ wanted: Bool) {
        do {
            if wanted {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            problem = tr("Could not change opening at login: \(error.localizedDescription)",
                         "No pude cambiar el arranque al iniciar sesión: \(error.localizedDescription)")
        }
        launchesAtLogin = SMAppService.mainApp.status == .enabled
    }

    func showStateFile() {
        let url = stateFileURL
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            NSWorkspace.shared.open(url.deletingLastPathComponent())
        }
    }

    // MARK: Agents

    /// Looks for Claude Code and Codex, and whether they already have the server.
    /// Busca Claude Code y Codex, y si ya tienen el servidor.
    func checkAgents() {
        if Demo.isOn {
            // Made-up answers: the demo never runs the real tools.
            // Respuestas inventadas: la demo nunca ejecuta las herramientas reales.
            agents[AgentClient.claudeCode.id] = agents[AgentClient.claudeCode.id] ?? .connected(executable: "/usr/local/bin/claude")
            agents[AgentClient.codex.id] = agents[AgentClient.codex.id] ?? .disconnected(executable: "/usr/local/bin/codex")
            return
        }
        for client in AgentClient.all where agents[client.id] == nil || agents[client.id] == .missing {
            agents[client.id] = .checking
        }
        for client in AgentClient.all {
            Task {
                let status = await Task.detached(priority: .utility) { () -> AgentStatus in
                    guard let executable = client.locate() else { return .missing }
                    return client.isInstalled(executable: executable)
                        ? .connected(executable: executable)
                        : .disconnected(executable: executable)
                }.value
                agents[client.id] = status
            }
        }
    }

    func connect(_ client: AgentClient) {
        change(client) { [sbswitch = sbswitchPath] in try client.install(executable: $0, sbswitch: sbswitch) }
    }

    func disconnect(_ client: AgentClient) {
        change(client) { try client.remove(executable: $0) }
    }

    private func change(_ client: AgentClient, _ work: @escaping @Sendable (String) throws -> Void) {
        guard let executable = agents[client.id]?.executable else { return }
        if Demo.isOn {
            let connected = agents[client.id] == .connected(executable: executable)
            agents[client.id] = connected ? .disconnected(executable: executable) : .connected(executable: executable)
            return
        }
        agents[client.id] = .working(executable: executable)
        Task {
            let status = await Task.detached(priority: .userInitiated) { () -> AgentStatus in
                do {
                    try work(executable)
                } catch {
                    return .failed(executable: executable, (error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
                }
                return client.isInstalled(executable: executable)
                    ? .connected(executable: executable)
                    : .disconnected(executable: executable)
            }.value
            agents[client.id] = status
        }
    }

    // MARK: Plumbing

    /// Runs `work` off the main thread and then reads the state again. Requests
    /// wait their turn, so what the menu shows is always the latest answer.
    /// A nil `label` is a silent look that never hides a message on screen.
    ///
    /// Lanza `work` fuera del hilo principal y vuelve a leer el estado. Las
    /// peticiones esperan su turno, así que el menú enseña siempre la última
    /// respuesta. Con `label` nil es un vistazo silencioso, que nunca tapa un
    /// mensaje que esté en pantalla.
    private func perform(
        _ label: String?,
        askingTheCLIAgain: Bool = false,
        then done: (() -> Void)? = nil,
        _ work: @escaping @Sendable (SwitchService) throws -> Void
    ) {
        if label != nil {
            guard activity == nil else { return }
            activity = label
            problem = nil
        }
        let previous = queue
        queue = Task { [weak self] in
            await previous?.value
            guard let self else { return }
            do {
                let service = try self.loadService()
                let snapshot = try await Task.detached(priority: .userInitiated) {
                    try work(service)
                    return try service.snapshot(askingTheCLIAgain: askingTheCLIAgain)
                }.value
                self.apply(snapshot)
                if label != nil { done?() }
            } catch {
                if label != nil || self.problem == nil {
                    self.problem = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                }
                // The state on disk may have moved even though the action failed.
                // El estado en disco puede haber cambiado aunque la acción fallara.
                if label != nil, let service = self.service,
                   let snapshot = try? await Task.detached(operation: { try service.snapshot() }).value {
                    self.apply(snapshot)
                }
            }
            if label != nil { self.activity = nil }
        }
    }

    private func apply(_ snapshot: Snapshot) {
        accounts = snapshot.accounts
        session = snapshot.session
        usage = snapshot.usage
        agentsCanSwitch = snapshot.agentsCanSwitch
        announceAgentSwitches(in: snapshot.usage.recent)
    }

    private func loadService() throws -> SwitchService {
        if let service { return service }
        let created = try SwitchService.live()
        service = created
        return created
    }

    /// `sbswitch` writes the same file from a terminal or an agent. Watching
    /// its folder (the file is replaced on every save, so the file itself
    /// cannot be watched) puts those switches on screen at once.
    ///
    /// `sbswitch` escribe el mismo fichero desde una terminal o un agente.
    /// Vigilar su carpeta (el fichero se sustituye en cada guardado, así que no
    /// se puede vigilar él mismo) pone esos cambios en pantalla al momento.
    private func watchTheStateFile() {
        let folder = stateFileURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: [.write, .rename, .delete], queue: .main)
        source.setEventHandler { [weak self] in
            Task { @MainActor in self?.stateChangedOnDisk() }
        }
        source.setCancelHandler { close(descriptor) }
        source.resume()
        watcher = source
    }

    /// One save is several events; wait for the last one.
    /// Un guardado son varios eventos; se espera al último.
    private func stateChangedOnDisk() {
        pendingReload?.cancel()
        pendingReload = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 300_000_000)
            guard !Task.isCancelled else { return }
            self?.refresh()
        }
    }

    // MARK: Notifications

    private func announceAgentSwitches(in recent: [UsageEvent]) {
        let newest = recent.first?.date
        defer { if let newest, newest > (newestSeen ?? .distantPast) { newestSeen = newest } }
        // The first look only sets the mark: old switches are not news.
        // La primera mirada solo pone la marca: los cambios viejos no son noticia.
        guard let seen = newestSeen else { return }
        guard notifiesAgentSwitches else { return }
        let fresh = recent.filter { $0.date > seen && $0.source == .agent && $0.kind == .switched }
        for event in fresh.reversed() {
            notify(
                title: tr("\(clientTitle(event.client)) switched the Supabase CLI", "\(clientTitle(event.client)) cambió el CLI de Supabase"),
                body: tr("Now on “\(accountName(event.accountID))”.", "Ahora en «\(accountName(event.accountID))».")
            )
        }
    }

    private func askToNotify() {
        guard Bundle.main.bundleIdentifier != nil else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert]) { _, _ in }
    }

    private func notify(title: String, body: String) {
        // Outside an .app bundle (`swift run`) the notification center crashes.
        // Fuera de un bundle .app (`swift run`) el centro de avisos se cae.
        guard Bundle.main.bundleIdentifier != nil, !Demo.isOn else { return }
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    if granted { center.add(request) }
                }
            case .denied:
                break
            default:
                center.add(request)
            }
        }
    }
}

/// "claude-code" → "Claude Code"; names nobody registered stay as they came.
/// «claude-code» → «Claude Code»; los nombres que nadie registró se quedan como llegan.
func clientTitle(_ client: String?) -> String {
    guard let client, !client.isEmpty else { return tr("An agent", "Un agente") }
    if let known = AgentClient.all.first(where: { $0.id == client }) { return known.title }
    let known = ["claude-ai": "Claude Desktop", "claude": "Claude", "codex-mcp-client": "Codex", "cursor": "Cursor",
                 "cursor-vscode": "Cursor", "windsurf": "Windsurf", "vscode": "VS Code", "zed": "Zed"]
    return known[client.lowercased()] ?? client
}

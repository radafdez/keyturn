import AppKit
import ServiceManagement
import SwiftUI
import SwitchCore

/// What the menu shows, and the only place that talks to `SwitchService`.
/// Lo que enseña el menú, y el único sitio que habla con `SwitchService`.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var accounts: [Account] = []
    @Published private(set) var session: SessionStatus = .none
    @Published private(set) var usage = UsageSummary(accounts: [], events: [], now: Date())
    /// What is being done right now, in the user's words. Nil when idle.
    /// Lo que se está haciendo ahora, con palabras del usuario. Nil en reposo.
    @Published private(set) var activity: String?
    @Published var problem: String?
    @Published private(set) var launchesAtLogin = false

    private var service: SwitchService?
    private var queue: Task<Void, Never>?
    private var timer: Timer?

    init() {
        launchesAtLogin = SMAppService.mainApp.status == .enabled
        refresh()
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

    // MARK: What the user can do

    func refresh() {
        perform(nil) { _ in }
    }

    func checkAgain() {
        perform(tr("Asking the CLI…", "Preguntando al CLI…"), askingTheCLIAgain: true) { _ in }
    }

    func activate(_ id: UUID) {
        let name = accounts.first { $0.id == id }?.name ?? ""
        perform(tr("Switching to \(name)…", "Cambiando a \(name)…")) { try $0.activate(id) }
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
    }

    private func loadService() throws -> SwitchService {
        if let service { return service }
        let created = try SwitchService.live()
        service = created
        return created
    }
}

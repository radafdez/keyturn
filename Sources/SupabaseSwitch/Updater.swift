import AppKit
import Sparkle
import SwitchCore

/// Updates through Sparkle. The feed and every zip are signed with the
/// project's EdDSA key, and the app refuses anything that is not: that, and
/// not an Apple notarization, is what proves an update comes from us.
///
/// Sparkle asks once, on the second launch, whether to check on its own. Until
/// then, and if the answer is no, it only checks when you press the button.
/// A copy installed with Homebrew updates the same way: its cask says
/// `auto_updates`, so `brew upgrade` leaves it alone instead of installing a
/// quarantined copy that Gatekeeper would block again.
///
/// Actualizaciones a través de Sparkle. El feed y cada zip van firmados con la
/// clave EdDSA del proyecto, y la app rechaza lo que no lo esté: eso, y no una
/// notarización de Apple, es lo que prueba que una actualización es nuestra.
///
/// Sparkle pregunta una vez, en el segundo arranque, si comprobar por su cuenta.
/// Hasta entonces, y si la respuesta es no, solo comprueba al pulsar el botón.
/// Una copia instalada con Homebrew se actualiza igual: su cask dice
/// `auto_updates`, así que `brew upgrade` no la toca en vez de instalar una
/// copia en cuarentena que Gatekeeper volvería a bloquear.
@MainActor
final class Updater: NSObject, ObservableObject {
    static let shared = Updater()

    enum Channel {
        /// Sparkle, with the feed of the GitHub releases. / Sparkle, con el feed de las versiones de GitHub.
        case sparkle
        /// A build from source, or one without a feed: the releases page. / Una
        /// compilación desde el código, o sin feed: la página de versiones.
        case manual
    }

    let channel: Channel
    @Published private(set) var canCheck = false
    @Published private(set) var checksAutomatically = false
    /// A version Sparkle found while the app was in the background, waiting
    /// for a click in the menu. / Una versión que Sparkle encontró con la app en
    /// segundo plano, esperando un clic en el menú.
    @Published private(set) var waiting: String?

    private var controller: SPUStandardUpdaterController?
    private var observations: [NSKeyValueObservation] = []

    private override init() {
        let info = Bundle.main.infoDictionary ?? [:]
        let snapshots = ProcessInfo.processInfo.environment["SUPABASE_SWITCH_SNAPSHOTS"] != nil
        let hasFeed = info["SUFeedURL"] != nil && info["SUPublicEDKey"] != nil
        if snapshots || (hasFeed && Bundle.main.bundleURL.pathExtension == "app") {
            channel = .sparkle
        } else {
            channel = .manual
        }
        super.init()

        // Screenshots show the Sparkle pane without starting Sparkle.
        // Las capturas enseñan el panel de Sparkle sin arrancar Sparkle.
        guard channel == .sparkle, !snapshots else {
            canCheck = snapshots
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
        self.controller = controller
        let updater = controller.updater
        observations = [
            updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let value = updater.canCheckForUpdates
                Task { @MainActor in self?.canCheck = value }
            },
            updater.observe(\.automaticallyChecksForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let value = updater.automaticallyChecksForUpdates
                Task { @MainActor in self?.checksAutomatically = value }
            },
        ]
    }

    func checkForUpdates() {
        // A menu bar app is never in front on its own; Sparkle's window would
        // open behind the others. / Una app de barra de menús nunca está delante
        // por sí sola; la ventana de Sparkle se abriría detrás de las demás.
        NSApp.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }

    func setChecksAutomatically(_ on: Bool) {
        controller?.updater.automaticallyChecksForUpdates = on
    }
}

// Gentle reminders: a background check that finds a version does not throw a
// window in front of whatever you are doing. It waits in the menu instead.
// Avisos discretos: una comprobación en segundo plano que encuentra una versión
// no te planta una ventana delante de lo que estés haciendo. Espera en el menú.
extension Updater: SPUStandardUserDriverDelegate {
    nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

    nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        let version = update.displayVersionString
        Task { @MainActor in self.waiting = version }
    }

    nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        Task { @MainActor in self.waiting = nil }
    }

    nonisolated func standardUserDriverWillFinishUpdateSession() {
        Task { @MainActor in self.waiting = nil }
    }
}

import Foundation
import SwitchCore

/// The CLI scanner, apart from the accounts: which command-line tools are
/// running on this Mac and for how long. It never touches them.
/// El escáner de CLIs, aparte de las cuentas: qué herramientas de línea de
/// órdenes corren en este Mac y durante cuánto tiempo. Nunca las toca.
@MainActor
final class CLIWatch: ObservableObject {
    static let shared = CLIWatch()

    @Published private(set) var isOn: Bool
    @Published private(set) var summary = CLIActivitySummary.empty
    /// Ticks every second while something runs, so the times on screen move.
    /// Avanza cada segundo mientras algo corre, para que los tiempos en pantalla se muevan.
    @Published private(set) var now = Date()

    /// Short enough to catch a `supabase db push`; one pass takes milliseconds.
    /// Lo bastante corto para pillar un `supabase db push`; una pasada tarda milisegundos.
    static let interval: TimeInterval = 5

    private static let key = "watchesCLIs"
    private let monitor: CLIMonitor
    private var timer: Timer?
    private var clock: Timer?
    private var scanning = false

    private init() {
        isOn = Demo.isOn || (UserDefaults.standard.object(forKey: Self.key) as? Bool ?? true)
        monitor = Demo.isOn ? Demo.cliMonitor() : CLIMonitor.live()
        summary = monitor.summary()
        // The demo stays frozen in time, so its pictures always look the same.
        // La demo se queda quieta en el tiempo, para que sus fotos salgan iguales.
        now = summary.now
        if isOn { start() }
        if !Demo.isOn {
            clock = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.isOn, !self.summary.running.isEmpty else { return }
                    self.now = Date()
                }
            }
            clock?.tolerance = 0.2
        }
    }

    var extraCommands: [String] { monitor.extraCommands }

    func setOn(_ wanted: Bool) {
        guard wanted != isOn else { return }
        isOn = wanted
        UserDefaults.standard.set(wanted, forKey: Self.key)
        if wanted {
            start()
        } else {
            timer?.invalidate()
            timer = nil
            let monitor = monitor
            Task {
                summary = await Task.detached(priority: .utility) { monitor.stop() }.value
            }
        }
    }

    /// "foo, bar baz" → ["foo", "bar", "baz"].
    func setExtraCommands(_ text: String) {
        let commands = text.split(whereSeparator: { $0 == "," || $0.isWhitespace }).map(String.init)
        monitor.setExtraCommands(commands)
        scan()
    }

    func flush() {
        if isOn { monitor.flush() }
    }

    private func start() {
        scan()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.scan() }
        }
        timer?.tolerance = 1
    }

    func scan() {
        guard isOn, !scanning, !Demo.isOn else { return }
        scanning = true
        let monitor = monitor
        Task {
            summary = await Task.detached(priority: .utility) { monitor.scan() }.value
            now = summary.now
            scanning = false
        }
    }
}

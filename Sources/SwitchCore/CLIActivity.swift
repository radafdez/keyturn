import Foundation

// MARK: - Sessions

/// One run of a watched tool, from the moment it started to the last time it
/// was seen. Only the tool, the app it ran in and the times are kept — never
/// its arguments, its folder or its output.
///
/// Una ejecución de una herramienta vigilada, desde que arrancó hasta la última
/// vez que se vio. Solo se guardan la herramienta, la app donde corrió y las
/// horas; nunca sus argumentos, su carpeta ni su salida.
public struct CLISession: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID
    public var tool: String
    public var pid: Int32
    public var started: Date
    public var lastSeen: Date
    /// Nil while it is still running. / Nil mientras sigue corriendo.
    public var ended: Date?
    public var host: String?
    public var via: String?

    public init(id: UUID = UUID(), tool: String, pid: Int32, started: Date, lastSeen: Date,
                ended: Date? = nil, host: String? = nil, via: String? = nil) {
        self.id = id
        self.tool = tool
        self.pid = pid
        self.started = started
        self.lastSeen = lastSeen
        self.ended = ended
        self.host = host
        self.via = via
    }

    public var isRunning: Bool { ended == nil }

    public func end(at now: Date) -> Date { ended ?? max(now, lastSeen) }

    public func duration(now: Date) -> TimeInterval { max(0, end(at: now).timeIntervalSince(started)) }
}

/// What is kept on disk, next to the accounts but in a file of its own.
/// Lo que se guarda en disco, junto a las cuentas pero en un fichero propio.
public struct CLIActivity: Codable, Equatable, Sendable {
    public var sessions: [CLISession]
    /// Commands the user added to the catalog. / Órdenes que el usuario añadió al catálogo.
    public var extraCommands: [String]

    public init(sessions: [CLISession] = [], extraCommands: [String] = []) {
        self.sessions = sessions
        self.extraCommands = extraCommands
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessions = try container.decodeIfPresent([CLISession].self, forKey: .sessions) ?? []
        extraCommands = try container.decodeIfPresent([String].self, forKey: .extraCommands) ?? []
    }

    /// Sessions that ended longer ago than this are dropped.
    /// Las sesiones que acabaron hace más de esto se descartan.
    public static let keptFor: TimeInterval = 90 * 24 * 3600
    public static let limit = 5000
}

public protocol CLIActivityStore: Sendable {
    func load() throws -> CLIActivity
    func save(_ activity: CLIActivity) throws
}

public struct FileCLIActivityStore: CLIActivityStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    /// In a folder of its own: the app watches the accounts' folder, and a save
    /// here every minute must not make it read the accounts again.
    /// En una carpeta propia: la app vigila la carpeta de las cuentas, y un
    /// guardado aquí cada minuto no debe hacerle releerlas.
    public static func standard() -> FileCLIActivityStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileCLIActivityStore(url: support.appendingPathComponent("Keyturn/CLIs/activity.json"))
    }

    public func load() throws -> CLIActivity {
        guard FileManager.default.fileExists(atPath: url.path) else { return CLIActivity() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(CLIActivity.self, from: Data(contentsOf: url))
    }

    public func save(_ activity: CLIActivity) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(activity).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

// MARK: - Following them over time

public enum CLITracker {
    /// Folds one scan into the sessions: new processes open a session, the ones
    /// still there move their `lastSeen`, and the ones gone end where they were
    /// last seen. Returns whether a session opened or closed.
    ///
    /// Incorpora un escaneo a las sesiones: los procesos nuevos abren sesión,
    /// los que siguen mueven su `lastSeen`, y los que ya no están acaban donde
    /// se vieron por última vez. Devuelve si se abrió o cerró alguna sesión.
    @discardableResult
    public static func apply(_ detections: [CLIDetection], to activity: inout CLIActivity, now: Date) -> Bool {
        // A process is its pid and its start: a pid can be reused later.
        // Un proceso es su pid y su inicio: un pid puede reutilizarse más tarde.
        struct Key: Hashable { var pid: Int32; var started: TimeInterval }
        func key(_ pid: Int32, _ started: Date) -> Key { Key(pid: pid, started: started.timeIntervalSince1970.rounded(.down)) }

        var current: [Key: CLIDetection] = [:]
        for detection in detections { current[key(detection.pid, detection.started)] = detection }

        var changed = false
        var open: Set<Key> = []
        for index in activity.sessions.indices where activity.sessions[index].isRunning {
            let session = activity.sessions[index]
            let id = key(session.pid, session.started)
            if current[id] != nil {
                activity.sessions[index].lastSeen = now
                open.insert(id)
            } else {
                activity.sessions[index].ended = session.lastSeen
                changed = true
            }
        }
        for (id, detection) in current where !open.contains(id) {
            activity.sessions.append(CLISession(tool: detection.tool, pid: detection.pid, started: detection.started,
                                                lastSeen: now, host: detection.host, via: detection.via))
            changed = true
        }
        if changed { prune(&activity, now: now) }
        return changed
    }

    /// Ends every open session now: the scanner was turned off.
    /// Cierra ahora todas las sesiones abiertas: se apagó el escáner.
    public static func endAll(_ activity: inout CLIActivity, now: Date) {
        for index in activity.sessions.indices where activity.sessions[index].isRunning {
            activity.sessions[index].ended = max(now, activity.sessions[index].lastSeen)
        }
    }

    static func prune(_ activity: inout CLIActivity, now: Date) {
        let oldest = now.addingTimeInterval(-CLIActivity.keptFor)
        activity.sessions.removeAll { ($0.ended ?? .distantFuture) < oldest }
        activity.sessions.sort { $0.started < $1.started }
        if activity.sessions.count > CLIActivity.limit {
            activity.sessions.removeFirst(activity.sessions.count - CLIActivity.limit)
        }
    }
}

// MARK: - What to show

/// One tool running now, however many copies. / Una herramienta que corre ahora, con cuantas copias tenga.
public struct RunningCLI: Equatable, Sendable, Identifiable {
    public var tool: String
    public var title: String
    public var copies: Int
    /// The oldest copy's start. / El inicio de la copia más antigua.
    public var since: Date
    public var hosts: [String]
    public var via: [String]
    public var id: String { tool }

    /// Groups what was found by tool, oldest first; `title` names a tool id.
    /// Agrupa lo encontrado por herramienta, la más antigua primero; `title` da nombre a un id.
    public static func group(_ found: [CLIDetection], title: (String) -> String, now: Date) -> [RunningCLI] {
        Dictionary(grouping: found, by: \.tool).map { tool, copies in
            RunningCLI(
                tool: tool,
                title: title(tool),
                copies: copies.count,
                since: copies.map(\.started).min() ?? now,
                hosts: Array(Set(copies.compactMap(\.host))).sorted(),
                via: Array(Set(copies.compactMap(\.via))).map(title).sorted()
            )
        }
        .sorted { $0.since != $1.since ? $0.since < $1.since : $0.title < $1.title }
    }
}

/// Time one tool was running in a window. Overlapping copies count once: two
/// Claude Code for an hour are an hour of Claude Code.
/// Tiempo que una herramienta estuvo corriendo en un periodo. Las copias que se
/// solapan cuentan una vez: dos Claude Code durante una hora son una hora.
public struct CLITotal: Equatable, Sendable, Identifiable {
    public var tool: String
    public var title: String
    public var active: TimeInterval
    public var sessions: Int
    public var lastSeen: Date
    public var id: String { tool }
}

public struct CLIActivitySummary: Equatable, Sendable {
    public var running: [RunningCLI]
    public var sessions: [CLISession]
    public var tools: [KnownCLI]
    public var now: Date

    public static let empty = CLIActivitySummary(activity: CLIActivity(), now: Date())

    public init(activity: CLIActivity, now: Date) {
        self.now = now
        sessions = activity.sessions
        tools = KnownCLI.watched(adding: activity.extraCommands)
        let titles = Dictionary(tools.map { ($0.id, $0.title) }, uniquingKeysWith: { first, _ in first })
        let open = activity.sessions.filter(\.isRunning).map {
            CLIDetection(tool: $0.tool, pid: $0.pid, started: $0.started, host: $0.host, via: $0.via)
        }
        running = RunningCLI.group(open, title: { titles[$0] ?? $0 }, now: now)
    }

    public func title(of tool: String) -> String {
        tools.first { $0.id == tool }?.title ?? tool
    }

    /// Time per tool since `start`, most first. / Tiempo por herramienta desde `start`, de más a menos.
    public func totals(since start: Date) -> [CLITotal] {
        let inWindow = sessions.filter { $0.end(at: now) > start }
        return Dictionary(grouping: inWindow, by: \.tool).map { tool, own in
            CLITotal(
                tool: tool,
                title: title(of: tool),
                active: Self.covered(by: own.map { (max($0.started, start), $0.end(at: now)) }),
                sessions: own.count,
                lastSeen: own.map { $0.end(at: now) }.max() ?? start
            )
        }
        .sorted { $0.active != $1.active ? $0.active > $1.active : $0.title < $1.title }
    }

    /// The latest sessions that already ended, newest first.
    /// Las últimas sesiones que ya acabaron, la más nueva primero.
    public func finished(limit: Int = 50) -> [CLISession] {
        Array(sessions.filter { !$0.isRunning }.sorted { $0.end(at: now) > $1.end(at: now) }.prefix(limit))
    }

    /// The length of the union of some intervals. / La longitud de la unión de unos intervalos.
    static func covered(by intervals: [(Date, Date)]) -> TimeInterval {
        var total: TimeInterval = 0
        var current: (Date, Date)?
        for (start, end) in intervals.filter({ $0.1 > $0.0 }).sorted(by: { $0.0 < $1.0 }) {
            if let open = current, start <= open.1 {
                current = (open.0, max(open.1, end))
            } else {
                if let open = current { total += open.1.timeIntervalSince(open.0) }
                current = (start, end)
            }
        }
        if let open = current { total += open.1.timeIntervalSince(open.0) }
        return total
    }
}

// MARK: - The scanner

/// Scans, folds the result into the sessions and keeps them on disk. Safe to
/// call from any thread; the app calls `scan` every few seconds.
///
/// Escanea, incorpora el resultado a las sesiones y las guarda en disco. Se
/// puede llamar desde cualquier hilo; la app llama a `scan` cada pocos segundos.
public final class CLIMonitor: @unchecked Sendable {
    private let source: ProcessSource
    private let store: CLIActivityStore
    private let ownPID: Int32
    private let lock = NSLock()
    private var activity: CLIActivity
    private var lastSave: Date?

    /// While something runs, its `lastSeen` is saved this often, so a crash or
    /// a restart loses at most this much.
    /// Mientras algo corre, su `lastSeen` se guarda con esta frecuencia, así que
    /// un cierre inesperado pierde como mucho esto.
    public static let saveEvery: TimeInterval = 60

    public init(source: ProcessSource, store: CLIActivityStore, ownPID: Int32 = getpid()) {
        self.source = source
        self.store = store
        self.ownPID = ownPID
        activity = (try? store.load()) ?? CLIActivity()
    }

    public static func live() -> CLIMonitor {
        CLIMonitor(source: LiveProcessSource(), store: FileCLIActivityStore.standard())
    }

    public var extraCommands: [String] {
        lock.lock(); defer { lock.unlock() }
        return activity.extraCommands
    }

    /// What is running right now, without touching the sessions.
    /// Lo que corre ahora mismo, sin tocar las sesiones.
    public func detect() -> [CLIDetection] {
        let tools = KnownCLI.watched(adding: extraCommands)
        return CLIDetector.detect(in: source.processes(), watching: tools, ignoring: ownPID)
    }

    @discardableResult
    public func scan(now: Date = Date()) -> CLIActivitySummary {
        let detections = detect()
        lock.lock(); defer { lock.unlock() }
        let changed = CLITracker.apply(detections, to: &activity, now: now)
        let due = activity.sessions.contains(where: \.isRunning)
            && now.timeIntervalSince(lastSave ?? .distantPast) >= Self.saveEvery
        if changed || due { persist(now: now) }
        return CLIActivitySummary(activity: activity, now: now)
    }

    /// Turned off: what was running ends now. / Apagado: lo que corría acaba ahora.
    @discardableResult
    public func stop(now: Date = Date()) -> CLIActivitySummary {
        lock.lock(); defer { lock.unlock() }
        CLITracker.endAll(&activity, now: now)
        persist(now: now)
        return CLIActivitySummary(activity: activity, now: now)
    }

    public func summary(now: Date = Date()) -> CLIActivitySummary {
        lock.lock(); defer { lock.unlock() }
        return CLIActivitySummary(activity: activity, now: now)
    }

    public func setExtraCommands(_ commands: [String]) {
        lock.lock(); defer { lock.unlock() }
        var unique: [String] = []
        for command in commands.map(KnownCLI.normalizedCommand) where !command.isEmpty && !unique.contains(command) {
            unique.append(command)
        }
        activity.extraCommands = unique
        persist(now: Date())
    }

    /// Writes what is in memory, e.g. when the app quits.
    /// Escribe lo que hay en memoria, por ejemplo al salir de la app.
    public func flush() {
        lock.lock(); defer { lock.unlock() }
        persist(now: Date())
    }

    private func persist(now: Date) {
        try? store.save(activity)
        lastSave = now
    }
}

// MARK: - Durations

/// "45 s", "12 min", "1 h 05 min", "3 d 4 h": the same in both languages.
/// «45 s», «12 min», «1 h 05 min», «3 d 4 h»: igual en los dos idiomas.
public func durationText(_ seconds: TimeInterval) -> String {
    let total = Int(max(0, seconds))
    if total < 60 { return "\(total) s" }
    let minutes = total / 60
    if minutes < 60 { return "\(minutes) min" }
    let hours = minutes / 60
    if hours < 24 { return "\(hours) h " + String(format: "%02d", minutes % 60) + " min" }
    return "\(hours / 24) d \(hours % 24) h"
}

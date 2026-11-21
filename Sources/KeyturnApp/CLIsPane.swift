import SwiftUI
import SwitchCore

/// Settings → Running CLIs: what runs now, how long each tool ran, the latest
/// sessions, and which commands are watched.
/// Ajustes → CLIs en marcha: lo que corre ahora, cuánto corrió cada
/// herramienta, las últimas sesiones y qué órdenes se vigilan.
struct CLIsPane: View {
    @ObservedObject var watch = CLIWatch.shared
    @ViewState private var period = Period.today
    @ViewState private var extra = ""
    @ViewState private var editing = false

    enum Period: String, CaseIterable, Identifiable {
        case today, week, month
        var id: String { rawValue }

        var title: String {
            switch self {
            case .today: return tr("Today", "Hoy")
            case .week: return tr("7 days", "7 días")
            case .month: return tr("30 days", "30 días")
            }
        }

        func start(_ now: Date) -> Date {
            switch self {
            case .today: return Calendar.current.startOfDay(for: now)
            case .week: return now.addingTimeInterval(-7 * 24 * 3600)
            case .month: return now.addingTimeInterval(-30 * 24 * 3600)
            }
        }
    }

    private var summary: CLIActivitySummary { watch.summary }

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { watch.isOn }, set: { watch.setOn($0) })) {
                    Text(tr("Watch the CLIs running on this Mac", "Vigilar los CLIs que corren en este Mac"))
                    Text(tr("Every \(Int(CLIWatch.interval)) seconds Keyturn looks at the names of the programs running. It only keeps which tool ran, in which app and for how long — never its arguments or its output, and nothing leaves this Mac.",
                            "Cada \(Int(CLIWatch.interval)) segundos Keyturn mira los nombres de los programas en marcha. Solo guarda qué herramienta corrió, en qué app y cuánto tiempo; nunca sus argumentos ni su salida, y nada sale de este Mac."))
                }
            }

            if watch.isOn {
                Section(tr("Running now", "En marcha ahora")) {
                    // Each section keys its rows apart: the same tool in two
                    // sections must not look like one row to the list.
                    // Cada sección identifica sus filas aparte: la misma
                    // herramienta en dos secciones no debe parecer una sola fila.
                    ForEach(summary.running, id: \.rowID) { RunningCLIRow(cli: $0) }
                    if summary.running.isEmpty {
                        Text(tr("None of the watched CLIs is running.", "No corre ninguno de los CLIs vigilados."))
                            .foregroundStyle(.secondary)
                    }
                }

                Section {
                    let totals = summary.totals(since: period.start(summary.now))
                    if totals.isEmpty {
                        Text(tr("Nothing recorded in this period.", "Nada registrado en este periodo."))
                            .foregroundStyle(.secondary)
                    } else {
                        let top = max(totals.map(\.active).max() ?? 0, 1)
                        ForEach(totals, id: \.rowID) { total in
                            DurationRow(title: total.title, seconds: total.active, top: top,
                                        detail: sessionsCount(total.sessions))
                        }
                    }
                } header: {
                    HStack {
                        Text(tr("Time running", "Tiempo en marcha"))
                        Spacer()
                        Picker("", selection: $period) {
                            ForEach(Period.allCases) { Text($0.title).tag($0) }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .fixedSize()
                    }
                } footer: {
                    Text(tr("Copies of a tool running at the same time count once. Commands that last less than \(Int(CLIWatch.interval)) seconds may not be seen.",
                            "Las copias de una herramienta que corren a la vez cuentan una vez. Las órdenes que duran menos de \(Int(CLIWatch.interval)) segundos pueden no verse."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                let finished = summary.finished(limit: 25)
                if !finished.isEmpty {
                    Section(tr("Latest sessions", "Últimas sesiones")) {
                        ForEach(finished) { session in
                            HStack(spacing: 10) {
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(summary.title(of: session.tool))
                                    if let place = place(host: session.host, via: session.via.map(summary.title(of:))) {
                                        Text(place).font(.caption).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                Text(durationText(session.duration(now: summary.now))).monospacedDigit()
                                Text(relativeTime(session.end(at: summary.now), now: summary.now))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .frame(minWidth: 90, alignment: .trailing)
                                    .help(session.started.formatted(.dateTime.locale(AppLanguage.current.locale)))
                            }
                        }
                    }
                }
            }

            Section {
                Text(KnownCLI.catalog.map(\.title).joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    TextField(tr("Also watch", "Vigilar también"), text: $extra, prompt: Text("deno, bun, mytool"))
                        .onSubmit(save)
                        .onChange(of: extra) { _ in editing = true }
                    Button(tr("Save", "Guardar"), action: save).disabled(!editing)
                }
            } header: {
                Text(tr("Watched", "Vigiladas"))
            } footer: {
                Text(tr("Command names, separated by commas or spaces, as you type them in a terminal.",
                        "Nombres de órdenes, separados por comas o espacios, tal como los escribes en una terminal."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            extra = watch.extraCommands.joined(separator: ", ")
            DispatchQueue.main.async { editing = false }
            watch.scan()
        }
    }

    private func save() {
        watch.setExtraCommands(extra)
        extra = watch.extraCommands.joined(separator: ", ")
        DispatchQueue.main.async { editing = false }
    }
}

/// One tool running now, with how long it has been running.
/// Una herramienta en marcha, con cuánto tiempo lleva.
struct RunningCLIRow: View {
    @ObservedObject var watch = CLIWatch.shared
    let cli: RunningCLI
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Circle().fill(Color.green).frame(width: 7, height: 7)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 4) {
                    Text(cli.title).lineLimit(1)
                        .help(tr("Running since \(cli.since.formatted(.dateTime.hour().minute().locale(AppLanguage.current.locale)))",
                                 "En marcha desde las \(cli.since.formatted(.dateTime.hour().minute().locale(AppLanguage.current.locale)))"))
                    if cli.copies > 1 {
                        Text("×\(cli.copies)").foregroundStyle(.secondary)
                    }
                }
                if let place = place(host: cli.hosts.joined(separator: ", ").nilIfEmpty, via: cli.via.joined(separator: ", ").nilIfEmpty) {
                    Text(place).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 8)
            Text(durationText(watch.now.timeIntervalSince(cli.since)))
                .monospacedDigit()
                .font(compact ? .caption : .body)
                .foregroundStyle(compact ? .secondary : .primary)
        }
    }
}

private struct DurationRow: View {
    let title: String
    let seconds: TimeInterval
    let top: TimeInterval
    var detail: String?

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).lineLimit(1)
                if let detail { Text(detail).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 8)
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(Color.accentColor).frame(width: max(160 * seconds / top, seconds > 0 ? 4 : 0))
            }
            .frame(width: 160, height: 6)
            Text(durationText(seconds)).monospacedDigit().frame(minWidth: 80, alignment: .trailing)
        }
    }
}

/// "in Terminal · launched by Claude Code". / «en Terminal · lanzado por Claude Code».
func place(host: String?, via: String?) -> String? {
    let parts = [host.map { tr("in \($0)", "en \($0)") }, via.map { tr("launched by \($0)", "lanzado por \($0)") }].compactMap { $0 }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
}

func sessionsCount(_ count: Int) -> String {
    count == 1 ? tr("1 session", "1 sesión") : tr("\(count) sessions", "\(count) sesiones")
}

private extension RunningCLI {
    var rowID: String { "running-" + tool }
}

private extension CLITotal {
    var rowID: String { "total-" + tool }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

import AppKit
import SwiftUI
import SwitchCore

struct MenuView: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater = Updater.shared
    @ObservedObject var clis = CLIWatch.shared
    @Environment(\.openWindow) private var openWindow

    enum Panel { case none, adding, stats }

    @ViewState private var expanded: UUID?
    @ViewState private var panel = Panel.none

    private var busy: Bool { model.activity != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if let problem = model.problem {
                Banner(text: problem, tint: .red) { model.problem = nil }
            }
            if let lost = model.lostLogin {
                Banner(
                    text: tr("The new login of “\(lost.name)” was replaced before it was captured. Log in with it again (“supabase login”) and press Capture.",
                             "La sesión nueva de «\(lost.name)» se sustituyó antes de capturarla. Vuelve a iniciarla («supabase login») y pulsa Capturar."),
                    tint: .red
                ) { model.forgetLostLogin() }
            }
            sessionNotice
            if let version = updater.waiting {
                Button { updater.checkForUpdates() } label: {
                    Label(tr("Version \(version) is ready to install", "La versión \(version) está lista para instalar"),
                          systemImage: "arrow.down.circle.fill")
                        .font(.callout)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }
            Divider()

            if model.accounts.isEmpty {
                Text(tr("No accounts yet. Capture the login the CLI has now, or add one with its token.",
                        "Aún no hay cuentas. Captura la sesión que el CLI tiene ahora, o añade una con su token."))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
            } else {
                VStack(spacing: 0) {
                    ForEach(model.accounts) { account in
                        AccountRow(
                            model: model,
                            account: account,
                            usage: model.usage.usage(of: account.id),
                            active: model.activeAccountID == account.id,
                            expanded: expanded == account.id,
                            setExpanded: { expanded = $0 ? account.id : (expanded == account.id ? nil : expanded) }
                        )
                    }
                }
                .padding(.vertical, 4)
            }

            Divider()
            switch panel {
            case .adding:
                AddAccountForm(model: model) { panel = .none }
            case .stats:
                StatsPanel(usage: model.usage) { panel = .none }
            case .none:
                VStack(alignment: .leading, spacing: 2) {
                    MenuButton(title: tr("Add account with its token…", "Añadir cuenta con su token…"), icon: "plus") {
                        panel = .adding
                    }
                    MenuButton(title: tr("Capture the CLI's current login", "Capturar la sesión actual del CLI"), icon: "arrow.down.circle") {
                        model.captureCurrent()
                    }
                    if !model.accounts.isEmpty {
                        MenuButton(title: tr("Statistics", "Estadísticas"), icon: "chart.bar") { panel = .stats }
                    }
                }
                .padding(.vertical, 4)
            }

            if clis.isOn {
                Divider()
                runningCLIs
            }

            Divider()
            footer
        }
        .frame(width: 340)
        .disabled(busy)
        .onAppear { model.refresh() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Supabase CLI").font(.headline)
            Spacer()
            if let activity = model.activity {
                ProgressView().controlSize(.small)
                Text(activity).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            } else {
                Button { model.checkAgain() } label: { Image(systemName: "arrow.clockwise") }
                    .buttonStyle(.borderless)
                    .help(tr("Ask the CLI again which account it is on", "Volver a preguntar al CLI en qué cuenta está"))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    @ViewBuilder
    private var sessionNotice: some View {
        switch model.session {
        case .account:
            EmptyView()
        case .none:
            Banner(text: tr("The CLI has no login. Pick an account to start one.",
                            "El CLI no tiene ninguna sesión. Elige una cuenta para iniciarla."),
                   tint: .secondary)
        case .unregistered:
            Banner(
                text: tr("The CLI is logged in as an account not registered here. Capture it so it is not lost: until then no agent can switch over it.",
                         "El CLI está en una cuenta que no está registrada aquí. Captúrala para no perderla: hasta entonces ningún agente puede cambiar por encima."),
                tint: .orange,
                actionTitle: tr("Capture", "Capturar")
            ) { model.captureCurrent() }
        case .unverified(let detail):
            Banner(
                text: tr("There is a login, but I could not check whose it is: \(detail)",
                         "Hay una sesión, pero no pude comprobar de quién es: \(detail)"),
                tint: .orange,
                actionTitle: tr("Retry", "Reintentar")
            ) { model.checkAgain() }
        }
    }

    /// The other CLIs running on this Mac, apart from the accounts above.
    /// Los otros CLIs que corren en este Mac, aparte de las cuentas de arriba.
    private var runningCLIs: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(tr("Running CLIs", "CLIs en marcha"))
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if clis.summary.running.isEmpty {
                Text(tr("None right now", "Ninguno ahora mismo"))
                    .font(.callout)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(clis.summary.running.prefix(6)) { RunningCLIRow(cli: $0, compact: true).font(.callout) }
                if clis.summary.running.count > 6 {
                    Text(tr("and \(clis.summary.running.count - 6) more", "y \(clis.summary.running.count - 6) más"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Toggle(tr("Open at login", "Abrir al iniciar sesión"), isOn: Binding(
                get: { model.launchesAtLogin },
                set: { model.setLaunchAtLogin($0) }
            ))
            .toggleStyle(.checkbox)
            .font(.callout)
            Spacer()
            Button {
                openWindow(id: SettingsView.windowID)
                NSApp.activate(ignoringOtherApps: true)
            } label: {
                Image(systemName: "gearshape")
            }
            .buttonStyle(.borderless)
            .keyboardShortcut(",", modifiers: .command)
            .help(tr("Settings… (⌘,)", "Ajustes… (⌘,)"))
            Button(tr("Quit", "Salir")) { NSApp.terminate(nil) }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}

// MARK: - One account

struct AccountRow: View {
    @ObservedObject var model: AppModel
    let account: Account
    let usage: AccountUsage?
    let active: Bool
    let expanded: Bool
    let setExpanded: (Bool) -> Void

    @ViewState private var hovering = false
    @ViewState private var renaming = false
    @ViewState private var newName = ""
    @ViewState private var confirmingRemoval = false

    private var summary: String {
        if account.projects.isEmpty { return tr("no projects", "sin proyectos") }
        return account.projects.map(\.displayName).joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 0) {
                if renaming {
                    InlineNameField(
                        text: $newName,
                        placeholder: tr("Account name", "Nombre de la cuenta"),
                        save: saveName,
                        cancel: { renaming = false }
                    )
                    .padding(.leading, 12)
                    .padding(.trailing, 8)
                    .padding(.vertical, 6)
                } else {
                    switchButton
                }

                Button { setExpanded(!expanded) } label: {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .frame(width: 32, height: 32)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help(tr("Show its projects", "Ver sus proyectos"))
            }
            .background(hovering && !renaming ? Color.primary.opacity(0.07) : Color.clear)
            .onHover { hovering = $0 }
            .contextMenu { contextMenu }

            if expanded { details }
        }
    }

    private var switchButton: some View {
        Button {
            if !active { model.activate(account.id) }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: active ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(active ? Color.green : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name).fontWeight(active ? .semibold : .regular)
                    Text(active ? tr("in use · \(summary)", "en uso · \(summary)") : summary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, 12)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(active
              ? tr("The CLI is already on this account. Right-click for more.", "El CLI ya está en esta cuenta. Clic derecho para más.")
              : tr("Switch the CLI to this account. Right-click for more.", "Cambiar el CLI a esta cuenta. Clic derecho para más."))
    }

    @ViewBuilder
    private var contextMenu: some View {
        Button(tr("Switch to this account", "Cambiar a esta cuenta")) { model.activate(account.id) }
            .disabled(active)
        Button(tr("Rename…", "Renombrar…"), action: startRenaming)
        Button(expanded ? tr("Hide projects", "Ocultar proyectos") : tr("Show projects", "Ver proyectos")) {
            setExpanded(!expanded)
        }
        Button(tr("Read projects again", "Releer proyectos")) { model.refreshProjects(account.id) }
        Divider()
        Button(tr("Remove…", "Quitar…")) {
            setExpanded(true)
            confirmingRemoval = true
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(account.projects) { project in
                ProjectRow(model: model, accountID: account.id, project: project)
            }

            if let line = usageLine {
                Text(line).font(.caption).foregroundStyle(.secondary)
            }

            if confirmingRemoval {
                VStack(alignment: .leading, spacing: 6) {
                    Text(tr("Remove “\(account.name)”? Its token is deleted from the Keychain. The CLI stays as it is.",
                            "¿Quitar «\(account.name)»? Su token se borra del Llavero. El CLI se queda como está."))
                        .font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Button(tr("Remove", "Quitar"), role: .destructive) { model.remove(account.id) }
                        Button(tr("Cancel", "Cancelar")) { confirmingRemoval = false }
                    }
                }
            } else {
                HStack(spacing: 12) {
                    Button(tr("Rename", "Renombrar"), action: startRenaming)
                    Button(tr("Read projects again", "Releer proyectos")) { model.refreshProjects(account.id) }
                    Button(tr("Remove", "Quitar")) { confirmingRemoval = true }
                }
                .buttonStyle(.link)
                .font(.caption)
            }
        }
        .padding(.leading, 36)
        .padding(.trailing, 12)
        .padding(.bottom, 8)
    }

    private var usageLine: String? {
        guard let usage, usage.switches + usage.runs > 0 else { return nil }
        let last = usage.lastUsed.map { relativeTime($0) } ?? ""
        return switchesCount(usage.switches) + " · " + tr("last \(last)", "último \(last)")
    }

    private func startRenaming() {
        newName = account.name
        renaming = true
    }

    private func saveName() {
        let trimmed = newName.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty, trimmed != account.name { model.rename(account.id, to: trimmed) }
        renaming = false
    }
}

// MARK: - One project

struct ProjectRow: View {
    @ObservedObject var model: AppModel
    let accountID: UUID
    let project: Project

    @ViewState private var renaming = false
    @ViewState private var alias = ""
    @ViewState private var copied = false

    var body: some View {
        if renaming {
            InlineNameField(
                text: $alias,
                placeholder: project.name,
                save: {
                    model.renameProject(project.ref, in: accountID, to: alias)
                    renaming = false
                },
                cancel: { renaming = false }
            )
        } else {
            HStack(spacing: 6) {
                VStack(alignment: .leading, spacing: 0) {
                    Text(project.displayName)
                        .font(.callout)
                        .help(project.alias == nil ? "" : tr("In Supabase: \(project.name)", "En Supabase: \(project.name)"))
                    Text("\(project.ref) · \(project.region)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
                Button {
                    alias = project.alias ?? ""
                    renaming = true
                } label: {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(tr("Give this project a local name", "Dar a este proyecto un nombre local"))
                Button {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(project.ref, forType: .string)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .frame(width: 16)
                }
                .buttonStyle(.borderless)
                .help(copied ? tr("Copied", "Copiado") : tr("Copy the ref", "Copiar el ref"))
            }
        }
    }
}

// MARK: - Statistics

private struct StatsPanel: View {
    let usage: UsageSummary
    let close: () -> Void

    private var top: Int { max(usage.accounts.map(\.switches).max() ?? 0, 1) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(tr("Statistics", "Estadísticas")).font(.headline)
                Spacer()
                Button(action: close) { Image(systemName: "xmark") }
                    .buttonStyle(.borderless)
                    .help(tr("Close", "Cerrar"))
            }

            if usage.totalSwitches + usage.totalRuns == 0 {
                markdown(tr("Nothing counted yet. Switches and `keyturn run` commands are counted from version 1.1 on.",
                        "Aún no hay nada contado. Los cambios y las órdenes `keyturn run` se cuentan desde la versión 1.1."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(totals).font(.caption).foregroundStyle(.secondary)
                ForEach(usage.accounts) { item in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(item.account.name).font(.callout).lineLimit(1)
                            Spacer(minLength: 4)
                            Bar(fraction: Double(item.switches) / Double(top))
                            Text("\(item.switches)")
                                .font(.callout.monospacedDigit())
                                .frame(minWidth: 24, alignment: .trailing)
                        }
                        Text(detail(item)).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(12)
    }

    private var totals: String {
        let since = usage.since.map { relativeTime($0) } ?? ""
        return [switchesCount(usage.totalSwitches), runsCount(usage.totalRuns), tr("counted since \(since)", "contados desde \(since)")]
            .joined(separator: " · ")
    }

    private func detail(_ item: AccountUsage) -> String {
        let last = item.lastUsed.map { relativeTime($0) } ?? tr("never", "nunca")
        return [tr("\(item.switchesThisWeek) this week", "\(item.switchesThisWeek) esta semana"), runsCount(item.runs),
                tr("last \(last)", "último \(last)")].joined(separator: " · ")
    }

    private struct Bar: View {
        let fraction: Double
        private let width: CGFloat = 110

        var body: some View {
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.1))
                Capsule().fill(Color.accentColor).frame(width: max(width * fraction, fraction > 0 ? 4 : 0))
            }
            .frame(width: width, height: 6)
        }
    }
}

// MARK: - Adding an account

struct AddAccountForm: View {
    @ObservedObject var model: AppModel
    let close: () -> Void

    @ViewState private var token = ""
    @ViewState private var name = ""

    private static let tokensPage = URL(string: "https://supabase.com/dashboard/account/tokens")!

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(tr("Add account", "Añadir cuenta")).font(.headline)
            Text(tr("Create an access token in the Supabase dashboard with that account and paste it here. It is kept only in the Keychain.",
                    "Crea un token de acceso en el panel de Supabase con esa cuenta y pégalo aquí. Se guarda solo en el Llavero."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                SecureField("sbp_…", text: $token)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(submit)
                // Reads the clipboard directly, so pasting does not depend on ⌘V.
                // Lee el portapapeles directamente: pegar no depende de ⌘V.
                Button(tr("Paste", "Pegar")) {
                    token = NSPasteboard.general.string(forType: .string)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                }
            }
            TextField(tr("Name (optional: the organization's is used)", "Nombre (opcional: se usa el de la organización)"), text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(submit)

            HStack {
                Button(tr("Open the tokens page", "Abrir la página de tokens")) { NSWorkspace.shared.open(Self.tokensPage) }
                    .buttonStyle(.link)
                    .font(.caption)
                Spacer()
                Button(tr("Cancel", "Cancelar"), action: close)
                Button(tr("Add", "Añadir"), action: submit)
                    .keyboardShortcut(.defaultAction)
                    .disabled(token.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(12)
    }

    private func submit() {
        guard !token.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        model.add(token: token, name: name) {
            token = ""
            close()
        }
    }
}

// MARK: - Small pieces

/// "1 switch", "3 switches" / «1 cambio», «3 cambios».
func switchesCount(_ count: Int) -> String {
    count == 1 ? tr("1 switch", "1 cambio") : tr("\(count) switches", "\(count) cambios")
}

/// "1 run", "3 runs" / «1 orden», «3 órdenes».
func runsCount(_ count: Int) -> String {
    count == 1 ? tr("1 run", "1 orden") : tr("\(count) runs", "\(count) órdenes")
}

/// A text field with Save and Cancel that takes the keyboard as soon as it
/// appears: Return saves, Escape cancels.
/// Un campo con Guardar y Cancelar que coge el teclado nada más aparecer:
/// Intro guarda, Escape cancela.
struct InlineNameField: View {
    @Binding var text: String
    let placeholder: String
    let save: () -> Void
    let cancel: () -> Void

    @ViewFocus private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(placeholder, text: $text)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit(save)
                .onExitCommand(perform: cancel)
            Button(tr("Save", "Guardar"), action: save)
                .controlSize(.small)
            Button(action: cancel) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .help(tr("Cancel", "Cancelar"))
        }
        .onAppear {
            // The panel has to be key before the field can take the focus.
            // El panel tiene que ser la ventana activa antes de que el campo coja el foco.
            NSApp.activate(ignoringOtherApps: true)
            DispatchQueue.main.async { focused = true }
        }
    }
}

private struct MenuButton: View {
    let title: String
    let icon: String
    let action: () -> Void

    @ViewState private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).frame(width: 16)
                Text(title)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovering ? Color.primary.opacity(0.07) : Color.clear)
        .onHover { hovering = $0 }
    }
}

private struct Banner: View {
    let text: String
    let tint: Color
    var actionTitle: String?
    var action: (() -> Void)?

    init(text: String, tint: Color, actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.tint = tint
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.caption)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if let action {
                if let actionTitle {
                    Button(actionTitle, action: action).controlSize(.small)
                } else {
                    Button(action: action) { Image(systemName: "xmark") }
                        .buttonStyle(.borderless)
                        .help(tr("Close", "Cerrar"))
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.14))
    }
}

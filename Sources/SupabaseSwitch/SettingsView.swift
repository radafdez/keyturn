import AppKit
import SwiftUI
import SwitchCore

/// The settings window: a sidebar of panes, the way macOS apps lay them out.
/// La ventana de ajustes: una barra lateral de paneles, como las apps de macOS.
struct SettingsView: View {
    static let windowID = "settings"

    @ObservedObject var model: AppModel
    @ViewState private var pane: Pane?

    init(model: AppModel, pane: Pane = .general) {
        self.model = model
        _pane = ViewState(initialValue: pane)
    }

    enum Pane: String, CaseIterable, Identifiable {
        case general, accounts, agents, activity, statistics, about
        var id: String { rawValue }

        var title: String {
            switch self {
            case .general: return tr("General", "General")
            case .accounts: return tr("Accounts", "Cuentas")
            case .agents: return tr("AI agents", "Agentes de IA")
            case .activity: return tr("Activity", "Actividad")
            case .statistics: return tr("Statistics", "Estadísticas")
            case .about: return tr("About", "Acerca de")
            }
        }

        var icon: String {
            switch self {
            case .general: return "gearshape"
            case .accounts: return "person.2"
            case .agents: return "sparkles"
            case .activity: return "clock.arrow.circlepath"
            case .statistics: return "chart.bar"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Pane.allCases, selection: $pane) { pane in
                NavigationLink(value: pane) {
                    Label(pane.title, systemImage: pane.icon)
                }
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 180, max: 220)
        } detail: {
            Group {
                switch pane ?? .general {
                case .general: GeneralPane(model: model)
                case .accounts: AccountsPane(model: model)
                case .agents: AgentsPane(model: model)
                case .activity: ActivityPane(model: model)
                case .statistics: StatisticsPane(model: model)
                case .about: AboutPane()
                }
            }
            .navigationTitle((pane ?? .general).title)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .frame(minWidth: 680, minHeight: 480)
        .onAppear { model.refresh() }
    }
}

// MARK: - General

private struct GeneralPane: View {
    @ObservedObject var model: AppModel
    @ObservedObject var updater = Updater.shared

    var body: some View {
        Form {
            Section {
                Picker(tr("Language", "Idioma"), selection: Binding(
                    get: { model.language },
                    set: { model.setLanguage($0) }
                )) {
                    ForEach(AppModel.LanguageChoice.allCases) { Text($0.title).tag($0) }
                }
                Toggle(tr("Open at login", "Abrir al iniciar sesión"), isOn: Binding(
                    get: { model.launchesAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                ))
            }

            if updater.channel == .sparkle {
                Section(tr("Updates", "Actualizaciones")) {
                    Toggle(tr("Check for updates automatically", "Buscar actualizaciones automáticamente"), isOn: Binding(
                        get: { updater.checksAutomatically },
                        set: { updater.setChecksAutomatically($0) }
                    ))
                    LabeledContent(tr("Version \(switchVersion)", "Versión \(switchVersion)")) {
                        Button(tr("Check Now", "Buscar ahora")) { updater.checkForUpdates() }
                            .disabled(!updater.canCheck)
                    }
                    Text(tr("A check only asks GitHub for the list of versions. It sends nothing about you or this Mac.",
                            "Una comprobación solo pide a GitHub la lista de versiones. No envía nada sobre ti ni sobre este Mac."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                LabeledContent(tr("Accounts and history", "Cuentas e historial")) {
                    Button(tr("Show in Finder", "Mostrar en el Finder")) { model.showStateFile() }
                }
                Text(tr("Names, projects and the history live in that file. The tokens do not: they are only in the Keychain.",
                        "Los nombres, los proyectos y el historial viven en ese fichero. Los tokens no: están solo en el Llavero."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section(tr("In a terminal", "En una terminal")) {
                CopyField(text: tr("sbswitch use <project>", "sbswitch use <proyecto>"))
                markdown(tr("`sbswitch` does the same switch from the shell: `status`, `list`, `use`, `run` and `mcp`.",
                            "`sbswitch` hace el mismo cambio desde el shell: `status`, `list`, `use`, `run` y `mcp`."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: - Accounts

private struct AccountsPane: View {
    @ObservedObject var model: AppModel
    @ViewState private var expanded: UUID?
    @ViewState private var adding = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let problem = model.problem {
                    Text(problem)
                        .font(.callout)
                        .foregroundStyle(.red)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Card {
                    if model.accounts.isEmpty {
                        Text(tr("No accounts yet.", "Aún no hay cuentas."))
                            .foregroundStyle(.secondary)
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
                                if account.id != model.accounts.last?.id { Divider() }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }

                if adding {
                    Card { AddAccountForm(model: model) { adding = false } }
                } else {
                    HStack {
                        Button(tr("Add account with its token…", "Añadir cuenta con su token…")) { adding = true }
                        Button(tr("Capture the CLI's current login", "Capturar la sesión actual del CLI")) { model.captureCurrent() }
                        Spacer()
                        if let activity = model.activity {
                            ProgressView().controlSize(.small)
                            Text(activity).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .padding(20)
            .disabled(model.activity != nil)
        }
    }
}

// MARK: - AI agents

private struct AgentsPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { model.agentsCanSwitch }, set: { model.setAgentsCanSwitch($0) })) {
                    Text(tr("Let AI agents switch the account", "Dejar que los agentes de IA cambien la cuenta"))
                    Text(tr("Off, they can still see which account is in use, and they are told to ask you.",
                            "Si está apagado, pueden ver qué cuenta está en uso, y se les dice que te lo pidan."))
                }
                Toggle(isOn: Binding(get: { model.notifiesAgentSwitches }, set: { model.setNotifiesAgentSwitches($0) })) {
                    Text(tr("Tell me when an agent switches", "Avisarme cuando un agente cambie"))
                    Text(tr("A macOS notification with the agent and the account. Every switch is in Activity either way.",
                            "Un aviso de macOS con el agente y la cuenta. Todos los cambios quedan en Actividad igualmente."))
                }
            } footer: {
                markdown(tr("Agents talk to `sbswitch mcp` (Model Context Protocol). They can list your accounts and projects and switch the CLI. They never see a token.",
                        "Los agentes hablan con `sbswitch mcp` (Model Context Protocol). Pueden ver tus cuentas y proyectos y cambiar el CLI. Nunca ven un token."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section(tr("Connect", "Conectar")) {
                ForEach(AgentClient.all) { client in
                    AgentRow(model: model, client: client)
                }
            }

            Section {
                CopyField(text: AgentClient.jsonConfiguration(sbswitch: model.sbswitchPath), lines: 8)
            } header: {
                Text(tr("Claude Desktop, Cursor, Windsurf and others", "Claude Desktop, Cursor, Windsurf y otros"))
            } footer: {
                Text(tr("Add this to the tool's MCP configuration file and restart it.",
                        "Añade esto al fichero de configuración MCP de la herramienta y reiníciala."))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .onAppear { model.checkAgents() }
    }
}

private struct AgentRow: View {
    @ObservedObject var model: AppModel
    let client: AgentClient

    private var status: AppModel.AgentStatus { model.agents[client.id] ?? .checking }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(client.title)
                    statusLine
                }
                Spacer()
                actions
            }
            if case .failed(_, let detail) = status {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if case .missing = status {
                EmptyView()
            } else {
                CopyField(text: client.commandLine(sbswitch: model.sbswitchPath))
            }
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var statusLine: some View {
        switch status {
        case .checking:
            Text(tr("Looking…", "Buscando…")).font(.caption).foregroundStyle(.secondary)
        case .missing:
            Text(tr("Not found on this Mac", "No está en este Mac")).font(.caption).foregroundStyle(.secondary)
        case .disconnected:
            Text(tr("Installed, not connected", "Instalado, sin conectar")).font(.caption).foregroundStyle(.secondary)
        case .connected:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                Text(tr("Connected", "Conectado"))
            }
            .font(.caption)
            .foregroundStyle(.green)
        case .working:
            Text(tr("Working…", "Trabajando…")).font(.caption).foregroundStyle(.secondary)
        case .failed:
            Text(tr("It did not work", "No funcionó")).font(.caption).foregroundStyle(.red)
        }
    }

    @ViewBuilder
    private var actions: some View {
        switch status {
        case .checking, .working:
            ProgressView().controlSize(.small)
        case .missing:
            Button(tr("Look again", "Volver a buscar")) { model.checkAgents() }
        case .connected:
            Button(tr("Disconnect", "Desconectar")) { model.disconnect(client) }
        case .disconnected, .failed:
            Button(tr("Connect", "Conectar")) { model.connect(client) }
                .disabled(status.executable == nil)
        }
    }
}

// MARK: - Activity

private struct ActivityPane: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.usage.recent.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "clock").font(.largeTitle).foregroundStyle(.tertiary)
                Text(tr("Nothing yet. Every switch shows up here, with who asked for it.",
                        "Aún nada. Cada cambio aparece aquí, con quién lo pidió."))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List(Array(model.usage.recent.enumerated()), id: \.offset) { _, event in
                HStack(spacing: 10) {
                    Image(systemName: icon(event))
                        .foregroundStyle(event.source == .agent ? Color.accentColor : Color.secondary)
                        .frame(width: 20)
                    markdown(sentence(event))
                    Spacer()
                    Text(relativeTime(event.date))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help(event.date.formatted(.dateTime.locale(AppLanguage.current.locale)))
                }
                .padding(.vertical, 2)
            }
        }
    }

    private func icon(_ event: UsageEvent) -> String {
        switch event.source {
        case .agent: return "sparkles"
        case .terminal: return "terminal"
        case .menu: return "menubar.rectangle"
        case nil: return "circle.dashed"
        }
    }

    private func sentence(_ event: UsageEvent) -> String {
        let account = model.accountName(event.accountID)
        switch (event.kind, event.source) {
        case (.ran, _):
            return tr("`sbswitch run` with “\(account)”", "`sbswitch run` con «\(account)»")
        case (.switched, .agent):
            let who = clientTitle(event.client)
            return tr("\(who) switched to “\(account)”", "\(who) cambió a «\(account)»")
        case (.switched, .terminal):
            return tr("Switched to “\(account)” from a terminal", "Cambio a «\(account)» desde una terminal")
        case (.switched, .menu):
            return tr("Switched to “\(account)” from the menu", "Cambio a «\(account)» desde el menú")
        case (.switched, nil):
            return tr("Switched to “\(account)”", "Cambio a «\(account)»")
        }
    }
}

// MARK: - Statistics

private struct StatisticsPane: View {
    @ObservedObject var model: AppModel

    private var usage: UsageSummary { model.usage }

    var body: some View {
        Form {
            if usage.totalSwitches + usage.totalRuns == 0 {
                Text(tr("Nothing counted yet.", "Aún no hay nada contado.")).foregroundStyle(.secondary)
            } else {
                Section {
                    LabeledContent(tr("Switches", "Cambios"), value: "\(usage.totalSwitches)")
                    LabeledContent(tr("sbswitch run commands", "Órdenes sbswitch run"), value: "\(usage.totalRuns)")
                    if let since = usage.since {
                        LabeledContent(tr("Counted since", "Contado desde"),
                                       value: since.formatted(.dateTime.year().month().day().locale(AppLanguage.current.locale)))
                    }
                }

                Section(tr("By account", "Por cuenta")) {
                    let top = max(usage.accounts.map(\.switches).max() ?? 0, 1)
                    ForEach(usage.accounts) { item in
                        CountRow(title: item.account.name, count: item.switches, top: top,
                                 detail: tr("\(item.switchesThisWeek) this week", "\(item.switchesThisWeek) esta semana")
                                    + " · " + runsCount(item.runs))
                    }
                }

                Section(tr("Who switched", "Quién cambió")) {
                    let sources: [(String, Int)] = [
                        (tr("You, from the menu", "Tú, desde el menú"), usage.switchesBySource[.menu] ?? 0),
                        (tr("A terminal", "Una terminal"), usage.switchesBySource[.terminal] ?? 0),
                        (tr("AI agents", "Agentes de IA"), usage.switchesBySource[.agent] ?? 0),
                        (tr("Before 1.2 (not recorded)", "Antes de la 1.2 (sin registrar)"), usage.switchesBySource[nil] ?? 0),
                    ].filter { $0.1 > 0 }
                    let top = max(sources.map(\.1).max() ?? 0, 1)
                    ForEach(sources, id: \.0) { CountRow(title: $0.0, count: $0.1, top: top) }
                }

                if !usage.agentClients.isEmpty {
                    Section(tr("By agent", "Por agente")) {
                        let top = max(usage.agentClients.map(\.switches).max() ?? 0, 1)
                        ForEach(usage.agentClients) { CountRow(title: clientTitle($0.client), count: $0.switches, top: top) }
                    }
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct CountRow: View {
    let title: String
    let count: Int
    let top: Int
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
                Capsule().fill(Color.accentColor).frame(width: max(160 * Double(count) / Double(top), count > 0 ? 4 : 0))
            }
            .frame(width: 160, height: 6)
            Text("\(count)").monospacedDigit().frame(minWidth: 28, alignment: .trailing)
        }
    }
}

// MARK: - About

/// Laid out like the About pane of the menu bar tools it takes after: who
/// made it, how it updates, where to find it, and its license.
/// Dispuesto como el panel Acerca de de las herramientas de barra de menús en
/// las que se inspira: quién la hizo, cómo se actualiza, dónde está y su licencia.
private struct AboutPane: View {
    static let repository = URL(string: "https://github.com/radafdez/supabase-switch")!

    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }
    private var build: String { info["CFBundleVersion"] as? String ?? "dev" }
    private var builtOn: String? {
        guard let raw = info["SupabaseSwitchBuildDate"] as? String,
              let date = ISO8601DateFormatter().date(from: raw) else { return nil }
        return date.formatted(.dateTime.year().month(.wide).day().locale(AppLanguage.current.locale))
    }
    private var copyright: String {
        (info["NSHumanReadableCopyright"] as? String)?.replacingOccurrences(of: "Copyright ", with: "") ?? "© 2026 Radames Fernandez. MIT License."
    }

    @ObservedObject var updater = Updater.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                VStack(spacing: 6) {
                    Image(nsImage: NSApp.applicationIconImage)
                        .resizable()
                        .frame(width: 96, height: 96)
                    Text("Supabase Switch").font(.title2.bold())
                    Text(tr("Version \(switchVersion) (\(build))", "Versión \(switchVersion) (\(build))"))
                        .foregroundStyle(.secondary)
                    if let builtOn {
                        Text(tr("Built \(builtOn)", "Compilada el \(builtOn)"))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(tr("One click to put the Supabase CLI on the right account. For you, your terminal and your AI agents.",
                            "Un clic para poner el CLI de Supabase en la cuenta correcta. Para ti, tu terminal y tus agentes de IA."))
                        .multilineTextAlignment(.center)
                        .padding(.top, 4)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        switch updater.channel {
                        case .sparkle:
                            Text(tr("New versions come from GitHub, signed with the project's key. The app installs them for you and refuses any that is not signed.",
                                    "Las versiones nuevas llegan de GitHub, firmadas con la clave del proyecto. La app las instala por ti y rechaza cualquiera que no lo esté."))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(tr("Check for Updates…", "Buscar actualizaciones…")) { updater.checkForUpdates() }
                                .disabled(!updater.canCheck)
                        case .manual:
                            Text(tr("This copy was built from source, so it does not update itself. New versions are published on GitHub.",
                                    "Esta copia se compiló desde el código, así que no se actualiza sola. Las versiones nuevas se publican en GitHub."))
                                .font(.callout)
                                .fixedSize(horizontal: false, vertical: true)
                            Button(tr("Open the releases page", "Abrir la página de versiones")) {
                                NSWorkspace.shared.open(Self.repository.appendingPathComponent("releases"))
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                } label: {
                    Text(tr("Updates", "Actualizaciones")).font(.headline)
                }

                GroupBox {
                    HStack(spacing: 18) {
                        LinkButton(title: "GitHub", icon: "chevron.left.forwardslash.chevron.right", url: Self.repository)
                        LinkButton(title: tr("Report a problem", "Avisar de un fallo"), icon: "exclamationmark.bubble",
                                   url: Self.repository.appendingPathComponent("issues/new/choose"))
                        LinkButton(title: tr("Changes", "Cambios"), icon: "list.bullet.rectangle",
                                   url: Self.repository.appendingPathComponent("blob/main/CHANGELOG.md"))
                        LinkButton(title: tr("License", "Licencia"), icon: "doc.text",
                                   url: Self.repository.appendingPathComponent("blob/main/LICENSE"))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(4)
                } label: {
                    Text(tr("Links", "Enlaces")).font(.headline)
                }

                Text(copyright)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct LinkButton: View {
    let title: String
    let icon: String
    let url: URL

    var body: some View {
        Button { NSWorkspace.shared.open(url) } label: {
            Label(title, systemImage: icon)
        }
        .buttonStyle(.link)
        .help(url.absoluteString)
    }
}

// MARK: - Small pieces

/// `Text` shows a `String` as it is; this one reads its `code` and *emphasis*.
/// `Text` enseña un `String` tal cual; este lee su `code` y su *énfasis*.
func markdown(_ text: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
}

/// Monospaced text with a copy button: commands and configuration to paste.
/// Texto monoespaciado con botón de copiar: órdenes y configuración para pegar.
struct CopyField: View {
    let text: String
    var lines = 1

    @ViewState private var copied = false

    var body: some View {
        HStack(alignment: lines > 1 ? .top : .center, spacing: 8) {
            Text(text)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .lineLimit(lines > 1 ? nil : 1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc").frame(width: 16)
            }
            .buttonStyle(.borderless)
            .help(copied ? tr("Copied", "Copiado") : tr("Copy", "Copiar"))
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.06)))
    }
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 10).fill(Color.primary.opacity(0.04)))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color.primary.opacity(0.08)))
    }
}

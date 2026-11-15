import Foundation
import SwitchCore

let usage = tr(
    """
    sbswitch \(switchVersion) — switch the account the Supabase CLI works with

      sbswitch                          list the accounts and mark the one in use
      sbswitch use <account>            switch the CLI to that account
      sbswitch current                  say which account the CLI is on now
      sbswitch capture [name]           register the account the CLI is logged in as
      sbswitch add [name]               register an account from its access token
                                        (asked without echo, or read from stdin)
      sbswitch refresh [account]        read the projects of one account again, or of all
      sbswitch rename <account> <new name>
      sbswitch alias <project> [alias]  give a project a local name; without one, go back
                                        to its Supabase name
      sbswitch remove <account>
      sbswitch stats                    switches and runs per account
      sbswitch run <account> -- <cmd>   run one command as that account without switching
      sbswitch version

    <account> is its name, the start of its name, or the ref, name or alias of
    one of its projects: `sbswitch use abcdefghijklmnopqrst` works like `sbswitch use acme`.
    """,
    """
    sbswitch \(switchVersion) — cambia la cuenta con la que trabaja el CLI de Supabase

      sbswitch                          lista las cuentas y marca la que está en uso
      sbswitch use <cuenta>             cambia el CLI a esa cuenta
      sbswitch current                  dice qué cuenta tiene el CLI ahora
      sbswitch capture [nombre]         registra la cuenta con la que el CLI está logueado
      sbswitch add [nombre]             registra una cuenta con su token (lo pide sin
                                        mostrarlo, o lo lee de la entrada estándar)
      sbswitch refresh [cuenta]         vuelve a leer los proyectos de una cuenta, o de todas
      sbswitch rename <cuenta> <nombre nuevo>
      sbswitch alias <proyecto> [alias] da a un proyecto un nombre local; sin alias, vuelve
                                        a su nombre de Supabase
      sbswitch remove <cuenta>
      sbswitch stats                    cambios y órdenes por cuenta
      sbswitch run <cuenta> -- <orden>  lanza una orden con esa cuenta sin cambiar el CLI
      sbswitch version

    <cuenta> es su nombre, el principio del nombre, o el ref, el nombre o el alias de
    uno de sus proyectos: `sbswitch use abcdefghijklmnopqrst` vale igual que `sbswitch use acme`.
    """
)

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

func describe(_ session: SessionStatus, in accounts: [Account]) -> String {
    switch session {
    case .none:
        return tr("The CLI has no stored login.", "El CLI no tiene ninguna sesión guardada.")
    case .account(let id):
        let name = accounts.first { $0.id == id }?.name ?? "?"
        return tr("The CLI is on “\(name)”.", "El CLI está en «\(name)».")
    case .unregistered:
        return tr("The CLI is logged in as an account not registered here. Register it with `sbswitch capture`.",
                  "El CLI está en una cuenta que no está registrada aquí. Regístrala con `sbswitch capture`.")
    case .unverified(let detail):
        return tr("There is a login, but I could not check whose it is: \(detail)",
                  "Hay una sesión, pero no pude comprobar de quién es: \(detail)")
    }
}

func printAccount(_ account: Account, active: Bool) {
    print("\(active ? "●" : "○") \(account.name)\(active ? tr("  (in use)", "  (en uso)") : "")")
    for project in account.projects {
        let alias = project.alias.map { "  (\($0))" } ?? ""
        print("    \(project.ref)  \(project.name)\(alias)  \(project.region)")
    }
    if account.projects.isEmpty { print(tr("    (no projects)", "    (sin proyectos)")) }
}

func printStats(_ usage: UsageSummary) {
    guard usage.totalSwitches + usage.totalRuns > 0 else {
        print(tr("Nothing counted yet: switches and runs are counted from version 1.1 on.",
                 "Aún no hay nada contado: los cambios y las órdenes se cuentan desde la versión 1.1."))
        return
    }
    let since = usage.since.map { relativeTime($0) } ?? ""
    print(tr("\(usage.totalSwitches) switches and \(usage.totalRuns) runs, counted since \(since)",
             "\(usage.totalSwitches) cambios y \(usage.totalRuns) órdenes, contados desde \(since)"))
    let width = usage.accounts.map(\.account.name.count).max() ?? 0
    for item in usage.accounts {
        let name = item.account.name.padding(toLength: width, withPad: " ", startingAt: 0)
        let last = item.lastUsed.map { relativeTime($0) } ?? tr("never", "nunca")
        print(tr(
            "  \(name)  \(item.switches) switches (\(item.switchesThisWeek) this week) · \(item.runs) runs · last \(last)",
            "  \(name)  \(item.switches) cambios (\(item.switchesThisWeek) esta semana) · \(item.runs) órdenes · último \(last)"
        ))
    }
}

/// A token typed by hand is read without echo; one piped in is read as is.
/// It is never taken from the arguments, where any process could see it.
/// Un token escrito a mano se lee sin eco; uno que llega por tubería, tal cual.
/// Nunca se toma de los argumentos, donde cualquier proceso podría verlo.
func readToken() -> String {
    if isatty(STDIN_FILENO) != 0 {
        guard let typed = getpass(tr("Supabase access token (not shown): ", "Token de acceso de Supabase (no se muestra): ")) else { return "" }
        return String(cString: typed)
    }
    return readLine(strippingNewline: true) ?? ""
}

func main() throws {
    var arguments = Array(CommandLine.arguments.dropFirst())
    let command = arguments.isEmpty ? "list" : arguments.removeFirst()

    if ["help", "-h", "--help"].contains(command) {
        print(usage)
        return
    }
    if ["version", "-v", "--version"].contains(command) {
        print("sbswitch \(switchVersion)")
        return
    }

    let service = try SwitchService.live()

    func account(_ query: String?) throws -> Account {
        guard let query, !query.isEmpty else { fail(usage) }
        return try SwitchService.resolve(query, in: try service.snapshot().accounts)
    }

    switch command {
    case "list", "ls":
        let snapshot = try service.snapshot()
        if snapshot.accounts.isEmpty {
            print(tr("No accounts yet. Start with `sbswitch capture`.", "Aún no hay cuentas. Empieza por `sbswitch capture`."))
        }
        for item in snapshot.accounts {
            printAccount(item, active: snapshot.activeAccount?.id == item.id)
        }
        if snapshot.activeAccount == nil { print(describe(snapshot.session, in: snapshot.accounts)) }

    case "current":
        let snapshot = try service.snapshot(askingTheCLIAgain: true)
        print(describe(snapshot.session, in: snapshot.accounts))

    case "use":
        let target = try account(arguments.first)
        let snapshot = try service.activate(target.id)
        print(describe(snapshot.session, in: snapshot.accounts))

    case "capture":
        print(tr("macOS is going to ask your permission to read the login the CLI keeps.",
                 "macOS te va a pedir permiso para leer la sesión que guarda el CLI."))
        let name = arguments.isEmpty ? nil : arguments.joined(separator: " ")
        printAccount(try service.captureCurrent(name: name), active: true)

    case "add":
        let name = arguments.isEmpty ? nil : arguments.joined(separator: " ")
        let added = try service.addAccount(token: readToken(), name: name)
        let snapshot = try service.snapshot()
        printAccount(added, active: snapshot.activeAccount?.id == added.id)

    case "refresh":
        let targets = arguments.isEmpty ? try service.snapshot().accounts : [try account(arguments.first)]
        for target in targets {
            printAccount(try service.refreshProjects(target.id), active: false)
        }

    case "rename":
        guard arguments.count >= 2 else { fail(usage) }
        let target = try account(arguments.first)
        try service.rename(target.id, to: arguments.dropFirst().joined(separator: " "))

    case "alias":
        guard let query = arguments.first else { fail(usage) }
        let found = try SwitchService.resolveProject(query, in: try service.snapshot().accounts)
        let alias = arguments.dropFirst().joined(separator: " ")
        try service.renameProject(found.project.ref, in: found.account.id, to: alias)
        print(alias.isEmpty
              ? tr("\(found.project.ref) is called “\(found.project.name)” again.",
                   "\(found.project.ref) vuelve a llamarse «\(found.project.name)».")
              : tr("\(found.project.ref) is now “\(alias)”.", "\(found.project.ref) ahora es «\(alias)»."))

    case "remove", "rm":
        let target = try account(arguments.first)
        try service.remove(target.id)
        print(tr("“\(target.name)” is no longer registered. The CLI stays as it was.",
                 "«\(target.name)» ya no está registrada. El CLI sigue como estaba."))

    case "stats":
        printStats(try service.snapshot().usage)

    case "run":
        guard let separator = arguments.firstIndex(of: "--"), separator == 1, arguments.count > 2 else { fail(usage) }
        let target = try account(arguments.first)
        let order = Array(arguments[(separator + 1)...])
        // The token travels in the environment of the new process, which then
        // replaces this one. The CLI's stored session is not touched.
        // El token viaja en el entorno del proceso nuevo, que sustituye a este.
        // La sesión guardada del CLI no se toca.
        setenv("SUPABASE_ACCESS_TOKEN", try service.tokenForRun(target.id), 1)
        var argv: [UnsafeMutablePointer<CChar>?] = order.map { strdup($0) }
        argv.append(nil)
        execvp(order[0], argv)
        fail(tr("Could not run “\(order[0])”: \(String(cString: strerror(errno)))",
                "No pude lanzar «\(order[0])»: \(String(cString: strerror(errno)))"))

    default:
        fail(usage)
    }
}

do {
    try main()
} catch {
    fail((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
}

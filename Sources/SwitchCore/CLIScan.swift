import Darwin
import Foundation

// MARK: - What is running

/// One process on this Mac, as the scanner sees it. The arguments are only
/// read to tell which tool a `node` or `python` is running; they are never
/// kept or shown.
///
/// Un proceso de este Mac, tal como lo ve el escáner. Los argumentos solo se
/// leen para saber qué herramienta ejecuta un `node` o un `python`; nunca se
/// guardan ni se enseñan.
public struct RunningProcess: Equatable, Sendable {
    public var pid: Int32
    public var parent: Int32
    /// Whole seconds, so the same process always has the same start.
    /// En segundos enteros, para que un proceso tenga siempre el mismo inicio.
    public var started: Date
    /// The executable, with symlinks resolved. / El ejecutable, con los enlaces resueltos.
    public var path: String
    public var arguments: [String]
    /// Run by the user of this session (not root, not another user).
    /// Lo ejecuta el usuario de esta sesión (ni root, ni otro usuario).
    public var isMine: Bool

    public init(pid: Int32, parent: Int32, started: Date, path: String, arguments: [String] = [], isMine: Bool = true) {
        self.pid = pid
        self.parent = parent
        self.started = started
        self.path = path
        self.arguments = arguments
        self.isMine = isMine
    }
}

public protocol ProcessSource: Sendable {
    func processes() -> [RunningProcess]
}

/// Reads the process table straight from the kernel (libproc and sysctl), the
/// same way `ps` does. Nothing is run, and a whole pass takes a few milliseconds.
///
/// Lee la tabla de procesos directamente del kernel (libproc y sysctl), igual
/// que `ps`. No se ejecuta nada, y una pasada entera tarda unos milisegundos.
public struct LiveProcessSource: ProcessSource {
    public init() {}

    public func processes() -> [RunningProcess] {
        let needed = proc_listallpids(nil, 0)
        guard needed > 0 else { return [] }
        // Room for the ones that start while listing. / Sitio para los que arrancan mientras.
        var pids = [pid_t](repeating: 0, count: Int(needed) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { return [] }
        let me = getuid()

        return pids.prefix(Int(count)).compactMap { pid in
            guard pid > 0 else { return nil }
            var info = proc_bsdinfo()
            let size = Int32(MemoryLayout<proc_bsdinfo>.size)
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
            let mine = info.pbi_uid == me
            return RunningProcess(
                pid: pid,
                parent: Int32(info.pbi_ppid),
                started: Date(timeIntervalSince1970: TimeInterval(info.pbi_start_tvsec)),
                path: Self.path(of: pid),
                // The kernel only hands them over for our own processes anyway.
                // El kernel solo los da de nuestros propios procesos, de todos modos.
                arguments: mine ? Self.arguments(of: pid) : [],
                isMine: mine
            )
        }
    }

    private static func path(of pid: pid_t) -> String {
        // PROC_PIDPATHINFO_MAXSIZE, which Swift does not import.
        // PROC_PIDPATHINFO_MAXSIZE, que Swift no importa.
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : ""
    }

    /// KERN_PROCARGS2 is `argc`, the executable path, padding, then the arguments.
    /// KERN_PROCARGS2 es `argc`, la ruta del ejecutable, relleno y luego los argumentos.
    private static func arguments(of pid: pid_t) -> [String] {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return [] }
        let argc = buffer.withUnsafeBytes { $0.loadUnaligned(as: Int32.self) }

        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }
}

// MARK: - Which tools are watched

/// A command-line tool the scanner knows by name.
/// Una herramienta de línea de órdenes que el escáner reconoce por su nombre.
public struct KnownCLI: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// Names of the command, as typed. / Nombres de la orden, tal como se escribe.
    public var executables: [String]
    /// npm packages it lives in, for the ones that run on `node`.
    /// Paquetes de npm donde vive, para las que corren sobre `node`.
    public var packages: [String]

    public init(id: String, title: String, executables: [String], packages: [String] = []) {
        self.id = id
        self.title = title
        self.executables = executables
        self.packages = packages
    }

    /// A command the user added by hand; its name is its title.
    /// Una orden que el usuario añadió a mano; su nombre es su título.
    public static func custom(_ command: String) -> KnownCLI {
        KnownCLI(id: command, title: command, executables: [command])
    }

    public static let catalog: [KnownCLI] = [
        KnownCLI(id: "supabase", title: "Supabase CLI", executables: ["supabase"], packages: ["supabase"]),
        // AI agents. / Agentes de IA.
        KnownCLI(id: "claude", title: "Claude Code", executables: ["claude"], packages: ["@anthropic-ai/claude-code"]),
        KnownCLI(id: "codex", title: "Codex", executables: ["codex"], packages: ["@openai/codex"]),
        KnownCLI(id: "gemini", title: "Gemini CLI", executables: ["gemini"], packages: ["@google/gemini-cli"]),
        KnownCLI(id: "copilot", title: "GitHub Copilot CLI", executables: ["copilot"], packages: ["@github/copilot"]),
        KnownCLI(id: "cursor-agent", title: "Cursor Agent", executables: ["cursor-agent"]),
        KnownCLI(id: "opencode", title: "opencode", executables: ["opencode"], packages: ["opencode-ai"]),
        KnownCLI(id: "aider", title: "Aider", executables: ["aider"]),
        // Hosting and clouds. / Alojamiento y nubes.
        KnownCLI(id: "vercel", title: "Vercel CLI", executables: ["vercel", "vc"], packages: ["vercel"]),
        KnownCLI(id: "netlify", title: "Netlify CLI", executables: ["netlify", "ntl"], packages: ["netlify-cli"]),
        KnownCLI(id: "wrangler", title: "Cloudflare Wrangler", executables: ["wrangler"], packages: ["wrangler"]),
        KnownCLI(id: "firebase", title: "Firebase CLI", executables: ["firebase"], packages: ["firebase-tools"]),
        KnownCLI(id: "fly", title: "Fly.io CLI", executables: ["fly", "flyctl"]),
        KnownCLI(id: "railway", title: "Railway CLI", executables: ["railway"], packages: ["@railway/cli"]),
        KnownCLI(id: "heroku", title: "Heroku CLI", executables: ["heroku"], packages: ["heroku"]),
        KnownCLI(id: "eas", title: "Expo EAS CLI", executables: ["eas"], packages: ["eas-cli"]),
        KnownCLI(id: "aws", title: "AWS CLI", executables: ["aws"]),
        KnownCLI(id: "gcloud", title: "Google Cloud CLI", executables: ["gcloud"]),
        KnownCLI(id: "az", title: "Azure CLI", executables: ["az", "azure.cli"]),
        KnownCLI(id: "doctl", title: "DigitalOcean CLI", executables: ["doctl"]),
        // Everything else a developer leaves running. / Lo demás que se queda corriendo.
        KnownCLI(id: "gh", title: "GitHub CLI", executables: ["gh"]),
        KnownCLI(id: "stripe", title: "Stripe CLI", executables: ["stripe"], packages: ["@stripe/cli"]),
        KnownCLI(id: "docker", title: "Docker CLI", executables: ["docker"]),
        KnownCLI(id: "kubectl", title: "kubectl", executables: ["kubectl"]),
        KnownCLI(id: "terraform", title: "Terraform", executables: ["terraform"]),
        KnownCLI(id: "pulumi", title: "Pulumi", executables: ["pulumi"]),
        KnownCLI(id: "ngrok", title: "ngrok", executables: ["ngrok"]),
        KnownCLI(id: "psql", title: "psql", executables: ["psql"]),
    ]

    /// The catalog plus the user's own commands, without repeating a name.
    /// El catálogo más las órdenes del usuario, sin repetir ningún nombre.
    public static func watched(adding extra: [String]) -> [KnownCLI] {
        var tools = catalog
        var taken = Set(catalog.flatMap(\.executables) + catalog.map(\.id))
        for command in extra.map(normalizedCommand) where !command.isEmpty && !taken.contains(command) {
            tools.append(.custom(command))
            taken.insert(command)
        }
        return tools
    }

    /// "  /usr/local/bin/Foo " → "Foo": only the name of the command counts.
    /// «  /usr/local/bin/Foo » → «Foo»: solo cuenta el nombre de la orden.
    public static func normalizedCommand(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed as NSString).lastPathComponent
    }
}

// MARK: - Telling them apart

/// One watched tool found running.
/// Una herramienta vigilada que está corriendo.
public struct CLIDetection: Equatable, Sendable {
    public var tool: String
    public var pid: Int32
    public var started: Date
    /// The app it runs in: "Terminal", "iTerm", "Cursor", "Claude"…
    /// La app donde corre: «Terminal», «iTerm», «Cursor», «Claude»…
    public var host: String?
    /// The watched tool that launched it, if any (Supabase run by Claude Code).
    /// La herramienta vigilada que la lanzó, si hay una (Supabase lanzado por Claude Code).
    public var via: String?

    public init(tool: String, pid: Int32, started: Date, host: String? = nil, via: String? = nil) {
        self.tool = tool
        self.pid = pid
        self.started = started
        self.host = host
        self.via = via
    }
}

public enum CLIDetector {
    /// Programs that run someone else's script: the tool is in their arguments.
    /// Programas que ejecutan el script de otro: la herramienta está en sus argumentos.
    static func isInterpreter(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["node", "bun", "deno", "ruby", "perl", "sh", "bash", "zsh"].contains(lower)
            || lower.hasPrefix("python")
    }

    /// Keyturn's own processes, whose `supabase` calls are not the user's.
    /// Los procesos del propio Keyturn, cuyas llamadas a `supabase` no son del usuario.
    static let ownExecutables: Set<String> = ["keyturn", "KeyturnApp"]

    public static func detect(
        in processes: [RunningProcess],
        watching tools: [KnownCLI],
        ignoring ownPID: Int32 = getpid()
    ) -> [CLIDetection] {
        let byPID = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var byName: [String: String] = [:]
        var byPackage: [String: String] = [:]
        for tool in tools {
            for name in tool.executables where byName[name] == nil { byName[name] = tool.id }
            for package in tool.packages where byPackage[package] == nil { byPackage[package] = tool.id }
        }

        var identified: [Int32: String?] = [:]
        func tool(of process: RunningProcess) -> String? {
            if let known = identified[process.pid] { return known }
            let found = identify(process, byName: byName, byPackage: byPackage)
            identified[process.pid] = found
            return found
        }

        return processes.compactMap { process -> CLIDetection? in
            guard process.isMine, process.pid != ownPID, let id = tool(of: process) else { return nil }
            var via: String?
            var host: String?
            var seen: Set<Int32> = [process.pid]
            var next = process.parent
            while next > 1, !seen.contains(next), let ancestor = byPID[next] {
                seen.insert(next)
                if ancestor.pid == ownPID || ownExecutables.contains(basename(ancestor.path)) { return nil }
                if let other = tool(of: ancestor) {
                    // A child of the same tool is part of it, not one more.
                    // Un hijo de la misma herramienta es parte de ella, no una más.
                    if other == id { return nil }
                    if via == nil { via = other }
                } else if host == nil {
                    // A tool can live in a bundle of its own (Claude Code's
                    // `claude.app`); the host is the app around it.
                    // Una herramienta puede vivir en un bundle propio (el
                    // `claude.app` de Claude Code); la app es la que la rodea.
                    host = appName(in: ancestor.path)
                }
                next = ancestor.parent
            }
            return CLIDetection(tool: id, pid: process.pid, started: process.started, host: host, via: via)
        }
    }

    static func identify(_ process: RunningProcess, byName: [String: String], byPackage: [String: String]) -> String? {
        let executable = basename(process.path)
        if let id = byName[executable] { return id }
        // The name it was started by: a native Claude Code lives in
        // `…/claude/versions/2.1.0`, but the shell starts it as `claude`.
        // El nombre con el que se lanzó: un Claude Code nativo vive en
        // `…/claude/versions/2.1.0`, pero el shell lo lanza como `claude`.
        if let first = process.arguments.first, let id = byName[basename(first)] { return id }
        guard isInterpreter(executable) || process.arguments.first.map({ isInterpreter(basename($0)) }) == true else { return nil }

        var arguments = process.arguments.dropFirst()
        while let argument = arguments.first {
            arguments = arguments.dropFirst()
            if argument == "-m", let module = arguments.first { return byName[module] }
            // Inline code (`zsh -c "…"`, `node -e "…"`) is not a script to name.
            // El código en línea (`zsh -c "…"`, `node -e "…"`) no es un script con nombre.
            if ["-c", "-e", "-p", "--eval", "--print"].contains(argument) { return nil }
            if argument.hasPrefix("-") { continue }
            // The script: by its name (`…/bin/firebase`, `gcloud.py`), or by the
            // package it belongs to (`…/node_modules/vercel/dist/index.js`).
            // El script: por su nombre (`…/bin/firebase`, `gcloud.py`), o por el
            // paquete al que pertenece (`…/node_modules/vercel/dist/index.js`).
            let script = basename(argument)
            if let id = byName[script] ?? byName[(script as NSString).deletingPathExtension] { return id }
            if let package = package(in: argument), let id = byPackage[package] { return id }
            return nil
        }
        return nil
    }

    /// The last `node_modules/<package>` in a path, scoped names included.
    /// El último `node_modules/<paquete>` de una ruta, también con ámbito.
    static func package(in path: String) -> String? {
        let parts = path.split(separator: "/").map(String.init)
        guard let index = parts.lastIndex(of: "node_modules"), index + 1 < parts.count else { return nil }
        let name = parts[index + 1]
        if name.hasPrefix("@"), index + 2 < parts.count { return name + "/" + parts[index + 2] }
        return name
    }

    /// "/Applications/Claude.app/Contents/Helpers/x" → "Claude": the outermost app.
    /// «/Applications/Claude.app/Contents/Helpers/x» → «Claude»: la app más externa.
    static func appName(in path: String) -> String? {
        guard let component = path.split(separator: "/").first(where: { $0.hasSuffix(".app") }) else { return nil }
        return String(component.dropLast(4))
    }

    static func basename(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }
}

import Foundation

/// Registers `keyturn mcp` in the AI tools that have their own command for it
/// (Claude Code, Codex), and writes the configuration for the ones edited by hand.
/// Registra `keyturn mcp` en las herramientas de IA que tienen su propia orden
/// para ello (Claude Code, Codex), y escribe la configuración de las que se
/// editan a mano.
public struct AgentClient: Identifiable, Equatable, Sendable {
    public var id: String
    public var title: String
    /// Where the tool usually lives; the login shell's PATH is tried after.
    /// Dónde suele estar la herramienta; después se prueba el PATH del shell.
    var candidates: [String]
    var command: String
    var addArguments: @Sendable (_ keyturn: String) -> [String]

    public static func == (lhs: AgentClient, rhs: AgentClient) -> Bool { lhs.id == rhs.id }

    public static let serverName = MCPServer.name

    public static let claudeCode = AgentClient(
        id: "claude-code",
        title: "Claude Code",
        candidates: ["~/.local/bin/claude", "~/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"],
        command: "claude",
        addArguments: { ["mcp", "add", "--scope", "user", serverName, "--", $0, "mcp"] }
    )

    public static let codex = AgentClient(
        id: "codex",
        title: "Codex",
        candidates: ["/opt/homebrew/bin/codex", "/usr/local/bin/codex", "~/.local/bin/codex"],
        command: "codex",
        addArguments: { ["mcp", "add", serverName, "--", $0, "mcp"] }
    )

    public static let all = [claudeCode, codex]

    /// The command a person would type, quoted for zsh.
    /// La orden que escribiría una persona, entrecomillada para zsh.
    public func commandLine(keyturn: String) -> String {
        ([command] + addArguments(keyturn)).map(shellQuoted).joined(separator: " ")
    }

    /// The tool's executable, or nil when it is not installed.
    /// El ejecutable de la herramienta, o nil si no está instalada.
    public func locate() -> String? {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let expanded = candidates.map { $0.hasPrefix("~/") ? home + $0.dropFirst() : $0 }
        if let found = expanded.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) { return found }
        guard let shell = try? ProcessRunner.run("/bin/zsh", ["-lc", "command -v \(command)"], timeout: 10, waitingFor: "the shell"),
              shell.status == 0
        else { return nil }
        let path = shell.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        return path.hasPrefix("/") && FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    /// Whether the tool already has a server called "keyturn".
    /// Si la herramienta ya tiene un servidor llamado «keyturn».
    public func isInstalled(executable: String) -> Bool {
        let result = try? ProcessRunner.run(executable, ["mcp", "get", Self.serverName], environment: Self.environment, timeout: 30, waitingFor: title)
        return result?.status == 0
    }

    /// Adds the server, replacing an older entry that may point elsewhere.
    /// Añade el servidor, sustituyendo una entrada vieja que apunte a otro sitio.
    public func install(executable: String, keyturn: String) throws {
        if isInstalled(executable: executable) { try remove(executable: executable) }
        let result = try ProcessRunner.run(executable, addArguments(keyturn), environment: Self.environment, timeout: 30, waitingFor: title)
        guard result.status == 0 else { throw Self.failure(result, title) }
    }

    public func remove(executable: String) throws {
        let result = try ProcessRunner.run(executable, ["mcp", "remove", Self.serverName], environment: Self.environment, timeout: 30, waitingFor: title)
        guard result.status == 0 else { throw Self.failure(result, title) }
    }

    /// For Claude Desktop, Cursor, Windsurf and the rest edited by hand.
    /// Para Claude Desktop, Cursor, Windsurf y el resto que se editan a mano.
    public static func jsonConfiguration(keyturn: String) -> String {
        let object: [String: Any] = ["mcpServers": [serverName: ["command": keyturn, "args": ["mcp"]]]]
        let data = (try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    /// An app opened from Finder has a bare PATH, and these tools are scripts
    /// that look for `node` and friends on it.
    /// Una app abierta desde el Finder tiene un PATH pelado, y estas
    /// herramientas son scripts que buscan `node` y compañía en él.
    static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let extra = ["/opt/homebrew/bin", "/usr/local/bin", home + "/.local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin"]
        let current = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
        environment["PATH"] = (current + extra.filter { !current.contains($0) }).joined(separator: ":")
        return environment
    }

    private static func failure(_ result: ProcessOutput, _ title: String) -> SwitchError {
        let detail = [result.stderr, result.stdout]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? "exit \(result.status)"
        return .cliFailed("\(title): \(detail)")
    }
}

/// Quotes a word for zsh only when it needs it. / Entrecomilla una palabra para zsh solo si hace falta.
func shellQuoted(_ word: String) -> String {
    let safe = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./=:@%+"))
    if !word.isEmpty, word.unicodeScalars.allSatisfy(safe.contains) { return word }
    return "'" + word.replacingOccurrences(of: "'", with: #"'\''"#) + "'"
}

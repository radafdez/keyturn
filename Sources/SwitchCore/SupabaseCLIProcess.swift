import Foundation

/// The real `supabase` binary.
public struct SupabaseCLIProcess: SupabaseCLI {
    public let executable: String

    public init(executable: String) {
        self.executable = executable
    }

    /// An app launched from Finder does not inherit the shell's PATH, so
    /// Homebrew's folder has to be looked up by hand.
    /// Una app abierta desde el Finder no hereda el PATH del shell, así que la
    /// carpeta de Homebrew hay que buscarla a mano.
    public static func locate() throws -> SupabaseCLIProcess {
        let candidates = ["/opt/homebrew/bin/supabase", "/usr/local/bin/supabase"]
        if let found = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) {
            return SupabaseCLIProcess(executable: found)
        }
        if let shell = try? ProcessRunner.run(
            "/bin/zsh", ["-lc", "command -v supabase"], timeout: 10, waitingFor: tr("the shell", "el shell")
        ), shell.status == 0 {
            let path = shell.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            if path.hasPrefix("/"), FileManager.default.isExecutableFile(atPath: path) {
                return SupabaseCLIProcess(executable: path)
            }
        }
        throw SwitchError.cliNotFound
    }

    public func login(token: String) throws {
        // The CLI takes the token from piped stdin, checks its shape and writes
        // it to its own Keychain entry — the same code path as a normal login,
        // minus the browser.
        // El CLI coge el token de stdin, comprueba su forma y lo escribe en su
        // propia entrada del Llavero: el mismo camino que un login normal, sin
        // el navegador.
        let result = try ProcessRunner.run(
            executable, ["login"],
            stdin: token + "\n",
            environment: environment(token: nil),
            timeout: 60,
            waitingFor: "`supabase login`"
        )
        guard result.status == 0 else { throw Self.failure(result) }
    }

    public func organizations(token: String?) throws -> [Organization] {
        struct Payload: Decodable {
            struct Row: Decodable { var id: String; var name: String? }
            var organizations: [Row]
        }
        let payload: Payload = try json(["orgs", "list"], token: token)
        return payload.organizations.map { Organization(id: $0.id, name: $0.name ?? $0.id) }
    }

    public func projects(token: String?) throws -> [Project] {
        struct Payload: Decodable {
            struct Row: Decodable { var id: String?; var ref: String?; var name: String?; var region: String? }
            var projects: [Row]
        }
        let payload: Payload = try json(["projects", "list"], token: token)
        return payload.projects.compactMap { row in
            guard let ref = row.ref ?? row.id else { return nil }
            return Project(ref: ref, name: row.name ?? ref, region: row.region ?? "")
        }
    }

    private func json<T: Decodable>(_ command: [String], token: String?) throws -> T {
        let result = try ProcessRunner.run(
            executable, command + ["--output-format", "json"],
            environment: environment(token: token),
            timeout: 45,
            waitingFor: "`supabase \(command.joined(separator: " "))`"
        )
        guard result.status == 0 else { throw Self.failure(result) }
        guard let start = result.stdout.firstIndex(of: "{"),
              let value = try? JSONDecoder().decode(T.self, from: Data(result.stdout[start...].utf8))
        else {
            throw SwitchError.cliFailed(tr("unexpected answer from `supabase \(command.joined(separator: " "))`", "respuesta inesperada de `supabase \(command.joined(separator: " "))`"))
        }
        return value
    }

    /// An inherited SUPABASE_ACCESS_TOKEN would win over everything else —
    /// over the piped token on login, and over the stored login on the rest.
    /// Un SUPABASE_ACCESS_TOKEN heredado ganaría a todo lo demás: al token por
    /// stdin en el login y a la sesión guardada en el resto.
    private func environment(token: String?) -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["SUPABASE_ACCESS_TOKEN"] = token
        return environment
    }

    static func failure(_ result: ProcessOutput) -> SwitchError {
        let text = (result.stderr + "\n" + result.stdout)
        let lowered = text.lowercased()
        if lowered.contains("unauthorized") || lowered.contains("401") || lowered.contains("invalid access token") {
            return .rejectedToken
        }
        if lowered.contains("access token not provided") || lowered.contains("supabase login") {
            return .noCLISession
        }
        return .cliFailed(SecurityToolKeychain.firstLine(text) ?? SecurityToolKeychain.exitCode(result.status))
    }
}

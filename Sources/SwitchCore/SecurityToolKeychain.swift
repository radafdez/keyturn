import Foundation

/// The login Keychain, through `/usr/bin/security`.
///
/// Why the tool and not the Security framework: an entry remembers which
/// program created it. This app is signed ad hoc, so its signature changes on
/// every rebuild and macOS would ask for the password again each time. Entries
/// created by `security` stay readable by `security`, rebuild after rebuild.
///
/// El Llavero de inicio de sesión, a través de `/usr/bin/security`.
///
/// Por qué la herramienta y no el framework Security: una entrada recuerda qué
/// programa la creó. Esta app va firmada ad hoc, su firma cambia en cada
/// compilación y macOS volvería a pedir la contraseña cada vez. Las entradas
/// creadas por `security` las sigue leyendo `security`, compiles lo que compiles.
public struct SecurityToolKeychain: SecretStore {
    static let tool = "/usr/bin/security"
    /// `security` exits with this when the entry does not exist.
    /// `security` sale con esto cuando la entrada no existe.
    static let notFound: Int32 = 44

    public init() {}

    public func read(_ slot: KeychainSlot) throws -> String? {
        // Reading the CLI's own entry makes macOS ask the user, and the tool
        // waits for the answer: give a person time to read the dialog.
        // Leer la entrada del propio CLI hace que macOS pregunte al usuario, y la
        // herramienta espera la respuesta: hay que dar tiempo a leer el diálogo.
        let foreign = slot.service != KeychainSlot.ownService
        let result = try ProcessRunner.run(
            Self.tool,
            ["find-generic-password", "-s", slot.service, "-a", slot.account, "-w"],
            timeout: foreign ? 120 : 15,
            waitingFor: foreign
                ? tr("you to allow access in the Keychain dialog", "que autorices el acceso en el aviso del Llavero")
                : Self.keychainName
        )
        if result.status == Self.notFound { return nil }
        guard result.status == 0 else {
            // 51 / "User interaction is not allowed" / a denied dialog all land here.
            // Un diálogo denegado o cancelado también acaba aquí.
            throw SwitchError.keychain(Self.firstLine(result.stderr) ?? Self.exitCode(result.status))
        }
        let value = KeyringCodec.decode(result.stdout)
        return value.isEmpty ? nil : value
    }

    public func write(_ secret: String, to slot: KeychainSlot) throws {
        // `security -i` reads its command from stdin, so the secret never shows
        // up in the process list. Base64 keeps it free of quotes and spaces.
        // `security -i` lee la orden por stdin, así que el secreto nunca aparece
        // en la lista de procesos. En base64 no lleva comillas ni espacios.
        let command = "add-generic-password -U -s \(Self.quoted(slot.service)) -a \(Self.quoted(slot.account)) "
            + "-l \(Self.quoted(KeychainSlot.ownService)) -w \(KeyringCodec.encode(secret))\n"
        let result = try ProcessRunner.run(Self.tool, ["-i"], stdin: command, timeout: 15, waitingFor: Self.keychainName)

        // The interactive mode reports success even when the command failed:
        // the only proof is reading the value back.
        // El modo interactivo dice que todo fue bien aunque la orden falle: la
        // única prueba es volver a leer el valor.
        guard try read(slot) == secret else {
            throw SwitchError.keychain(Self.firstLine(result.stderr) ?? tr("the token was not saved", "no se guardó el token"))
        }
    }

    public func delete(_ slot: KeychainSlot) throws {
        let result = try ProcessRunner.run(
            Self.tool,
            ["delete-generic-password", "-s", slot.service, "-a", slot.account],
            timeout: 15,
            waitingFor: Self.keychainName
        )
        guard result.status == 0 || result.status == Self.notFound else {
            throw SwitchError.keychain(Self.firstLine(result.stderr) ?? Self.exitCode(result.status))
        }
    }

    public func modificationStamp(_ slot: KeychainSlot) -> String? {
        // Without `-w` or `-g` the tool prints attributes only: no prompt, ever.
        // Sin `-w` ni `-g` la herramienta solo imprime atributos: nunca pregunta.
        guard
            let result = try? ProcessRunner.run(
                Self.tool,
                ["find-generic-password", "-s", slot.service, "-a", slot.account],
                timeout: 10,
                waitingFor: Self.keychainName
            ),
            result.status == 0
        else { return nil }
        return Self.modificationDate(in: result.stdout) ?? "present"
    }

    /// Pulls the value out of a line like
    /// `    "mdat"<timedate>=0x3230…  "20261115081443Z\000"`.
    static func modificationDate(in attributes: String) -> String? {
        for line in attributes.split(separator: "\n") where line.contains("\"mdat\"") {
            guard let equals = line.firstIndex(of: "=") else { continue }
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
            if value.isEmpty || value == "<NULL>" { return nil }
            return value
        }
        return nil
    }

    static var keychainName: String { tr("the Keychain", "el Llavero") }

    static func exitCode(_ status: Int32) -> String { tr("exit code \(status)", "código \(status)") }

    static func quoted(_ text: String) -> String {
        "\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    static func firstLine(_ text: String) -> String? {
        text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.first { !$0.isEmpty }
    }
}

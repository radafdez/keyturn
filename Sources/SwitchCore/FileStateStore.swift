import Foundation

/// The list of accounts, as JSON. No token is ever written here.
/// La lista de cuentas, en JSON. Aquí nunca se escribe un token.
public struct FileStateStore: StateStore {
    public let url: URL

    public init(url: URL) {
        self.url = url
    }

    public static func standard() -> FileStateStore {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return FileStateStore(url: support.appendingPathComponent("SupabaseSwitch/accounts.json"))
    }

    public func load() throws -> SwitchState {
        guard FileManager.default.fileExists(atPath: url.path) else { return SwitchState() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(SwitchState.self, from: Data(contentsOf: url))
    }

    public func save(_ state: SwitchState) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(state).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}

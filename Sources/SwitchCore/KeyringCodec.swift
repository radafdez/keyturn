import Foundation

/// The Supabase CLI (and go-keyring before it) may wrap a secret as
/// `go-keyring-base64:<base64>`. This app stores its own secrets the same way,
/// so no secret ever needs shell quoting.
/// El CLI de Supabase (y antes go-keyring) puede envolver un secreto como
/// `go-keyring-base64:<base64>`. Esta app guarda los suyos igual, y así ningún
/// secreto necesita comillas de shell.
public enum KeyringCodec {
    static let prefix = "go-keyring-base64:"

    public static func decode(_ stored: String) -> String {
        let trimmed = stored.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(prefix) else { return trimmed }
        let payload = String(trimmed.dropFirst(prefix.count))
        guard let data = Data(base64Encoded: payload), let text = String(data: data, encoding: .utf8) else {
            return trimmed
        }
        return text
    }

    public static func encode(_ secret: String) -> String {
        prefix + Data(secret.utf8).base64EncodedString()
    }
}

public enum AccessToken {
    /// Same shape the CLI accepts: `sbp_` or `sbp_oauth_` plus 40 hex digits.
    /// La misma forma que acepta el CLI: `sbp_` o `sbp_oauth_` más 40 hexadecimales.
    public static func isValid(_ token: String) -> Bool {
        token.range(of: "^sbp_(oauth_)?[a-f0-9]{40}$", options: .regularExpression) != nil
    }
}

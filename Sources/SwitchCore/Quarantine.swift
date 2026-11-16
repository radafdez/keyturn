import Darwin
import Foundation

/// Homebrew quarantines every file of a cask, and macOS kills a quarantined
/// command-line tool that Apple has not notarized, with no dialog to approve
/// it. Approving the app with "Open Anyway" does not cover `sbswitch` inside
/// it. So once the app runs, which means you approved it, it lifts the
/// quarantine from its own bundle: `sbswitch` and the MCP server then work,
/// as they do in copies built from source or installed by Sparkle.
///
/// Homebrew pone en cuarentena cada fichero de un cask, y macOS mata sin
/// preguntar una herramienta de terminal en cuarentena que Apple no ha
/// notarizado. Aprobar la app con «Abrir igualmente» no cubre el `sbswitch` que
/// lleva dentro. Así que, cuando la app ya corre, que es señal de que la
/// aprobaste, quita la cuarentena de su propio bundle: `sbswitch` y el servidor
/// MCP funcionan entonces como en una copia compilada o instalada por Sparkle.
public enum Quarantine {
    public static let attribute = "com.apple.quarantine"

    /// Removes the attribute from the bundle and everything in it, without
    /// following symlinks. Returns how many files had it. / Quita el atributo
    /// del bundle y de todo lo que contiene, sin seguir enlaces. Devuelve
    /// cuántos ficheros lo tenían.
    @discardableResult
    public static func release(bundle: URL) -> Int {
        guard bundle.pathExtension == "app", isQuarantined(bundle) || containsQuarantined(bundle) else { return 0 }
        var released = 0
        var paths = [bundle.path]
        if let files = FileManager.default.enumerator(atPath: bundle.path) {
            for case let file as String in files {
                paths.append(bundle.appendingPathComponent(file).path)
            }
        }
        for path in paths where removexattr(path, attribute, XATTR_NOFOLLOW) == 0 {
            released += 1
        }
        return released
    }

    public static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// Homebrew marks the files inside even when the bundle itself has lost
    /// the mark. / Homebrew marca los ficheros de dentro aunque el bundle haya
    /// perdido la marca.
    private static func containsQuarantined(_ bundle: URL) -> Bool {
        isQuarantined(bundle.appendingPathComponent("Contents/MacOS/sbswitch"))
    }
}

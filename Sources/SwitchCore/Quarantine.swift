import Darwin
import Foundation

/// Homebrew quarantines every file of a cask, and macOS kills a quarantined
/// command-line tool that Apple has not notarized, with no dialog to approve
/// it: approving the app does not cover `sbswitch` inside it. The app cannot
/// lift the mark itself either, because macOS does not let a quarantined
/// process remove it. So the app only notices, and tells you the command that
/// does it. Copies installed by Sparkle and builds from source never have it.
///
/// Homebrew pone en cuarentena cada fichero de un cask, y macOS mata sin
/// preguntar una herramienta de terminal en cuarentena que Apple no ha
/// notarizado: aprobar la app no cubre el `sbswitch` que lleva dentro. La app
/// tampoco puede quitar la marca, porque macOS no deja que un proceso en
/// cuarentena la quite. Así que la app solo lo detecta y te da la orden que lo
/// hace. Las copias que instala Sparkle y las compiladas nunca la llevan.
public enum Quarantine {
    public static let attribute = "com.apple.quarantine"

    public static func isQuarantined(_ url: URL) -> Bool {
        getxattr(url.path, attribute, nil, 0, 0, XATTR_NOFOLLOW) >= 0
    }

    /// Whether macOS will stop the `sbswitch` inside this app. / Si macOS
    /// parará el `sbswitch` de esta app.
    public static func blocksCommandLine(bundle: URL) -> Bool {
        bundle.pathExtension == "app" && isQuarantined(bundle.appendingPathComponent("Contents/MacOS/sbswitch"))
    }

    /// The Terminal command that lifts the mark from the whole app. / La orden
    /// de Terminal que quita la marca de toda la app.
    public static func releaseCommand(bundle: URL) -> String {
        "xattr -dr \(attribute) '\(bundle.path.replacingOccurrences(of: "'", with: "'\\''"))'"
    }
}

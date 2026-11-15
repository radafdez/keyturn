import Foundation

/// The two languages the app speaks. English unless the first preferred
/// language of the system is Spanish; `SUPABASE_SWITCH_LANG=en|es` overrides it.
///
/// Texts sit next to the code that shows them, as `tr("English", "Español")`.
/// With two languages that is easier to keep in step than a table of keys.
///
/// Los dos idiomas de la app. Inglés, salvo que el primer idioma preferido del
/// sistema sea el español; `SUPABASE_SWITCH_LANG=en|es` lo fuerza.
public enum AppLanguage: String, Sendable {
    case english = "en"
    case spanish = "es"

    public nonisolated(unsafe) static var current: AppLanguage = detect()

    /// What the system (or `SUPABASE_SWITCH_LANG`) asks for, whatever the app chose.
    /// Lo que pide el sistema (o `SUPABASE_SWITCH_LANG`), elija lo que elija la app.
    public static var system: AppLanguage { detect() }

    static func detect(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        preferred: [String] = Locale.preferredLanguages
    ) -> AppLanguage {
        if let forced = environment["SUPABASE_SWITCH_LANG"].flatMap({ AppLanguage(rawValue: $0.lowercased()) }) {
            return forced
        }
        return preferred.first?.lowercased().hasPrefix("es") == true ? .spanish : .english
    }

    public var locale: Locale { Locale(identifier: rawValue) }
}

/// The text in the current language.
/// El texto en el idioma actual.
public func tr(_ english: String, _ spanish: String) -> String {
    AppLanguage.current == .spanish ? spanish : english
}

/// "2 hours ago" / "hace 2 horas".
public func relativeTime(_ date: Date, now: Date = Date()) -> String {
    let formatter = RelativeDateTimeFormatter()
    formatter.locale = AppLanguage.current.locale
    formatter.unitsStyle = .full
    if now.timeIntervalSince(date) < 60 { return tr("just now", "ahora mismo") }
    return formatter.localizedString(for: date, relativeTo: now)
}

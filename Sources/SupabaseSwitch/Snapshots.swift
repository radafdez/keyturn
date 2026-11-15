import AppKit
import SwiftUI
import SwitchCore

/// Draws the menu and every settings pane, with the demo accounts, into PNGs:
/// the screenshots of the README.
///
///     SUPABASE_SWITCH_SNAPSHOTS=docs "dist/Supabase Switch.app/Contents/MacOS/SupabaseSwitch"
///
/// Dibuja el menú y cada panel de ajustes, con las cuentas de la demo, en PNG:
/// las capturas del README.
@MainActor
enum Snapshots {
    static func render(into folder: URL) async {
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let model = AppModel()
        await model.settle()
        model.checkAgents()

        for (language, suffix) in [(AppModel.LanguageChoice.english, ""), (.spanish, "-es")] {
            model.setLanguage(language)
            await shoot(MenuView(model: model), size: nil, dark: false, to: folder.appendingPathComponent("menu-light\(suffix).png"))
            await shoot(MenuView(model: model), size: nil, dark: true, to: folder.appendingPathComponent("menu-dark\(suffix).png"))
            for pane in SettingsView.Pane.allCases {
                await shoot(SettingsView(model: model, pane: pane), size: NSSize(width: 760, height: 540), dark: pane == .about,
                            to: folder.appendingPathComponent("settings-\(pane.rawValue)\(suffix).png"))
            }
        }
        model.setLanguage(.system)
    }

    private static func shoot<V: View>(_ view: V, size: NSSize?, dark: Bool, to url: URL) async {
        // The window draws its own background; a picture of the view alone needs one.
        // La ventana pinta su propio fondo; la foto de la vista sola necesita uno.
        let host = NSHostingView(rootView: view.background(Color(nsColor: .windowBackgroundColor)))
        let frame = NSRect(origin: NSPoint(x: -20_000, y: 0), size: size ?? host.fittingSize)
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window.isReleasedWhenClosed = false
        window.contentView = host
        window.orderFrontRegardless()
        // Lists and forms fill in on the next passes of the run loop.
        // Las listas y los formularios se rellenan en las siguientes vueltas del bucle.
        try? await Task.sleep(nanoseconds: 600_000_000)
        host.layoutSubtreeIfNeeded()
        if size == nil { window.setContentSize(host.fittingSize) }
        try? await Task.sleep(nanoseconds: 200_000_000)
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        window.close()
    }
}

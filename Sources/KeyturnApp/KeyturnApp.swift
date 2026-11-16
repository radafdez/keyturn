import AppKit
import SwiftUI
import SwitchCore

@main
struct Keyturn: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    // Started with the app, so a scheduled check does not wait for a window.
    // Arranca con la app, para que una comprobación programada no espere a una ventana.
    @StateObject private var updater = Updater.shared

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            if let icon = MenuBarIcon.image {
                Image(nsImage: icon)
            } else {
                Image(systemName: "bolt.fill")
            }
            Text(model.menuBarTitle)
        }
        .menuBarExtraStyle(.window)

        Window(tr("Keyturn Settings", "Ajustes de Keyturn"), id: SettingsView.windowID) {
            SettingsView(model: model)
        }
        .defaultSize(width: 760, height: 540)
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when launched outside the bundle (`swift run`).
        // Sin icono en el Dock, también si se lanza fuera del bundle.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.editMenu()
        if let folder = ProcessInfo.processInfo.environment["KEYTURN_SNAPSHOTS"] {
            Task { @MainActor in
                await Snapshots.render(into: URL(fileURLWithPath: folder))
                NSApp.terminate(nil)
            }
        }
    }

    /// An app without a menu bar of its own still needs an Edit menu: it is
    /// what makes ⌘V work in the token field.
    /// Una app sin barra de menús propia sigue necesitando el menú Edición: es
    /// lo que hace que ⌘V funcione en el campo del token.
    private static func editMenu() -> NSMenu {
        let edit = NSMenu(title: "Edición")
        edit.addItem(withTitle: "Deshacer", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cortar", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copiar", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Pegar", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Seleccionar todo", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let item = NSMenuItem()
        item.submenu = edit
        let main = NSMenu()
        main.addItem(item)
        return main
    }
}

/// The brand symbol for the menu bar, drawn by `scripts/make-icon.swift`. It is a
/// template, so macOS inks it black or white to match the bar. A build run with
/// `swift run` has no bundle and falls back to a bolt.
/// El símbolo de la marca para la barra de menús, que dibuja
/// `scripts/make-icon.swift`. Es una plantilla, así que macOS lo pinta de negro o
/// de blanco según la barra. Una compilación con `swift run` no tiene bundle y
/// usa un rayo.
enum MenuBarIcon {
    static let image: NSImage? = {
        guard let image = Bundle.main.image(forResource: "MenuBarIcon") else { return nil }
        image.isTemplate = true
        image.accessibilityDescription = "Keyturn"
        return image
    }()
}

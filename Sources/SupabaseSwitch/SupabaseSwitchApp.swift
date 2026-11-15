import AppKit
import SwiftUI

@main
struct SupabaseSwitchApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra {
            MenuView(model: model)
        } label: {
            Image(systemName: "bolt.fill")
            Text(model.menuBarTitle)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // No Dock icon, also when launched outside the bundle (`swift run`).
        // Sin icono en el Dock, también si se lanza fuera del bundle.
        NSApp.setActivationPolicy(.accessory)
        NSApp.mainMenu = Self.editMenu()
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

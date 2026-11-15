// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SupabaseSwitch",
    platforms: [.macOS(.v13)],
    targets: [
        // Everything that is not UI: accounts, Keychain, and the Supabase CLI.
        // Todo lo que no es interfaz: cuentas, Llavero, y el CLI de Supabase.
        .target(name: "SwitchCore"),
        // The menu bar app. / La app de la barra de menús.
        .executableTarget(name: "SupabaseSwitch", dependencies: ["SwitchCore"]),
        // The same switch from a terminal. / El mismo cambio desde una terminal.
        .executableTarget(name: "sbswitch", dependencies: ["SwitchCore"]),
        .testTarget(name: "SwitchCoreTests", dependencies: ["SwitchCore"]),
    ]
)

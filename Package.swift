// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SupabaseSwitch",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Updates for the app, signed with our EdDSA key. Pinned: a new Sparkle is a
        // deliberate change. / Actualizaciones de la app, firmadas con nuestra clave
        // EdDSA. Fijado: un Sparkle nuevo es un cambio a propósito.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Everything that is not UI: accounts, Keychain, and the Supabase CLI.
        // Todo lo que no es interfaz: cuentas, Llavero, y el CLI de Supabase.
        .target(name: "SwitchCore"),
        // The menu bar app. / La app de la barra de menús.
        .executableTarget(
            name: "SupabaseSwitch",
            dependencies: ["SwitchCore", .product(name: "Sparkle", package: "Sparkle")]
        ),
        // The same switch from a terminal. / El mismo cambio desde una terminal.
        .executableTarget(name: "sbswitch", dependencies: ["SwitchCore"]),
        .testTarget(name: "SwitchCoreTests", dependencies: ["SwitchCore"]),
    ]
)

import Darwin
import Foundation
import Testing
@testable import SwitchCore

@Suite struct QuarantineTests {
    /// A bundle laid out like the app, every file marked as Homebrew marks it.
    /// Un bundle con la forma de la app, cada fichero marcado como lo marca Homebrew.
    private func quarantinedBundle() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Supabase Switch.app")
        let macOS = root.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        for name in ["SupabaseSwitch", "sbswitch"] {
            try Data("x".utf8).write(to: macOS.appendingPathComponent(name))
        }
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("Contents/link"),
                                                   withDestinationURL: macOS.appendingPathComponent("sbswitch"))
        let value = Array("0181;6afa8cdd;Homebrew Cask;".utf8)
        for path in [root.path, macOS.path, macOS.appendingPathComponent("SupabaseSwitch").path,
                     macOS.appendingPathComponent("sbswitch").path] {
            #expect(setxattr(path, Quarantine.attribute, value, value.count, 0, XATTR_NOFOLLOW) == 0)
        }
        return root
    }

    @Test func itLiftsTheQuarantineFromTheWholeBundle() throws {
        let bundle = try quarantinedBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }

        #expect(Quarantine.release(bundle: bundle) == 4)
        #expect(!Quarantine.isQuarantined(bundle))
        #expect(!Quarantine.isQuarantined(bundle.appendingPathComponent("Contents/MacOS/sbswitch")))
        #expect(Quarantine.release(bundle: bundle) == 0)
    }

    @Test func itAlsoActsWhenOnlyTheFilesInsideAreMarked() throws {
        let bundle = try quarantinedBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }
        removexattr(bundle.path, Quarantine.attribute, XATTR_NOFOLLOW)

        #expect(Quarantine.release(bundle: bundle) == 3)
        #expect(!Quarantine.isQuarantined(bundle.appendingPathComponent("Contents/MacOS/sbswitch")))
    }

    @Test func itLeavesAnythingThatIsNotAnAppAlone() throws {
        let bundle = try quarantinedBundle()
        defer { try? FileManager.default.removeItem(at: bundle.deletingLastPathComponent()) }

        #expect(Quarantine.release(bundle: bundle.appendingPathComponent("Contents")) == 0)
        #expect(Quarantine.isQuarantined(bundle.appendingPathComponent("Contents/MacOS/sbswitch")))
    }
}

import Darwin
import Foundation
import Testing
@testable import SwitchCore

@Suite struct QuarantineTests {
    /// A bundle laid out like the app, with `keyturn` marked as Homebrew marks it.
    /// Un bundle con la forma de la app, con `keyturn` marcado como lo marca Homebrew.
    private func bundle(quarantined: Bool) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathComponent("Keyturn.app")
        let macOS = root.appendingPathComponent("Contents/MacOS")
        try FileManager.default.createDirectory(at: macOS, withIntermediateDirectories: true)
        let keyturn = macOS.appendingPathComponent("keyturn")
        try Data("x".utf8).write(to: keyturn)
        if quarantined {
            let value = Array("0181;6afa8cdd;Homebrew Cask;".utf8)
            #expect(setxattr(keyturn.path, Quarantine.attribute, value, value.count, 0, XATTR_NOFOLLOW) == 0)
        }
        return root
    }

    @Test func aQuarantinedKeyturnIsNoticed() throws {
        let app = try bundle(quarantined: true)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        #expect(Quarantine.blocksCommandLine(bundle: app))
    }

    @Test func aCleanCopyIsLeftAlone() throws {
        let app = try bundle(quarantined: false)
        defer { try? FileManager.default.removeItem(at: app.deletingLastPathComponent()) }
        #expect(!Quarantine.blocksCommandLine(bundle: app))
        #expect(!Quarantine.blocksCommandLine(bundle: app.appendingPathComponent("Contents")))
    }

    @Test func theCommandQuotesThePath() {
        let command = Quarantine.releaseCommand(bundle: URL(fileURLWithPath: "/Applications/Rob's Keyturn.app"))
        #expect(command == #"xattr -dr com.apple.quarantine '/Applications/Rob'\''s Keyturn.app'"#)
    }
}

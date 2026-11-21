import Foundation
import Testing
@testable import SwitchCore

private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
private func at(_ minutes: Double) -> Date { t0.addingTimeInterval(minutes * 60) }

private let terminal = RunningProcess(pid: 10, parent: 1, started: at(0), path: "/System/Applications/Utilities/Terminal.app/Contents/MacOS/Terminal")
private let login = RunningProcess(pid: 11, parent: 10, started: at(0), path: "/usr/bin/login", isMine: false)
private let shell = RunningProcess(pid: 12, parent: 11, started: at(0), path: "/bin/zsh", arguments: ["-zsh"])

private func detect(_ processes: [RunningProcess], extra: [String] = [], own: Int32 = 99_999) -> [CLIDetection] {
    CLIDetector.detect(in: processes, watching: KnownCLI.watched(adding: extra), ignoring: own)
}

@Suite struct CLIDetectorTests {
    @Test func aToolIsFoundByItsExecutableAndTheAppItRunsIn() {
        let supabase = RunningProcess(pid: 20, parent: 12, started: at(1), path: "/opt/homebrew/Cellar/supabase/2.1/bin/supabase")
        let found = detect([terminal, login, shell, supabase])
        #expect(found == [CLIDetection(tool: "supabase", pid: 20, started: at(1), host: "Terminal")])
    }

    @Test func aNativeClaudeCodeIsFoundByTheNameItWasStartedWith() {
        let claude = RunningProcess(pid: 20, parent: 12, started: at(1), path: "/Users/me/.local/share/claude/versions/2.1.0",
                                    arguments: ["claude", "--resume"])
        #expect(detect([terminal, login, shell, claude]).map(\.tool) == ["claude"])
    }

    @Test func toolsOnNodeAreFoundByTheirScriptOrTheirPackage() {
        let firebase = RunningProcess(pid: 20, parent: 12, started: at(1), path: "/opt/homebrew/bin/node",
                                      arguments: ["node", "/opt/homebrew/bin/firebase", "emulators:start"])
        let vercel = RunningProcess(pid: 21, parent: 12, started: at(1), path: "/opt/homebrew/bin/node",
                                    arguments: ["node", "--no-warnings", "/usr/local/lib/node_modules/vercel/dist/index.js", "dev"])
        let gemini = RunningProcess(pid: 22, parent: 12, started: at(1), path: "/opt/homebrew/bin/node",
                                    arguments: ["node", "/x/node_modules/@google/gemini-cli/dist/index.js"])
        let gcloud = RunningProcess(pid: 23, parent: 12, started: at(1), path: "/usr/bin/python3",
                                    arguments: ["python3", "-S", "/sdk/lib/gcloud.py", "auth"])
        let azure = RunningProcess(pid: 24, parent: 12, started: at(1), path: "/opt/homebrew/bin/python3.12",
                                   arguments: ["python3", "-Im", "-m", "azure.cli", "login"])
        let plainNode = RunningProcess(pid: 25, parent: 12, started: at(1), path: "/opt/homebrew/bin/node",
                                       arguments: ["node", "server.js"])
        let found = detect([terminal, login, shell, firebase, vercel, gemini, gcloud, azure, plainNode])
        #expect(found.map(\.tool) == ["firebase", "vercel", "gemini", "gcloud", "az"])
    }

    @Test func childrenOfTheSameToolCountOnceAndOthersSayWhoLaunchedThem() {
        let claude = RunningProcess(pid: 20, parent: 12, started: at(1), path: "/usr/local/bin/claude")
        let subClaude = RunningProcess(pid: 21, parent: 20, started: at(2), path: "/usr/local/bin/claude")
        let shellOfClaude = RunningProcess(pid: 22, parent: 20, started: at(2), path: "/bin/zsh", arguments: ["/bin/zsh", "-c", "supabase db push"])
        let supabase = RunningProcess(pid: 23, parent: 22, started: at(3), path: "/opt/homebrew/bin/supabase")
        let found = detect([terminal, login, shell, claude, subClaude, shellOfClaude, supabase])
        #expect(found == [
            CLIDetection(tool: "claude", pid: 20, started: at(1), host: "Terminal"),
            CLIDetection(tool: "supabase", pid: 23, started: at(3), host: "Terminal", via: "claude"),
        ])
    }

    @Test func keyturnsOwnCallsAndOtherUsersAreLeftOut() {
        let app = RunningProcess(pid: 30, parent: 1, started: at(0), path: "/Applications/Keyturn.app/Contents/MacOS/KeyturnApp")
        let ownCall = RunningProcess(pid: 31, parent: 30, started: at(1), path: "/opt/homebrew/bin/supabase")
        let mcp = RunningProcess(pid: 32, parent: 1, started: at(0), path: "/Applications/Keyturn.app/Contents/MacOS/keyturn")
        let agentCall = RunningProcess(pid: 33, parent: 32, started: at(1), path: "/opt/homebrew/bin/supabase")
        let someoneElse = RunningProcess(pid: 34, parent: 1, started: at(1), path: "/opt/homebrew/bin/supabase", isMine: false)
        #expect(detect([app, ownCall, mcp, agentCall, someoneElse], own: 30).isEmpty)
    }

    @Test func theAppIsTheOutermostOneAboveTheTool() {
        let claudeApp = RunningProcess(pid: 40, parent: 1, started: at(0), path: "/Applications/Claude.app/Contents/MacOS/Claude")
        let helper = RunningProcess(pid: 41, parent: 40, started: at(0), path: "/Applications/Claude.app/Contents/Helpers/disclaimer")
        let code = RunningProcess(pid: 42, parent: 41, started: at(1),
                                  path: "/Users/me/Library/Application Support/Claude/claude-code/2.1/x/claude.app/Contents/MacOS/claude")
        #expect(detect([claudeApp, helper, code]) == [CLIDetection(tool: "claude", pid: 42, started: at(1), host: "Claude")])
    }

    @Test func inlineCodeIsNotMistakenForATool() {
        let script = RunningProcess(pid: 20, parent: 12, started: at(1), path: "/bin/zsh",
                                    arguments: ["/bin/zsh", "-c", "node /x/node_modules/vercel/dist/index.js; supabase start"])
        let eval = RunningProcess(pid: 21, parent: 12, started: at(1), path: "/usr/local/bin/node",
                                  arguments: ["node", "-e", "require('/x/node_modules/vercel')"])
        #expect(detect([terminal, login, shell, script, eval]).isEmpty)
    }

    @Test func aToolLaunchedByClaudeCodeInsideTheClaudeAppRunsInClaude() {
        let claudeApp = RunningProcess(pid: 40, parent: 1, started: at(0), path: "/Applications/Claude.app/Contents/MacOS/Claude")
        let code = RunningProcess(pid: 42, parent: 40, started: at(1), path: "/Users/me/x/claude.app/Contents/MacOS/claude")
        let supabase = RunningProcess(pid: 43, parent: 42, started: at(2), path: "/opt/homebrew/bin/supabase")
        #expect(detect([claudeApp, code, supabase]).last == CLIDetection(tool: "supabase", pid: 43, started: at(2), host: "Claude", via: "claude"))
    }

    @Test func theUsersOwnCommandsAreWatchedToo() {
        let tool = RunningProcess(pid: 20, parent: 12, started: at(1), path: "/usr/local/bin/mytool")
        #expect(detect([terminal, login, shell, tool]).isEmpty)
        #expect(detect([terminal, login, shell, tool], extra: [" /usr/local/bin/mytool "]).map(\.tool) == ["mytool"])
        // A name already in the catalog is not added twice.
        // Un nombre que ya está en el catálogo no se añade dos veces.
        #expect(KnownCLI.watched(adding: ["supabase", "vc", "mytool", "mytool"]).count == KnownCLI.catalog.count + 1)
    }

    @Test func packagesAreReadFromNodeModulesPaths() {
        #expect(CLIDetector.package(in: "/a/node_modules/vercel/dist/index.js") == "vercel")
        #expect(CLIDetector.package(in: "/a/node_modules/x/node_modules/@openai/codex/bin/codex.js") == "@openai/codex")
        #expect(CLIDetector.package(in: "/a/b/index.js") == nil)
    }
}

@Suite struct CLITrackerTests {
    private let claude = CLIDetection(tool: "claude", pid: 20, started: at(0), host: "Terminal")
    private let supabase = CLIDetection(tool: "supabase", pid: 21, started: at(5), host: "Terminal", via: "claude")

    @Test func aSessionOpensContinuesAndEndsWhereItWasLastSeen() {
        var activity = CLIActivity()
        #expect(CLITracker.apply([claude], to: &activity, now: at(1)))
        #expect(!CLITracker.apply([claude], to: &activity, now: at(2)))
        #expect(activity.sessions.count == 1)
        #expect(activity.sessions[0].lastSeen == at(2))
        #expect(activity.sessions[0].isRunning)

        #expect(CLITracker.apply([], to: &activity, now: at(3)))
        #expect(activity.sessions[0].ended == at(2))
        #expect(activity.sessions[0].duration(now: at(10)) == 120)
    }

    @Test func aReusedPidIsANewSession() {
        var activity = CLIActivity()
        CLITracker.apply([claude], to: &activity, now: at(1))
        var again = claude
        again.started = at(4)
        CLITracker.apply([again], to: &activity, now: at(5))
        #expect(activity.sessions.count == 2)
        #expect(activity.sessions[0].ended == at(1))
        #expect(activity.sessions[1].isRunning)
    }

    @Test func aToolStillRunningAfterARestartKeepsItsSession() throws {
        let store = MemoryCLIStore()
        let source = FakeProcesses()
        source.list = [RunningProcess(pid: 20, parent: 1, started: at(0), path: "/usr/local/bin/claude")]
        CLIMonitor(source: source, store: store, ownPID: 1).scan(now: at(1))

        let later = CLIMonitor(source: source, store: store, ownPID: 1).scan(now: at(30))
        #expect(later.sessions.count == 1)
        #expect(later.running.map(\.tool) == ["claude"])
        #expect(later.sessions[0].duration(now: at(30)) == 30 * 60)

        source.list = []
        let closed = CLIMonitor(source: source, store: store, ownPID: 1).scan(now: at(60))
        #expect(closed.running.isEmpty)
        #expect(closed.sessions[0].ended == at(30))
    }

    @Test func turningItOffEndsWhatWasRunning() {
        let store = MemoryCLIStore()
        let source = FakeProcesses()
        source.list = [RunningProcess(pid: 20, parent: 1, started: at(0), path: "/usr/local/bin/claude")]
        let monitor = CLIMonitor(source: source, store: store, ownPID: 1)
        monitor.scan(now: at(1))
        let stopped = monitor.stop(now: at(2))
        #expect(stopped.running.isEmpty)
        #expect(store.activity.sessions[0].ended == at(2))
    }

    @Test func extraCommandsAreKeptCleanAndOnDisk() {
        let store = MemoryCLIStore()
        let monitor = CLIMonitor(source: FakeProcesses(), store: store, ownPID: 1)
        monitor.setExtraCommands([" foo ", "/bin/bar", "", "foo"])
        #expect(store.activity.extraCommands == ["foo", "bar"])
        #expect(CLIMonitor(source: FakeProcesses(), store: store, ownPID: 1).extraCommands == ["foo", "bar"])
    }

    @Test func oldFilesWithoutExtraCommandsStillOpen() throws {
        let json = #"{"sessions":[]}"#
        let decoded = try JSONDecoder().decode(CLIActivity.self, from: Data(json.utf8))
        #expect(decoded == CLIActivity())
    }
}

@Suite struct CLISummaryTests {
    @Test func overlappingCopiesCountOnceAndTheWindowClipsSessions() {
        let activity = CLIActivity(sessions: [
            CLISession(tool: "claude", pid: 1, started: at(0), lastSeen: at(60), ended: at(60)),
            CLISession(tool: "claude", pid: 2, started: at(30), lastSeen: at(90), ended: at(90)),
            CLISession(tool: "claude", pid: 3, started: at(120), lastSeen: at(130)),
            CLISession(tool: "gh", pid: 4, started: at(100), lastSeen: at(101), ended: at(101)),
        ])
        let summary = CLIActivitySummary(activity: activity, now: at(130))

        let all = summary.totals(since: .distantPast)
        #expect(all.map(\.tool) == ["claude", "gh"])
        #expect(all[0].active == 100 * 60)
        #expect(all[0].sessions == 3)
        #expect(all[1].active == 60)

        let lastHour = summary.totals(since: at(70))
        #expect(lastHour.first { $0.tool == "claude" }?.active == TimeInterval(30 * 60))
        #expect(lastHour.first { $0.tool == "claude" }?.sessions == 2)

        #expect(summary.running == [RunningCLI(tool: "claude", title: "Claude Code", copies: 1, since: at(120), hosts: [], via: [])])
        #expect(summary.finished().map(\.pid) == [4, 2, 1])
    }

    @Test func durationsReadTheSameInBothLanguages() {
        #expect(durationText(42) == "42 s")
        #expect(durationText(12 * 60 + 5) == "12 min")
        #expect(durationText(65 * 60) == "1 h 05 min")
        #expect(durationText(76 * 3600) == "3 d 4 h")
    }

    @Test func theDemoShowsToolsRunningAndAHistory() {
        let summary = Demo.cliMonitor(now: t0).summary(now: t0)
        #expect(summary.running.map(\.tool) == ["claude", "stripe", "vercel", "supabase"])
        #expect(summary.running.first { $0.tool == "supabase" }?.via == ["Claude Code"])
        #expect(summary.running.first { $0.tool == "vercel" }?.hosts == ["Cursor"])
        #expect(!summary.finished().isEmpty)
    }
}

final class FakeProcesses: ProcessSource, @unchecked Sendable {
    var list: [RunningProcess] = []
    func processes() -> [RunningProcess] { list }
}

final class MemoryCLIStore: CLIActivityStore, @unchecked Sendable {
    var activity = CLIActivity()
    func load() throws -> CLIActivity { activity }
    func save(_ activity: CLIActivity) throws { self.activity = activity }
}

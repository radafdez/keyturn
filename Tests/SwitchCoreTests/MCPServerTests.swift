import Foundation
import Testing
@testable import SwitchCore

/// Talks to the server the way an MCP client does: one JSON line in, one out.
/// Habla con el servidor como lo hace un cliente MCP: una línea JSON entra, otra sale.
private final class Session {
    let world = World()
    let server: MCPServer
    private var nextID = 0

    init() {
        let service = world.service
        server = MCPServer(service: { service })
    }

    func send(_ method: String, _ params: [String: Any] = [:]) throws -> [String: Any] {
        nextID += 1
        let line = MCPServer.encode(["jsonrpc": "2.0", "id": nextID, "method": method, "params": params])
        let reply = try #require(server.handle(line))
        let object = try #require(try JSONSerialization.jsonObject(with: Data(reply.utf8)) as? [String: Any])
        #expect(object["id"] as? Int == nextID)
        return object
    }

    func call(_ tool: String, _ arguments: [String: Any] = [:]) throws -> [String: Any] {
        try #require(try send("tools/call", ["name": tool, "arguments": arguments])["result"] as? [String: Any])
    }

    func initialize(client: String = "claude-code", version: String = "2025-06-18") throws -> [String: Any] {
        let result = try #require(try send("initialize", [
            "protocolVersion": version,
            "capabilities": [String: Any](),
            "clientInfo": ["name": client, "version": "1.0"],
        ])["result"] as? [String: Any])
        #expect(server.handle(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#) == nil)
        return result
    }
}

private func text(_ result: [String: Any]) -> String {
    ((result["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
}

@Suite struct MCPServerTests {
    @Test func theHandshakeNamesTheServerAndKeepsTheClientsName() throws {
        let session = Session()
        let result = try session.initialize()

        #expect(result["protocolVersion"] as? String == "2025-06-18")
        #expect((result["serverInfo"] as? [String: Any])?["name"] as? String == "supabase-switch")
        #expect((result["serverInfo"] as? [String: Any])?["version"] as? String == switchVersion)
        #expect((result["capabilities"] as? [String: Any])?["tools"] != nil)
        #expect((result["instructions"] as? String)?.contains("use_project") == true)
        #expect(session.server.clientName == "claude-code")
    }

    @Test func anUnknownProtocolVersionGetsTheNewest() throws {
        let session = Session()
        let result = try session.initialize(version: "1999-01-01")
        #expect(result["protocolVersion"] as? String == MCPServer.protocolVersions[0])
    }

    @Test func itListsFourToolsAndOnlyTheReadersAreReadOnly() throws {
        let session = Session()
        _ = try session.initialize()
        let tools = try #require((try session.send("tools/list")["result"] as? [String: Any])?["tools"] as? [[String: Any]])

        let names = tools.compactMap { $0["name"] as? String }
        #expect(names == ["list_accounts", "current_account", "use_project", "switch_account"])
        let readOnly = tools.filter { ($0["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool == true }
        #expect(readOnly.compactMap { $0["name"] as? String } == ["list_accounts", "current_account"])
        for tool in tools {
            #expect((tool["inputSchema"] as? [String: Any])?["type"] as? String == "object")
        }
    }

    @Test func listAccountsShowsProjectsAndWhichOneIsInUse() throws {
        let session = Session()
        let acme = try session.world.service.addAccount(token: tokenA)
        _ = try session.world.service.addAccount(token: tokenB)
        try session.world.service.renameProject("acmeprod", in: acme.id, to: "Acme prod")
        try session.world.service.activate(acme.id)
        _ = try session.initialize()

        let result = try session.call("list_accounts")

        #expect(result["isError"] as? Bool == false)
        #expect(text(result).contains("logged in as “Acme”"))
        #expect(text(result).contains("acmeprod  Acme acmeprod — alias “Acme prod”"))
        let structured = try #require(result["structuredContent"] as? [String: Any])
        #expect(structured["cliAccount"] as? String == "Acme")
        let accounts = try #require(structured["accounts"] as? [[String: Any]])
        #expect(accounts.map { $0["inUse"] as? Bool } == [true, false])
    }

    @Test func noTokenEverLeavesTheServer() throws {
        let session = Session()
        let acme = try session.world.service.addAccount(token: tokenA)
        try session.world.service.activate(acme.id)
        _ = try session.initialize()

        var everything = ""
        for tool in ["list_accounts", "current_account"] {
            everything += MCPServer.encode(try session.call(tool))
        }
        everything += MCPServer.encode(try session.call("use_project", ["project": "acmeprod"]))
        #expect(!everything.contains("sbp_"))
    }

    @Test func useProjectSwitchesAndRecordsTheAgent() throws {
        let session = Session()
        let acme = try session.world.service.addAccount(token: tokenA)
        let globex = try session.world.service.addAccount(token: tokenB)
        try session.world.service.activate(acme.id)
        _ = try session.initialize(client: "claude-code")

        let result = try session.call("use_project", ["project": "globexprod"])

        #expect(result["isError"] as? Bool == false)
        #expect(text(result).contains("Switched the Supabase CLI to the account “Globex”"))
        #expect((result["structuredContent"] as? [String: Any])?["switched"] as? Bool == true)
        #expect(try session.world.service.snapshot().activeAccount?.id == globex.id)
        let last = try #require(session.world.store.state.history.last)
        #expect(last.source == .agent)
        #expect(last.client == "claude-code")

        let again = try session.call("use_project", ["project": "globexprod"])
        #expect((again["structuredContent"] as? [String: Any])?["switched"] as? Bool == false)
        #expect(text(again).contains("already"))
    }

    @Test func switchAccountWorksByName() throws {
        let session = Session()
        _ = try session.world.service.addAccount(token: tokenA)
        let globex = try session.world.service.addAccount(token: tokenB)
        _ = try session.initialize(client: "cursor")

        let result = try session.call("switch_account", ["account": "glob"])

        #expect(result["isError"] as? Bool == false)
        #expect(try session.world.service.snapshot().activeAccount?.id == globex.id)
        #expect(session.world.store.state.history.last?.client == "cursor")
    }

    @Test func whenAgentsAreOffTheyGetAnErrorTheyCanReadAndNothingChanges() throws {
        let session = Session()
        let acme = try session.world.service.addAccount(token: tokenA)
        _ = try session.world.service.addAccount(token: tokenB)
        try session.world.service.activate(acme.id)
        try session.world.service.setAgentsCanSwitch(false)
        _ = try session.initialize()

        let result = try session.call("use_project", ["project": "globexprod"])

        #expect(result["isError"] as? Bool == true)
        #expect(text(result).contains("turned off"))
        #expect(try session.world.service.snapshot().activeAccount?.id == acme.id)
        #expect(try session.call("list_accounts")["isError"] as? Bool == false)
    }

    @Test func badInputIsAnErrorTheModelCanRead() throws {
        let session = Session()
        _ = try session.world.service.addAccount(token: tokenA)
        _ = try session.initialize()

        let missing = try session.call("use_project")
        #expect(missing["isError"] as? Bool == true)
        #expect(text(missing).contains("“project” is required"))

        let unknown = try session.call("use_project", ["project": "nope"])
        #expect(unknown["isError"] as? Bool == true)
        #expect(text(unknown).contains("nope"))
    }

    @Test func protocolErrorsUseJSONRPCCodes() throws {
        let session = Session()
        let unknownMethod = try session.send("resources/list")
        #expect((unknownMethod["error"] as? [String: Any])?["code"] as? Int == -32601)

        let unknownTool = try session.send("tools/call", ["name": "run_anything", "arguments": [String: Any]()])
        #expect((unknownTool["error"] as? [String: Any])?["code"] as? Int == -32602)

        let garbage = try #require(session.server.handle("{not json"))
        #expect(garbage.contains("-32700"))
        #expect(try session.send("ping")["result"] != nil)
    }

    @Test func aMissingCLIIsReportedInsteadOfCrashing() throws {
        let server = MCPServer(service: { throw SwitchError.cliNotFound })
        let reply = try #require(server.handle(
            #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"list_accounts","arguments":{}}}"#))
        #expect(reply.contains(#""isError":true"#))
        #expect(reply.contains("not found"))
    }
}

@Suite struct AgentSetupTests {
    let app = "/Applications/Supabase Switch.app/Contents/MacOS/sbswitch"

    @Test func theCommandsAreQuotedForTheShell() {
        #expect(AgentClient.claudeCode.commandLine(sbswitch: app)
                == "claude mcp add --scope user supabase-switch -- '/Applications/Supabase Switch.app/Contents/MacOS/sbswitch' mcp")
        #expect(AgentClient.codex.commandLine(sbswitch: "/opt/homebrew/bin/sbswitch")
                == "codex mcp add supabase-switch -- /opt/homebrew/bin/sbswitch mcp")
        #expect(shellQuoted("it's") == #"'it'\''s'"#)
    }

    @Test func theJSONConfigurationPointsAtSbswitchMcp() throws {
        let json = AgentClient.jsonConfiguration(sbswitch: app)
        let object = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let server = try #require((object["mcpServers"] as? [String: Any])?["supabase-switch"] as? [String: Any])
        #expect(server["command"] as? String == app)
        #expect(server["args"] as? [String] == ["mcp"])
    }
}

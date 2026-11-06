import XCTest
@testable import DSHKit

final class AgentTests: XCTestCase {
    private var root: URL!
    private var workspace: URL!

    override func setUp() async throws {
        root = TestSupport.tempDirectory("dsh-agent")
        workspace = root.appendingPathComponent("ws", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testToolRoundTripAndHistory() async throws {
        let store = SessionStore(root: root.appendingPathComponent("sessions"))
        let header = try await store.createSession(cwd: workspace.path)
        let log = SessionLog(id: header.id)

        let provider = MockProvider(queues: [
            [
                .toolCall(index: 0, id: "call_1", name: "echo", arguments: #"{"text":"hi"}"#),
                .usage(LLMUsage(promptTokens: 11, completionTokens: 2)),
                .done,
            ],
            [
                .text("done"),
                .done,
            ],
        ])

        let echo = Tool(
            name: "echo",
            description: "Echo text",
            parameters: Schema.object(properties: ["text": Schema.string("text")], required: ["text"]),
            execute: { _, input in .text(input["text"]?.stringValue ?? "") }
        )

        var config = DSHConfig.default
        config.permissionPreset = "danger"
        let agent = Agent(
            sessionID: header.id,
            workspace: workspace,
            log: log,
            store: store,
            provider: provider,
            tools: ToolRegistry(tools: [echo]),
            sandbox: SandboxGuard(root: workspace, mode: .dangerFullAccess),
            config: config.agentConfig,
            approval: nil
        )

        try await agent.run("please echo")

        let projection = await agent.projection()
        XCTAssertEqual(projection.toolCalls.count, 1)
        XCTAssertEqual(projection.toolCalls[0].output, "hi")
        XCTAssertTrue(projection.items.contains { $0.kind == .assistant && $0.text == "done" })
        XCTAssertGreaterThanOrEqual(projection.usage.promptTokens, 11)
        XCTAssertNil(projection.lastError)

        let events = await log.snapshot()
        XCTAssertEqual(events.first?.type, .turnStart)
        let lastTurnEnd = events.last(where: { $0.type == .turnEnd })
        XCTAssertEqual(lastTurnEnd?.reason, "completed")
        XCTAssertTrue(events.contains { $0.type == .sessionTitle })
        XCTAssertEqual(events.filter { $0.type == .stepStart }.count, 2)
        XCTAssertEqual(events.filter { $0.type == .toolCall }.count, 1)
        XCTAssertEqual(events.filter { $0.type == .toolResult }.count, 1)

        let requests = provider.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[0].tools.first?.name, "echo")
        let roles = requests[1].messages.map(\.role)
        XCTAssertEqual(roles, [.user, .assistant, .tool])
        XCTAssertEqual(requests[1].messages[1].toolCalls.first?.name, "echo")
        XCTAssertEqual(requests[1].messages[2].toolCallID, "call_1")
        XCTAssertEqual(requests[1].messages[2].content, "hi")
    }

    func testEmptyResponseFailsTurn() async throws {
        let store = SessionStore(root: root.appendingPathComponent("sessions"))
        let header = try await store.createSession(cwd: workspace.path)
        let log = SessionLog(id: header.id)
        let provider = MockProvider(queues: [[.done]])

        let agent = Agent(
            sessionID: header.id,
            workspace: workspace,
            log: log,
            store: store,
            provider: provider,
            tools: ToolRegistry(),
            sandbox: SandboxGuard(root: workspace, mode: .workspaceWrite),
            config: DSHConfig.default.agentConfig,
            approval: nil
        )

        do {
            try await agent.run("hi")
            XCTFail("expected empty response failure")
        } catch {
            // expected
        }
        let projection = await agent.projection()
        XCTAssertNotNil(projection.lastError)
        let events = await log.snapshot()
        XCTAssertEqual(events.last?.type, .turnEnd)
        XCTAssertEqual(events.last?.reason, "error")
    }

    func testUnknownToolReturnsErrorResult() async throws {
        let store = SessionStore(root: root.appendingPathComponent("sessions"))
        let header = try await store.createSession(cwd: workspace.path)
        let log = SessionLog(id: header.id)
        let provider = MockProvider(queues: [
            [.toolCall(index: 0, id: "c1", name: "nope", arguments: "{}"), .done],
            [.text("ok"), .done],
        ])
        var config = DSHConfig.default
        config.permissionPreset = "danger"
        let agent = Agent(
            sessionID: header.id,
            workspace: workspace,
            log: log,
            store: store,
            provider: provider,
            tools: ToolRegistry(),
            sandbox: SandboxGuard(root: workspace, mode: .dangerFullAccess),
            config: config.agentConfig,
            approval: nil
        )
        try await agent.run("go")
        let projection = await agent.projection()
        XCTAssertEqual(projection.toolCalls.first?.isError, true)
        XCTAssertTrue(projection.toolCalls.first?.output?.contains("Unknown tool") == true)
    }
    func testSecondTurnIncludesHistory() async throws {
        let store = SessionStore(root: root.appendingPathComponent("sessions-history"))
        let header = try await store.createSession(cwd: workspace.path)
        let log = SessionLog(id: header.id)
        let provider = MockProvider(queues: [
            [.text("one"), .done],
            [.text("two"), .done],
        ])
        var config = DSHConfig.default
        config.permissionPreset = "danger"
        let agent = Agent(
            sessionID: header.id,
            workspace: workspace,
            log: log,
            store: store,
            provider: provider,
            tools: ToolRegistry(),
            sandbox: SandboxGuard(root: workspace, mode: .dangerFullAccess),
            config: config.agentConfig,
            approval: nil
        )

        try await agent.run("first")
        try await agent.run("second")

        let requests = provider.capturedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].messages.map(\.role), [.user, .assistant, .user])
        XCTAssertEqual(requests[1].messages[0].content, "first")
        XCTAssertEqual(requests[1].messages[1].content, "one")
        XCTAssertEqual(requests[1].messages[2].content, "second")
        let events = await log.snapshot()
        XCTAssertEqual(events.filter { $0.type == .turnStart }.count, 2)
        XCTAssertEqual(events.filter { $0.type == .turnEnd }.count, 2)
    }

    func testApprovalDenyBlocksDangerousTool() async throws {
        let store = SessionStore(root: root.appendingPathComponent("sessions-approval"))
        let header = try await store.createSession(cwd: workspace.path)
        let log = SessionLog(id: header.id)
        let provider = MockProvider(queues: [
            [.toolCall(index: 0, id: "d1", name: "danger", arguments: "{}"), .done],
            [.text("ok"), .done],
        ])
        let dangerous = Tool(
            name: "danger",
            description: "dangerous test tool",
            parameters: Schema.object(properties: [:]),
            isDangerous: true,
            execute: { _, _ in .text("executed") }
        )
        var config = DSHConfig.default
        config.permissionPreset = "default"
        let agent = Agent(
            sessionID: header.id,
            workspace: workspace,
            log: log,
            store: store,
            provider: provider,
            tools: ToolRegistry(tools: [dangerous]),
            sandbox: SandboxGuard(root: workspace, mode: .workspaceWrite),
            config: config.agentConfig,
            approval: { _ in false }
        )

        try await agent.run("do it")
        let projection = await agent.projection()
        XCTAssertEqual(projection.toolCalls.first?.isError, true)
        XCTAssertTrue(projection.toolCalls.first?.output?.contains("denied") == true)
        let events = await log.snapshot()
        XCTAssertEqual(events.filter { $0.type == .approvalAsked }.count, 1)
        XCTAssertEqual(events.filter { $0.type == .approvalDecided }.count, 1)
    }

    func testApprovalAllowExecutesDangerousTool() async throws {
        let store = SessionStore(root: root.appendingPathComponent("sessions-approval-allow"))
        let header = try await store.createSession(cwd: workspace.path)
        let log = SessionLog(id: header.id)
        let provider = MockProvider(queues: [
            [.toolCall(index: 0, id: "d2", name: "danger", arguments: "{}"), .done],
            [.text("ok"), .done],
        ])
        let dangerous = Tool(
            name: "danger",
            description: "dangerous test tool",
            parameters: Schema.object(properties: [:]),
            isDangerous: true,
            execute: { _, _ in .text("executed") }
        )
        var config = DSHConfig.default
        config.permissionPreset = "default"
        let agent = Agent(
            sessionID: header.id,
            workspace: workspace,
            log: log,
            store: store,
            provider: provider,
            tools: ToolRegistry(tools: [dangerous]),
            sandbox: SandboxGuard(root: workspace, mode: .workspaceWrite),
            config: config.agentConfig,
            approval: { _ in true }
        )

        try await agent.run("do it")
        let projection = await agent.projection()
        XCTAssertEqual(projection.toolCalls.first?.output, "executed")
        XCTAssertEqual(projection.toolCalls.first?.isError, false)
    }
}

// MARK: - Mock provider

final class MockProvider: LLMProvider, @unchecked Sendable {
    let name = "mock"
    let defaultModel = "mock"

    private let lock = NSLock()
    private var queues: [[StreamDelta]]
    private var requests: [ChatRequest] = []

    init(queues: [[StreamDelta]]) {
        self.queues = queues
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamDelta, Error> {
        lock.lock()
        requests.append(request)
        let deltas = queues.isEmpty ? [StreamDelta.done] : queues.removeFirst()
        lock.unlock()
        return AsyncThrowingStream { continuation in
            for delta in deltas { continuation.yield(delta) }
            continuation.finish()
        }
    }

    func capturedRequests() -> [ChatRequest] {
        lock.lock()
        defer { lock.unlock() }
        return requests
    }
}


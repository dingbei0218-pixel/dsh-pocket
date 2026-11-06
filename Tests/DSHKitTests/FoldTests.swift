import XCTest
@testable import DSHKit

final class FoldTests: XCTestCase {
    func testDerivesMessagesAndToolCards() async throws {
        let log = SessionLog(id: "fold")
        try await log.append(.turnStart(turn: 0))
        try await log.append(.userMessage(content: "read a file"))
        try await log.append(.stepStart(turn: 0, step: 1))
        try await log.append(.assistantChunk(text: "Let me "))
        try await log.append(.assistantChunk(text: "check."))
        try await log.append(.assistantMessage(content: "Let me check.", toolCallIDs: ["c1"]))
        try await log.append(.toolCall(callID: "c1", tool: "read_file", input: .object(["path": "a.txt"])))
        try await log.append(.toolResult(callID: "c1", output: "hello"))
        try await log.append(.stepEnd(turn: 0, step: 1))
        try await log.append(.stepStart(turn: 0, step: 2))
        try await log.append(.assistantMessage(content: "Done."))
        try await log.append(.stepEnd(turn: 0, step: 2))
        try await log.append(.turnEnd(turn: 0, reason: .completed))

        let projection = await log.projection()
        XCTAssertEqual(projection.messages.count, 3)
        XCTAssertEqual(projection.messages[1].toolCallIDs, ["c1"])
        XCTAssertEqual(projection.toolCalls.count, 1)
        XCTAssertEqual(projection.toolCalls[0].output, "hello")
        XCTAssertTrue(projection.toolCalls[0].finished)
        XCTAssertEqual(projection.items.filter { $0.kind == .user }.count, 1)
        XCTAssertEqual(projection.items.filter { $0.kind == .tool }.count, 1)
        XCTAssertTrue(projection.items.contains { $0.kind == .assistant && $0.text == "Done." })
        XCTAssertFalse(projection.isStreaming)
    }

    func testGoalLatestRevisionWins() async throws {
        let log = SessionLog(id: "goal")
        try await log.append(.goalChange(goalID: "g", phase: .active, description: "ship", maxRounds: 5, revision: 1))
        try await log.append(.goalChange(goalID: "g", phase: .paused, description: "ship it", maxRounds: 8, revision: 2))
        try await log.append(.goalRound(1))
        let projection = await log.projection()
        XCTAssertEqual(projection.goal?.phase, .paused)
        XCTAssertEqual(projection.goal?.revision, 2)
        XCTAssertEqual(projection.goal?.maxRounds, 8)
        XCTAssertEqual(projection.goal?.rounds, 1)
    }

    func testTodoLastWriteWinsAndClears() async throws {
        let log = SessionLog(id: "todo")
        try await log.append(.todoWrite(items: [TodoItem(content: "one")]))
        try await log.append(.todoWrite(items: [TodoItem(content: "two", status: .completed)]))
        var projection = await log.projection()
        XCTAssertEqual(projection.todos.map(\.content), ["two"])
        try await log.append(.todoWrite(items: []))
        projection = await log.projection()
        XCTAssertTrue(projection.todos.isEmpty)
    }

    func testUsageAccumulates() async throws {
        let log = SessionLog(id: "usage")
        try await log.append(.llmDone(promptTokens: 10, completionTokens: 2))
        try await log.append(.llmDone(promptTokens: 20, completionTokens: 3))
        let projection = await log.projection()
        XCTAssertEqual(projection.usage.promptTokens, 30)
        XCTAssertEqual(projection.usage.completionTokens, 5)
        XCTAssertEqual(projection.usage.lastPromptTokens, 20)
    }

    func testTitleAndFallback() async throws {
        let log = SessionLog(id: "title")
        try await log.append(.userMessage(content: "Fix the login bug\nmore"))
        var projection = await log.projection()
        XCTAssertEqual(projection.displayTitle, "Fix the login bug")
        try await log.append(.sessionTitle("Login fix"))
        projection = await log.projection()
        XCTAssertEqual(projection.displayTitle, "Login fix")
    }

    func testApprovalLifecycle() async throws {
        let log = SessionLog(id: "approval")
        try await log.append(.approvalAsked(requestID: "a1", tool: "write_file", summary: "Write x"))
        var projection = await log.projection()
        XCTAssertEqual(projection.pendingApproval?.tool, "write_file")
        try await log.append(.approvalDecided(requestID: "a1", allowed: false))
        projection = await log.projection()
        XCTAssertNil(projection.pendingApproval)
    }

    func testSandboxPresetMapping() async throws {
        let log = SessionLog(id: "preset")
        try await log.append(.presetChange("safe"))
        let projection = await log.projection()
        XCTAssertEqual(projection.sandboxMode, .readOnly)
        XCTAssertEqual(projection.approvalPolicy, .askDangerous)
    }
}

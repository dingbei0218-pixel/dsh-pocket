import XCTest
@testable import DSHKit

final class SessionLogTests: XCTestCase {
    func testTurnStepLifecycle() async throws {
        let log = SessionLog(id: "test")
        try await log.append(.turnStart(turn: 0))
        try await log.append(.userMessage(content: "hi"))
        try await log.append(.stepStart(turn: 0, step: 1))
        try await log.append(.assistantMessage(content: "hello"))
        try await log.append(.stepEnd(turn: 0, step: 1))
        try await log.append(.turnEnd(turn: 0, reason: .completed))

        let events = await log.snapshot()
        XCTAssertEqual(events.map(\.seq), Array(1...6).map(UInt64.init))
        XCTAssertEqual(events[5].type, .turnEnd)
        let errors = await log.check()
        XCTAssertTrue(errors.isEmpty, errors.joined())
        let projection = await log.projection()
        XCTAssertEqual(projection.messages.count, 2)
        XCTAssertTrue(projection.items.contains { $0.kind == .assistant && $0.text == "hello" })
    }

    func testRejectsUnpairedStepEnd() async throws {
        let log = SessionLog(id: "test")
        try await log.append(.turnStart(turn: 0))
        do {
            try await log.append(.stepEnd(turn: 0, step: 1))
            XCTFail("expected invariant error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("step/end without open step/start"))
        }
        let seq = await log.lastSeq
        XCTAssertEqual(seq, 1)
    }

    func testRejectsOutOfOrderTurn() async throws {
        let log = SessionLog(id: "test")
        do {
            try await log.append(.turnStart(turn: 1))
            XCTFail("expected invariant error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("expected turn 0"))
        }
    }

    func testToolPairing() async throws {
        let log = SessionLog(id: "test")
        try await log.append(.turnStart(turn: 0))
        try await log.append(.stepStart(turn: 0, step: 1))
        try await log.append(.toolCall(callID: "c1", tool: "echo", input: .object([:])))
        do {
            try await log.append(.toolCall(callID: "c1", tool: "echo", input: .object([:])))
            XCTFail("duplicate call must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("duplicate tool/call"))
        }
        try await log.append(.toolResult(callID: "c1", output: "ok"))
        do {
            try await log.append(.toolResult(callID: "c1", output: "again"))
            XCTFail("duplicate result must fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("duplicate tool/result"))
        }
        try await log.append(.stepEnd(turn: 0, step: 1))
        try await log.append(.turnEnd(turn: 0, reason: .completed))
        let errors = await log.check()
        XCTAssertTrue(errors.isEmpty)
    }

    func testRepairOrphanTurn() async throws {
        let events: [SessionEvent] = [
            SessionEvent(seq: 1, time: Date(), type: .turnStart, data: EventData.turnStart(turn: 0).payload),
            SessionEvent(seq: 2, time: Date(), type: .stepStart, data: EventData.stepStart(turn: 0, step: 1).payload),
            SessionEvent(seq: 3, time: Date(), type: .toolCall, data: EventData.toolCall(callID: "c1", tool: "x", input: .object([:])).payload),
        ]
        let log = SessionLog(id: "test")
        try await log.restore(events, repair: true)
        let restored = await log.snapshot()
        XCTAssertEqual(restored.count, 6)
        XCTAssertEqual(restored.last?.type, .turnEnd)
        XCTAssertEqual(restored.last?.reason, "interrupted")
        let errors = await log.check()
        XCTAssertTrue(errors.isEmpty, errors.joined())
    }

    func testSurfaceReplaceHidesEvents() async throws {
        let log = SessionLog(id: "test")
        try await log.append(.turnStart(turn: 0))
        try await log.append(.userMessage(content: "one"))
        try await log.append(.assistantMessage(content: "two"))
        try await log.append(.turnEnd(turn: 0, reason: .completed))
        try await log.appendSurfaceReplace(start: 2, end: 3, summary: "summary")

        let events = await log.snapshot()
        XCTAssertEqual(events.count, 5)
        let effective = Fold.effectiveEvents(events)
        XCTAssertEqual(effective.map(\.type), [.turnStart, .turnEnd, .surfaceReplace])
        XCTAssertEqual(effective.last?.data["data"]?["summary"]?.stringValue, "summary")
    }

    func testRestoreRejectsCorruptSequence() async throws {
        let events: [SessionEvent] = [
            SessionEvent(seq: 1, time: Date(), type: .turnStart, data: EventData.turnStart(turn: 0).payload),
            SessionEvent(seq: 2, time: Date(), type: .turnEnd, data: EventData.turnEnd(turn: 0, reason: .completed).payload),
            SessionEvent(seq: 3, time: Date(), type: .turnStart, data: EventData.turnStart(turn: 5).payload),
        ]
        let log = SessionLog(id: "test")
        do {
            try await log.restore(events, repair: false)
            XCTFail("expected invariant error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("expected turn"))
        }
    }
}

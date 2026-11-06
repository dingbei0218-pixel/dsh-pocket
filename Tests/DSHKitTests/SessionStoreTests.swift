import XCTest
@testable import DSHKit

final class SessionStoreTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = TestSupport.tempDirectory("dsh-store-tests")
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testCreateAppendLoadList() async throws {
        let store = SessionStore(root: root)
        let header = try await store.createSession(cwd: "/tmp/ws")
        XCTAssertEqual(header.version, 1)

        let log = SessionLog(id: header.id)
        try await log.append(.turnStart(turn: 0))
        try await log.append(.userMessage(content: "hello store"))
        try await log.append(.turnEnd(turn: 0, reason: .completed))
        for event in await log.snapshot() {
            try await store.append(event, to: header.id)
        }

        let (loadedHeader, events) = try await store.load(header.id)
        XCTAssertEqual(loadedHeader.id, header.id)
        XCTAssertEqual(events.count, 3)
        XCTAssertEqual(events[1].content, "hello store")

        let list = try await store.listSessions()
        XCTAssertEqual(list.count, 1)
        XCTAssertEqual(list[0].title, "hello store")
        XCTAssertEqual(list[0].eventCount, 3)
    }

    func testForkSeedsEventsAndEndSeed() async throws {
        let store = SessionStore(root: root)
        let header = try await store.createSession(cwd: nil)
        let log = SessionLog(id: header.id)
        try await log.append(.turnStart(turn: 0))
        try await log.append(.turnEnd(turn: 0, reason: .completed))
        for event in await log.snapshot() { try await store.append(event, to: header.id) }

        let child = try await store.fork(header.id)
        let (_, childEvents) = try await store.load(child.id)
        XCTAssertEqual(child.parentSession, header.id)
        XCTAssertEqual(child.origin, .fork)
        XCTAssertEqual(childEvents.count, 3)
        XCTAssertEqual(childEvents.last?.type, .endSeed)
        XCTAssertEqual(childEvents.last?.data["parentSession"]?.stringValue, header.id.rawValue)
    }

    func testCorruptLastLineIsTolerated() async throws {
        let store = SessionStore(root: root)
        let header = try await store.createSession(cwd: nil)
        try await store.append(EventData.turnStart(turn: 0).makeEvent(seq: 1), to: header.id)
        var data = try Data(contentsOf: await store.eventsURL(header.id))
        data.append(Data("{not json".utf8))
        try data.write(to: await store.eventsURL(header.id))
        let events = try await store.loadEvents(header.id)
        XCTAssertEqual(events.count, 1)
    }

    func testMissingSessionThrows() async throws {
        let store = SessionStore(root: root)
        do {
            _ = try await store.load(SessionID(rawValue: "nope"))
            XCTFail("expected error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("not found"))
        }
    }
}

import XCTest
@testable import DSHKit

final class EventRoundTripTests: XCTestCase {
    func testEnvelopeShapeMatchesGo() throws {
        let event = SessionEvent(
            seq: 7,
            time: Date(timeIntervalSince1970: 1_700_000_000.123),
            type: .turnStart,
            data: EventData.turnStart(turn: 0).payload
        )
        let data = try DSHCoding.encode(event)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["seq"] as? UInt64, 7)
        XCTAssertEqual(json["type"] as? String, "turn/start")
        XCTAssertEqual((json["data"] as? [String: Any])?["turn"] as? Int, 0)
        let time = try XCTUnwrap(json["time"] as? String)
        XCTAssertTrue(time.hasSuffix("Z"), time)
        XCTAssertTrue(time.contains("."), time)

        let decoded = try DSHCoding.decode(SessionEvent.self, from: data)
        XCTAssertEqual(decoded, event)
    }

    func testAllKnownTypesEncode() throws {
        for type in EventType.allKnown {
            let event = SessionEvent(seq: 1, time: Date(), type: type, data: .object([:]))
            let data = try DSHCoding.encode(event)
            let round = try DSHCoding.decode(SessionEvent.self, from: data)
            XCTAssertEqual(round.type, type)
        }
    }

    func testUnknownEventTypeIsPreserved() throws {
        let event = SessionEvent(seq: 1, time: Date(), type: EventType("future/thing"), data: .object(["x": .int(1)]))
        let data = try DSHCoding.encode(event)
        let round = try DSHCoding.decode(SessionEvent.self, from: data)
        XCTAssertEqual(round.type.rawValue, "future/thing")
        XCTAssertEqual(round.data["x"]?.intValue, 1)
        XCTAssertFalse(round.type.isKnown)
    }

    func testDateParsesGoNanoseconds() {
        let date = ISO8601.date(from: "2026-11-06T13:49:19.123456789Z")
        XCTAssertNotNil(date)
        XCTAssertEqual(ISO8601.string(from: date!), "2026-11-06T13:49:19.123Z")
    }

    func testToolPayloadKeys() throws {
        let call = EventData.toolCall(callID: "call_1", tool: "read_file", input: .object(["path": "a.swift"]))
        XCTAssertEqual(call.payload["callId"]?.stringValue, "call_1")
        XCTAssertEqual(call.payload["tool"]?.stringValue, "read_file")
        XCTAssertEqual(call.payload["input"]?["path"]?.stringValue, "a.swift")

        let result = EventData.toolResult(callID: "call_1", output: "ok", isError: true, truncated: true)
        XCTAssertEqual(result.payload["callId"]?.stringValue, "call_1")
        XCTAssertEqual(result.payload["isError"]?.boolValue, true)
        XCTAssertEqual(result.payload["truncated"]?.boolValue, true)
    }

    func testTodoPayloadHasEntriesAndItems() {
        let json = EventData.todoWrite(items: [TodoItem(content: "a"), TodoItem(content: "b", status: .completed)]).payload
        XCTAssertEqual(json["items"]?.arrayValue?.count, 2)
        let entries = try? XCTUnwrap(json["entries"]?.arrayValue)
        XCTAssertEqual(entries?.count, 2)
        XCTAssertEqual(entries?[1]["status"]?.stringValue, "completed")
    }

    func testHeaderJSONUsesCamelCaseAndOmitsNil() throws {
        let header = SessionHeader(id: "s1", cwd: "/tmp", origin: .created)
        let data = try DSHCoding.encode(header)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(json["cwd"] as? String, "/tmp")
        XCTAssertEqual(json["origin"] as? String, "created")
        XCTAssertEqual(json["version"] as? Int, 1)
        XCTAssertNil(json["parentSession"])
        let decoded = try DSHCoding.decode(SessionHeader.self, from: data)
        XCTAssertEqual(decoded.id, header.id)
    }
}

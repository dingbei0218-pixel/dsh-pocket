import Foundation

/// 表面操作：compaction 唯一合法的「回写历史」方式。
/// 读取时把 `[start, end]` 范围的旧事件隐藏，用本事件的 data 替代；源事件永远不变。
public struct SurfaceOp: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case append
        case replace
    }

    public var op: Kind
    public var start: UInt64?
    public var end: UInt64?
    public var data: JSONValue?

    public init(op: Kind = .append, start: UInt64? = nil, end: UInt64? = nil, data: JSONValue? = nil) {
        self.op = op
        self.start = start
        self.end = end
        self.data = data
    }
}

/// 一条会话事件（严格递增 seq + 单调时间）。
///
/// JSON 形状与 dsh-go `SessionEvent` 完全一致：
/// `{ "seq":1, "time":"2026-...", "type":"turn/start", "data":{...}, "surfaceOp":{...}?, "sourceEventSeqs":[...]? }`
public struct SessionEvent: Codable, Hashable, Sendable, Identifiable {
    public var seq: UInt64
    public var time: Date
    public var type: EventType
    public var data: JSONValue
    public var surfaceOp: SurfaceOp?
    public var sourceEventSeqs: [UInt64]?

    public var id: UInt64 { seq }

    public init(
        seq: UInt64,
        time: Date,
        type: EventType,
        data: JSONValue = .object([:]),
        surfaceOp: SurfaceOp? = nil,
        sourceEventSeqs: [UInt64]? = nil
    ) {
        self.seq = seq
        self.time = time
        self.type = type
        self.data = data
        self.surfaceOp = surfaceOp
        self.sourceEventSeqs = sourceEventSeqs
    }

    private enum CodingKeys: String, CodingKey {
        case seq, time, type, data, surfaceOp, sourceEventSeqs
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        seq = try container.decode(UInt64.self, forKey: .seq)
        time = try container.decode(Date.self, forKey: .time)
        type = try container.decode(EventType.self, forKey: .type)
        data = try container.decodeIfPresent(JSONValue.self, forKey: .data) ?? .object([:])
        surfaceOp = try container.decodeIfPresent(SurfaceOp.self, forKey: .surfaceOp)
        sourceEventSeqs = try container.decodeIfPresent([UInt64].self, forKey: .sourceEventSeqs)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(seq, forKey: .seq)
        try container.encode(time, forKey: .time)
        try container.encode(type, forKey: .type)
        try container.encode(data, forKey: .data)
        try container.encodeIfPresent(surfaceOp, forKey: .surfaceOp)
        try container.encodeIfPresent(sourceEventSeqs, forKey: .sourceEventSeqs)
    }

    // MARK: - 便捷读取（与 dsh-go 字段名逐字对应）

    public var callID: ToolCallID? {
        guard let raw = data["callId"]?.stringValue else { return nil }
        return ToolCallID(rawValue: raw)
    }

    public var toolName: String? { data["tool"]?.stringValue }
    public var text: String? { data["text"]?.stringValue }
    public var content: String? { data["content"]?.stringValue }
    public var output: String? { data["output"]?.stringValue }
    public var isError: Bool { data["isError"]?.boolValue ?? false }
    public var turn: UInt64? { data["turn"]?.uint64Value }
    public var step: UInt64? { data["step"]?.uint64Value }
    public var reason: String? { data["reason"]?.stringValue }
}

import Foundation

/// 与语言无关的 JSON 值。
///
/// 工具入参、事件 payload、工具 schema 都使用它：
/// - `Codable` 保证与 dsh-go / DeepSeek API 的 JSON 字节语义一致；
/// - `Hashable + Sendable` 让它可以安全地跨 actor 传递、用于 diff / 缓存键。
public enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .number(Double(value))
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            // 整数值不要输出 "1.0"，避免与 Go 的 JSON 输出产生无意义差异。
            if value.isFinite, value == value.rounded(), abs(value) < 9_007_199_254_740_992 {
                try container.encode(Int64(value))
            } else {
                try container.encode(value)
            }
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }
}

// MARK: - 便捷构造与读取

public extension JSONValue {
    static func int(_ value: Int) -> JSONValue { .number(Double(value)) }
    static func int64(_ value: Int64) -> JSONValue { .number(Double(value)) }
    static func uint64(_ value: UInt64) -> JSONValue { .number(Double(value)) }
    static func double(_ value: Double) -> JSONValue { .number(value) }

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    var intValue: Int? {
        guard let value = doubleValue, value.isFinite else { return nil }
        return Int(value)
    }

    var int64Value: Int64? {
        guard let value = doubleValue, value.isFinite else { return nil }
        return Int64(value)
    }

    var uint64Value: UInt64? {
        guard let value = doubleValue, value.isFinite, value >= 0 else { return nil }
        return UInt64(value)
    }

    var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    var objectValue: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }

    subscript(key: String) -> JSONValue? {
        get {
            guard case .object(let dictionary) = self else { return nil }
            return dictionary[key]
        }
        set {
            guard case .object(var dictionary) = self else { return }
            dictionary[key] = newValue
            self = .object(dictionary)
        }
    }

    subscript(index: Int) -> JSONValue? {
        guard case .array(let values) = self, values.indices.contains(index) else { return nil }
        return values[index]
    }

    /// 稳定、紧凑的 JSON 字符串（用于事件 payload 与日志）。
    func jsonString(pretty: Bool = false) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(self), let text = String(data: data, encoding: .utf8) else {
            return "null"
        }
        return text
    }

    static func parse(_ text: String) -> JSONValue? {
        guard let data = text.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

// MARK: - 字面量支持

extension JSONValue: ExpressibleByNilLiteral {
    public init(nilLiteral: ()) { self = .null }
}

extension JSONValue: ExpressibleByBooleanLiteral {
    public init(booleanLiteral value: Bool) { self = .bool(value) }
}

extension JSONValue: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
}

extension JSONValue: ExpressibleByFloatLiteral {
    public init(floatLiteral value: Double) { self = .number(value) }
}

extension JSONValue: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

extension JSONValue: ExpressibleByArrayLiteral {
    public init(arrayLiteral elements: JSONValue...) { self = .array(elements) }
}

extension JSONValue: ExpressibleByDictionaryLiteral {
    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        var dictionary: [String: JSONValue] = [:]
        for (key, value) in elements { dictionary[key] = value }
        self = .object(dictionary)
    }
}

// MARK: - 有序编码辅助

public extension Dictionary where Key == String, Value == JSONValue {
    /// 工具 schema 的参数定义常用「有序字段」，统一从字典构造。
    static func schema(
        type: String = "object",
        properties: [String: JSONValue] = [:],
        required: [String] = []
    ) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string(type),
            "properties": .object(properties),
        ]
        if !required.isEmpty {
            object["required"] = .array(required.map { .string($0) })
        }
        return .object(object)
    }
}

import Foundation

/// JSON Schema 构造小工具（工具参数描述用）。
public enum Schema {
    public static func string(_ description: String, enum values: [String]? = nil) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("string"),
            "description": .string(description),
        ]
        if let values { object["enum"] = .array(values.map { .string($0) }) }
        return .object(object)
    }

    public static func integer(_ description: String, minimum: Int? = nil, maximum: Int? = nil) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("integer"),
            "description": .string(description),
        ]
        if let minimum { object["minimum"] = .int(minimum) }
        if let maximum { object["maximum"] = .int(maximum) }
        return .object(object)
    }

    public static func boolean(_ description: String) -> JSONValue {
        .object(["type": .string("boolean"), "description": .string(description)])
    }

    public static func array(_ description: String, items: JSONValue) -> JSONValue {
        .object([
            "type": .string("array"),
            "description": .string(description),
            "items": items,
        ])
    }

    public static func object(properties: [String: JSONValue], required: [String] = []) -> JSONValue {
        var object: [String: JSONValue] = [
            "type": .string("object"),
            "properties": .object(properties),
        ]
        if !required.isEmpty { object["required"] = .array(required.map { .string($0) }) }
        return .object(object)
    }
}

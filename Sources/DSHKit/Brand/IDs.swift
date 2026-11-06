import Foundation

/// 品牌化 ID 基类：把裸字符串包装成不同语义类型，避免跨 API 误传。
///
/// 对应 dsh-go `pkg/brand` 的 `Branded[T]`。Swift 没有零成本泛型标签别名，
/// 这里用 `RawRepresentable` 结构体逐一定义；JSON 表示仍是纯字符串。
public protocol BrandedID: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible
where RawValue == String {
    init(rawValue: String)
}

public extension BrandedID {
    init(_ raw: String) { self.init(rawValue: raw) }
    var description: String { rawValue }
    var isEmpty: Bool { rawValue.isEmpty }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct SessionID: BrandedID {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }

    /// dsh-go 使用 `brand.NewSessionID` 生成；Apple 端用 UUID，保证全局唯一且可排序。
    public static func generate(prefix: String = "sess") -> SessionID {
        SessionID(rawValue: "\(prefix)_\(UUID().uuidString.lowercased())")
    }

    public var short: String { String(rawValue.prefix(12)) }
}

public struct ToolCallID: BrandedID {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func generate() -> ToolCallID { ToolCallID(rawValue: "call_\(UUID().uuidString.lowercased())") }
}

public struct ApprovalRequestID: BrandedID {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public static func generate() -> ApprovalRequestID { ApprovalRequestID(rawValue: "appr_\(UUID().uuidString.lowercased())") }
}

public struct JobID: BrandedID {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct WorkspaceID: BrandedID {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct AttachmentID: BrandedID {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

public struct ProjectionID: BrandedID {
    public var rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
}

// MARK: - 字面量便利（示例 / 测试 / 固定 ID）

extension SessionID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension ToolCallID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension ApprovalRequestID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension JobID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension WorkspaceID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension AttachmentID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

extension ProjectionID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self.init(rawValue: value) }
}

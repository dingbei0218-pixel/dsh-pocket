import Foundation

/// 工具错误（进入 tool/error 或 tool/result isError）。
public struct ToolError: Error, LocalizedError, Sendable {
    public var message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

public struct ToolResult: Sendable, Equatable {
    public var output: String
    public var isError: Bool
    public var truncated: Bool
    public var spillPath: String?

    public init(output: String, isError: Bool = false, truncated: Bool = false, spillPath: String? = nil) {
        self.output = output
        self.isError = isError
        self.truncated = truncated
        self.spillPath = spillPath
    }

    public static func text(_ output: String) -> ToolResult { ToolResult(output: output) }
    public static func failure(_ message: String) -> ToolResult { ToolResult(output: message, isError: true) }
}

/// 工具执行上下文：工作区、调用 ID、事件回写通道。
public struct ToolContext: Sendable {
    public let sessionID: SessionID
    public let workspace: URL
    public let callID: ToolCallID
    public let sandbox: SandboxGuard
    public let emit: @Sendable (EventData) async -> Void

    public init(
        sessionID: SessionID,
        workspace: URL,
        callID: ToolCallID,
        sandbox: SandboxGuard,
        emit: @escaping @Sendable (EventData) async -> Void
    ) {
        self.sessionID = sessionID
        self.workspace = workspace
        self.callID = callID
        self.sandbox = sandbox
        self.emit = emit
    }
}

/// 工具定义。
public struct Tool: Sendable {
    public var name: String
    public var description: String
    public var parameters: JSONValue
    /// 是否属于危险操作（写盘、执行命令、联网等），用于审批策略。
    public var isDangerous: Bool
    public var isReadOnly: Bool
    public var execute: @Sendable (ToolContext, JSONValue) async throws -> ToolResult

    public init(
        name: String,
        description: String,
        parameters: JSONValue,
        isDangerous: Bool = false,
        isReadOnly: Bool = false,
        execute: @escaping @Sendable (ToolContext, JSONValue) async throws -> ToolResult
    ) {
        self.name = name
        self.description = description
        self.parameters = parameters
        self.isDangerous = isDangerous
        self.isReadOnly = isReadOnly
        self.execute = execute
    }

    public var schema: ToolSchema {
        ToolSchema(name: name, description: description, parameters: parameters)
    }
}

/// 工具注册表（不可变快照；并发安全）。
public struct ToolRegistry: Sendable {
    private var tools: [String: Tool]
    public let maxOutputCharacters: Int

    public init(tools: [Tool] = [], maxOutputCharacters: Int = 60_000) {
        var dictionary: [String: Tool] = [:]
        for tool in tools where dictionary[tool.name] == nil {
            dictionary[tool.name] = tool
        }
        self.tools = dictionary
        self.maxOutputCharacters = maxOutputCharacters
    }

    public var all: [Tool] { tools.values.sorted { $0.name < $1.name } }
    public var schemas: [ToolSchema] { all.map(\.schema) }
    public var names: [String] { all.map(\.name) }

    public func tool(named name: String) -> Tool? { tools[name] }

    public mutating func register(_ tool: Tool) { tools[tool.name] = tool }

    public mutating func remove(_ name: String) { tools[name] = nil }

    /// 截断超长输出；超过上限时写入 spill 文件，返回带路径的结果。
    public func truncate(_ output: String, callID: ToolCallID, spillDirectory: URL?) -> ToolResult {
        guard output.count > maxOutputCharacters else {
            return ToolResult(output: output)
        }
        let head = String(output.prefix(maxOutputCharacters))
        var spillPath: String?
        if let spillDirectory {
            try? FileManager.default.createDirectory(at: spillDirectory, withIntermediateDirectories: true)
            let url = spillDirectory.appendingPathComponent("\(callID.rawValue).txt")
            try? output.write(to: url, atomically: true, encoding: .utf8)
            spillPath = url.path
        }
        let note = "\n\n[output truncated at \(maxOutputCharacters) characters; \(output.count) total\(spillPath.map { ", full output: \($0)" } ?? "")]"
        return ToolResult(output: head + note, truncated: true, spillPath: spillPath)
    }
}

/// 审批策略判定。
public struct ApprovalRequest: Sendable, Equatable {
    public var requestID: ApprovalRequestID
    public var tool: String
    public var summary: String
    public var input: JSONValue

    public init(requestID: ApprovalRequestID, tool: String, summary: String, input: JSONValue) {
        self.requestID = requestID
        self.tool = tool
        self.summary = summary
        self.input = input
    }
}

public typealias ApprovalHandler = @Sendable (ApprovalRequest) async -> Bool

public enum ApprovalDecision: Sendable {
    case allow
    case deny

    public var allowed: Bool { self == .allow }
}

public enum ApprovalGate {
    /// 返回非 nil 表示需要向用户发起审批。
    public static func requiresApproval(tool: Tool, policy: ApprovalPolicy) -> Bool {
        switch policy {
        case .allowAll:
            return false
        case .denyAll:
            return true
        case .askDangerous:
            return tool.isDangerous
        case .askDangerousToolEdit:
            return tool.isDangerous || tool.name == "edit_file" || tool.name == "write_file"
        }
    }

    public static func summary(tool: Tool, input: JSONValue) -> String {
        switch tool.name {
        case "write_file":
            return "Write \(input["path"]?.stringValue ?? "file")"
        case "edit_file":
            return "Edit \(input["path"]?.stringValue ?? "file")"
        case "shell":
            return "Run shell command: \(input["command"]?.stringValue ?? "")"
        case "web_fetch":
            return "Fetch \(input["url"]?.stringValue ?? "URL")"
        default:
            return "Run \(tool.name)"
        }
    }
}

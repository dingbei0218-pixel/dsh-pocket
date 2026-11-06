import Foundation

/// 对话消息（OpenAI / DeepSeek 兼容形状）。
public struct LLMMessage: Codable, Sendable, Equatable {
    public enum Role: String, Codable, Sendable {
        case system
        case user
        case assistant
        case tool
    }

    public var role: Role
    public var content: String
    public var toolCalls: [LLMToolCall]
    public var toolCallID: String?

    public init(role: Role, content: String, toolCalls: [LLMToolCall] = [], toolCallID: String? = nil) {
        self.role = role
        self.content = content
        self.toolCalls = toolCalls
        self.toolCallID = toolCallID
    }

    public static func user(_ text: String) -> LLMMessage { .init(role: .user, content: text) }
    public static func assistant(_ text: String, toolCalls: [LLMToolCall] = []) -> LLMMessage {
        .init(role: .assistant, content: text, toolCalls: toolCalls)
    }
    public static func tool(callID: String, _ text: String) -> LLMMessage {
        .init(role: .tool, content: text, toolCallID: callID)
    }
}

/// 模型返回的工具调用（参数是原始 JSON 字符串，流式期间会分片）。
public struct LLMToolCall: Codable, Sendable, Equatable {
    public var id: String
    public var name: String
    public var arguments: String

    public init(id: String, name: String, arguments: String) {
        self.id = id
        self.name = name
        self.arguments = arguments
    }

    public var input: JSONValue {
        JSONValue.parse(arguments) ?? .object([:])
    }
}

/// 提供给模型的工具定义（JSON Schema）。
public struct ToolSchema: Codable, Sendable, Equatable {
    public var name: String
    public var description: String
    public var parameters: JSONValue

    public init(name: String, description: String, parameters: JSONValue) {
        self.name = name
        self.description = description
        self.parameters = parameters
    }
}

public struct ChatRequest: Sendable {
    public var model: String
    public var system: String
    public var messages: [LLMMessage]
    public var tools: [ToolSchema]
    public var temperature: Double?
    public var maxTokens: Int?

    public init(
        model: String,
        system: String = "",
        messages: [LLMMessage],
        tools: [ToolSchema] = [],
        temperature: Double? = nil,
        maxTokens: Int? = nil
    ) {
        self.model = model
        self.system = system
        self.messages = messages
        self.tools = tools
        self.temperature = temperature
        self.maxTokens = maxTokens
    }
}

public struct LLMUsage: Sendable, Equatable {
    public var promptTokens: Int
    public var completionTokens: Int
    public var promptCacheHitTokens: Int
    public var promptCacheMissTokens: Int

    public init(promptTokens: Int = 0, completionTokens: Int = 0, promptCacheHitTokens: Int = 0, promptCacheMissTokens: Int = 0) {
        self.promptTokens = promptTokens
        self.completionTokens = completionTokens
        self.promptCacheHitTokens = promptCacheHitTokens
        self.promptCacheMissTokens = promptCacheMissTokens
    }
}

/// 流式分片。
public enum StreamDelta: Sendable {
    case text(String)
    case reasoning(String)
    /// DeepSeek 的 tool_calls 是增量：同一下标会分多次到达，参数按字符串拼接。
    case toolCall(index: Int, id: String?, name: String?, arguments: String)
    case usage(LLMUsage)
    case done
}

/// LLM 稳定失败分类（对齐 dsh-go `LlmFailureKind` / 官方 error.ts）。
public enum LLMFailureKind: String, Sendable, Codable, CaseIterable {
    case overload
    case rateLimit = "rate-limit"
    case responseRefusal = "response-refusal"
    case contextOverflow = "context-overflow"
    case quota
    case emptyResponse = "empty-response"
    case invalidCredential = "invalid-credential"
    case invalidRequest = "invalid-request"
    case network
    case cancelled
    case unknown

    public var isRetryable: Bool {
        switch self {
        case .overload, .rateLimit, .contextOverflow, .emptyResponse, .network:
            return true
        default:
            return false
        }
    }
}

public struct LLMFailure: Error, LocalizedError, Sendable {
    public var kind: LLMFailureKind
    public var message: String
    public var statusCode: Int?

    public init(kind: LLMFailureKind, message: String, statusCode: Int? = nil) {
        self.kind = kind
        self.message = message
        self.statusCode = statusCode
    }

    public var errorDescription: String? { "llm failure [\(kind.rawValue)]: \(message)" }

    /// 从 provider 的 status/body 做稳定分类（只按结构信号，不把 message 直接透出给路由）。
    public static func classify(status: Int, body: String) -> LLMFailure {
        let lower = body.lowercased()
        let snippet = String(body.prefix(400))

        if status == 401 || status == 403 || lower.contains("invalid api key") || lower.contains("invalid_api_key") {
            return LLMFailure(kind: .invalidCredential, message: snippet, statusCode: status)
        }
        if status == 429 || lower.contains("rate limit") || lower.contains("rate_limit") {
            return LLMFailure(kind: .rateLimit, message: snippet, statusCode: status)
        }
        if lower.contains("insufficient balance") || lower.contains("insufficient quota") || lower.contains("quota") {
            return LLMFailure(kind: .quota, message: snippet, statusCode: status)
        }
        if lower.contains("context length") || lower.contains("context window") || lower.contains("maximum context") || lower.contains("too long") {
            return LLMFailure(kind: .contextOverflow, message: snippet, statusCode: status)
        }
        if status >= 500 {
            return LLMFailure(kind: .overload, message: snippet, statusCode: status)
        }
        if status == 400 || status == 422 {
            return LLMFailure(kind: .invalidRequest, message: snippet, statusCode: status)
        }
        if lower.contains("refus") || lower.contains("declin") {
            return LLMFailure(kind: .responseRefusal, message: snippet, statusCode: status)
        }
        return LLMFailure(kind: .unknown, message: snippet, statusCode: status)
    }
}

/// 模型提供方接缝。
public protocol LLMProvider: Sendable {
    var name: String { get }
    var defaultModel: String { get }
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamDelta, Error>
}

extension LLMProvider {
    public var defaultModel: String { "deepseek-chat" }
}

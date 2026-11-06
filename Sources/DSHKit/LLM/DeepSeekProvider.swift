import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// DeepSeek / OpenAI-compatible 提供方配置。
public struct DeepSeekConfig: Sendable {
    public var baseURL: URL
    public var model: String
    public var apiKey: @Sendable () async throws -> String
    public var reasoningEffort: String?
    public var temperature: Double?
    public var maxTokens: Int?
    public var extraHeaders: [String: String]

    public init(
        baseURL: URL = URL(string: "https://api.deepseek.com")!,
        model: String = "deepseek-chat",
        apiKey: @escaping @Sendable () async throws -> String,
        reasoningEffort: String? = nil,
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        extraHeaders: [String: String] = [:]
    ) {
        self.baseURL = baseURL
        self.model = model
        self.apiKey = apiKey
        self.reasoningEffort = reasoningEffort
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.extraHeaders = extraHeaders
    }

    public var chatCompletionsURL: URL {
        baseURL.appendingPathComponent("chat/completions")
    }
}

/// DeepSeek 流式适配器（SSE + reasoning + tool_calls 增量 + usage）。
public final class DeepSeekProvider: LLMProvider, @unchecked Sendable {
    public let config: DeepSeekConfig
    private let client: SSEHTTPClient
    private let sessionConfiguration: URLSessionConfiguration

    public init(config: DeepSeekConfig, client: SSEHTTPClient = SSEHTTPClient()) {
        self.config = config
        self.client = client
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 1800
        configuration.httpAdditionalHeaders = ["Accept-Encoding": "gzip"]
        self.sessionConfiguration = configuration
    }

    public var name: String { "deepseek" }
    public var defaultModel: String { config.model }

    public func stream(_ request: ChatRequest) -> AsyncThrowingStream<StreamDelta, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let key = try await config.apiKey()
                    guard !key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw LLMFailure(kind: .invalidCredential, message: "Missing API key")
                    }
                    var urlRequest = try makeURLRequest(request, apiKey: key)
                    urlRequest.timeoutInterval = 90
                    var receivedAnything = false

                    for try await line in client.lines(for: urlRequest, sessionConfiguration: sessionConfiguration) {
                        try Task.checkCancellation()
                        guard line.hasPrefix("data:") else { continue }
                        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
                        if payload == "[DONE]" {
                            continuation.yield(.done)
                            continuation.finish()
                            return
                        }
                        guard let data = payload.data(using: .utf8) else { continue }
                        guard let chunk = try? DSHCoding.decoder().decode(WireChunk.self, from: data) else {
                            continue
                        }
                        if let usage = chunk.usage {
                            continuation.yield(.usage(LLMUsage(
                                promptTokens: usage.promptTokens ?? 0,
                                completionTokens: usage.completionTokens ?? 0,
                                promptCacheHitTokens: usage.promptCacheHitTokens ?? 0,
                                promptCacheMissTokens: usage.promptCacheMissTokens ?? 0
                            )))
                        }
                        guard let choice = chunk.choices?.first else { continue }
                        let delta = choice.delta
                        if let reasoning = delta.reasoningContent, !reasoning.isEmpty {
                            receivedAnything = true
                            continuation.yield(.reasoning(reasoning))
                        }
                        if let content = delta.content, !content.isEmpty {
                            receivedAnything = true
                            continuation.yield(.text(content))
                        }
                        if let calls = delta.toolCalls {
                            for call in calls {
                                receivedAnything = true
                                continuation.yield(.toolCall(
                                    index: call.index ?? 0,
                                    id: call.id,
                                    name: call.function?.name,
                                    arguments: call.function?.arguments ?? ""
                                ))
                            }
                        }
                    }

                    if !receivedAnything {
                        continuation.yield(.done)
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish(throwing: LLMFailure(kind: .cancelled, message: "Request cancelled"))
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func makeURLRequest(_ request: ChatRequest, apiKey: String) throws -> URLRequest {
        let wire = WireRequest(
            model: request.model.isEmpty ? config.model : request.model,
            messages: request.messages.map(WireMessage.init),
            tools: request.tools.isEmpty ? nil : request.tools.map(WireTool.init),
            temperature: request.temperature ?? config.temperature,
            maxTokens: request.maxTokens ?? config.maxTokens,
            reasoningEffort: config.reasoningEffort
        )
        var urlRequest = URLRequest(url: config.chatCompletionsURL)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        urlRequest.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        urlRequest.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        for (key, value) in config.extraHeaders {
            urlRequest.setValue(value, forHTTPHeaderField: key)
        }
        urlRequest.httpBody = try DSHCoding.encode(wire)
        return urlRequest
    }
}

// MARK: - Wire types

private struct WireRequest: Encodable {
    var model: String
    var messages: [WireMessage]
    var tools: [WireTool]?
    var temperature: Double?
    var maxTokens: Int?
    var reasoningEffort: String?
    var stream = true
    var streamOptions = WireStreamOptions(includeUsage: true)

    enum CodingKeys: String, CodingKey {
        case model, messages, tools, temperature, stream, streamOptions
        case maxTokens = "max_tokens"
        case reasoningEffort = "reasoning_effort"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(model, forKey: .model)
        try container.encode(messages, forKey: .messages)
        try container.encodeIfPresent(tools, forKey: .tools)
        try container.encodeIfPresent(temperature, forKey: .temperature)
        try container.encodeIfPresent(maxTokens, forKey: .maxTokens)
        try container.encodeIfPresent(reasoningEffort, forKey: .reasoningEffort)
        try container.encode(stream, forKey: .stream)
        try container.encode(streamOptions, forKey: .streamOptions)
    }
}

private struct WireStreamOptions: Encodable {
    var includeUsage: Bool
    enum CodingKeys: String, CodingKey { case includeUsage = "include_usage" }
}

private struct WireMessage: Encodable {
    var role: String
    var content: String
    var toolCalls: [WireToolCall]?
    var toolCallID: String?

    enum CodingKeys: String, CodingKey {
        case role, content
        case toolCalls = "tool_calls"
        case toolCallID = "tool_call_id"
    }

    init(_ message: LLMMessage) {
        role = message.role.rawValue
        content = message.content
        if !message.toolCalls.isEmpty {
            toolCalls = message.toolCalls.map(WireToolCall.init)
        }
        toolCallID = message.toolCallID
    }
}

private struct WireTool: Encodable {
    var type = "function"
    var function: WireFunction

    init(_ schema: ToolSchema) {
        function = WireFunction(name: schema.name, description: schema.description, parameters: schema.parameters)
    }
}

private struct WireFunction: Encodable {
    var name: String
    var description: String
    var parameters: JSONValue
}

private struct WireToolCall: Encodable {
    var id: String
    var type = "function"
    var function: WireToolCallFunction

    init(_ call: LLMToolCall) {
        id = call.id
        function = WireToolCallFunction(name: call.name, arguments: call.arguments)
    }
}

private struct WireToolCallFunction: Encodable {
    var name: String
    var arguments: String
}

private struct WireChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            var content: String?
            var reasoningContent: String?
            var toolCalls: [ToolCallDelta]?

            enum CodingKeys: String, CodingKey {
                case content
                case reasoningContent = "reasoning_content"
                case toolCalls = "tool_calls"
            }
        }
        var delta: Delta
    }

    struct ToolCallDelta: Decodable {
        struct Function: Decodable {
            var name: String?
            var arguments: String?
        }
        var index: Int?
        var id: String?
        var function: Function?
    }

    struct Usage: Decodable {
        var promptTokens: Int?
        var completionTokens: Int?
        var promptCacheHitTokens: Int?
        var promptCacheMissTokens: Int?

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case promptCacheHitTokens = "prompt_cache_hit_tokens"
            case promptCacheMissTokens = "prompt_cache_miss_tokens"
        }
    }

    var choices: [Choice]?
    var usage: Usage?
}

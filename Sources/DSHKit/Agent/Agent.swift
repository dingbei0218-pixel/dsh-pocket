import Foundation

public enum AgentError: Error, LocalizedError, Sendable {
    case busy
    case stepLimit(Int)
    case noProvider
    case emptyResponse

    public var errorDescription: String? {
        switch self {
        case .busy: return "Agent is already running a turn"
        case .stepLimit(let limit): return "Step limit reached (\(limit))"
        case .noProvider: return "No LLM provider configured"
        case .emptyResponse: return "The model returned an empty response"
        }
    }
}

public struct AgentConfig: Sendable {
    public var model: String
    public var temperature: Double?
    public var maxTokens: Int?
    public var maxSteps: Int
    public var maxRetries: Int
    public var contextWindow: Int
    public var compactionThreshold: Double
    public var customInstructions: String
    public var requestTimeout: TimeInterval

    public init(
        model: String = "deepseek-chat",
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        maxSteps: Int = 24,
        maxRetries: Int = 3,
        contextWindow: Int = 128_000,
        compactionThreshold: Double = 0.8,
        customInstructions: String = "",
        requestTimeout: TimeInterval = 120
    ) {
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.maxSteps = maxSteps
        self.maxRetries = maxRetries
        self.contextWindow = contextWindow
        self.compactionThreshold = compactionThreshold
        self.customInstructions = customInstructions
        self.requestTimeout = requestTimeout
    }
}

/// 进程内 Agent：Turn/Step 双循环 + 工具调用 + 审批 + 事件持久化。
///
/// 对应 dsh-go `pkg/agent` 的核心语义，但修掉了参考实现里几个「演示级简化」：
/// - 真正把 tool schema 发给模型；
/// - 把 assistant tool_calls 与 tool 结果回填进下一轮上下文；
/// - DeepSeek 增量 tool_calls 按 index 聚合（参考实现把每个分片当成完整调用）；
/// - 重试只在「尚未产生输出」时进行，避免重复文本。
public actor Agent {
    public nonisolated let sessionID: SessionID
    public nonisolated let workspace: URL

    private let log: SessionLog
    private let store: SessionStore?
    private let provider: LLMProvider
    private let tools: ToolRegistry
    private let sandbox: SandboxGuard
    private let config: AgentConfig
    private let approval: ApprovalHandler?
    private let promptBuilder: SystemPromptBuilder

    private var currentTask: Task<Void, Error>?
    private var isRunning = false

    public init(
        sessionID: SessionID,
        workspace: URL,
        log: SessionLog,
        store: SessionStore?,
        provider: LLMProvider,
        tools: ToolRegistry,
        sandbox: SandboxGuard,
        config: AgentConfig,
        approval: ApprovalHandler?
    ) {
        self.sessionID = sessionID
        self.workspace = workspace
        self.log = log
        self.store = store
        self.provider = provider
        self.tools = tools
        self.sandbox = sandbox
        self.config = config
        self.approval = approval
        self.promptBuilder = SystemPromptBuilder(customInstructions: config.customInstructions)
    }

    /// 打开（或创建）一个会话并恢复事件日志。
    public static func open(
        store: SessionStore,
        sessionID: SessionID,
        workspace: URL,
        provider: LLMProvider,
        tools: ToolRegistry,
        sandbox: SandboxGuard,
        config: AgentConfig,
        approval: ApprovalHandler?
    ) async throws -> Agent {
        let (header, events) = try await store.load(sessionID)
        let log = SessionLog(id: sessionID)
        try await log.restore(events)
        let resolvedWorkspace: URL
        if let cwd = header.cwd, !cwd.isEmpty {
            resolvedWorkspace = URL(fileURLWithPath: cwd)
        } else {
            resolvedWorkspace = workspace
        }
        return Agent(
            sessionID: sessionID,
            workspace: resolvedWorkspace,
            log: log,
            store: store,
            provider: provider,
            tools: tools,
            sandbox: sandbox,
            config: config,
            approval: approval
        )
    }

    public var running: Bool { isRunning }
    public func eventLog() -> SessionLog { log }
    public func projection() async -> SessionProjection {
        await log.projection()
    }
    public func events() async -> AsyncStream<SessionEvent> {
        await log.updates()
    }

    // MARK: - 入口

    /// 提交一个 turn 并异步执行（UI 用；立即返回）。
    public func send(_ text: String) throws {
        guard !isRunning else { throw AgentError.busy }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isRunning = true
        let task = Task { [weak self] in
            guard let self else { return }
            try await self.perform(text)
        }
        currentTask = task
    }

    /// 执行一个 turn 并等待完成（CLI / 测试用）。
    public func run(_ text: String) async throws {
        guard !isRunning else { throw AgentError.busy }
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isRunning = true
        let task = Task { [weak self] in
            guard let self else { return }
            try await self.perform(text)
        }
        currentTask = task
        do {
            try await task.value
        } catch {
            isRunning = false
            currentTask = nil
            throw error
        }
    }

    public func cancel() {
        currentTask?.cancel()
    }

    // MARK: - Turn / Step

    private func perform(_ input: String) async throws {
        defer {
            isRunning = false
            currentTask = nil
        }

        let turn = await log.nextTurnNumber
        var step: UInt64 = 1

        do {
            _ = try await emit(.turnStart(turn: turn))
            _ = try await emit(.userMessage(content: input, source: "run"))

            while true {
                guard step <= UInt64(config.maxSteps) else {
                    throw AgentError.stepLimit(config.maxSteps)
                }
                _ = try await emit(.stepStart(turn: turn, step: step))
                let hadTools: Bool
                do {
                    hadTools = try await runStep(turn: turn, step: step)
                    _ = try await emit(.stepEnd(turn: turn, step: step))
                } catch {
                    if await log.isStepOpen {
                        _ = try? await emit(.stepEnd(turn: turn, step: step))
                    }
                    throw error
                }
                if !hadTools { break }
                step += 1
            }

            _ = try await emit(.turnStopping(reason: "completed"))
            _ = try await emit(.turnEnd(turn: turn, reason: .completed))
            await maybeWriteTitle(input: input)
        } catch {
            let cancelled = isCancellation(error)
            if await log.isStepOpen {
                _ = try? await emit(.stepEnd(turn: turn, step: step))
            }
            _ = try? await emit(.agentError(
                message: cancelled ? "Turn cancelled by user" : error.localizedDescription,
                pkg: "DSHKit.Agent"
            ))
            if await log.isTurnOpen {
                _ = try? await emit(.turnEnd(turn: turn, reason: cancelled ? .aborted : .error))
            }
            throw error
        }
    }

    private func runStep(turn: UInt64, step: UInt64) async throws -> Bool {
        let snapshot = await log.snapshot()
        let projection = Fold.project(snapshot, sessionID: sessionID)
        let system = promptBuilder.build(workspace: workspace, sandbox: sandbox, tools: tools, projection: projection)
        var messages = buildMessages(from: Fold.effectiveEvents(snapshot))
        messages = trim(messages)

        let request = ChatRequest(
            model: config.model,
            system: system,
            messages: messages,
            tools: tools.schemas,
            temperature: config.temperature,
            maxTokens: config.maxTokens
        )

        _ = try await emit(.agentRequest(provider: provider.name, model: config.model))
        _ = try await emit(.llmRequest(provider: provider.name, model: config.model))
        if projection.turnCount <= 1, step == 1 {
            let headerHash = stableHash(system)
            _ = try? await emit(.requestHeader(
                configEpoch: 1,
                systemHash: headerHash,
                toolCount: tools.all.count
            ))
            _ = try? await emit(.requestContext(
                provider: provider.name,
                model: config.model,
                contextWindow: config.contextWindow,
                reason: "initial"
            ))
        }

        var text = ""
        var reasoning = ""
        var toolAccumulators: [Int: ToolCallAccumulator] = [:]
        var usage: LLMUsage?
        var receivedAnything = false
        var attempt = 0

        while true {
            do {
                for try await delta in provider.stream(request) {
                    try Task.checkCancellation()
                    switch delta {
                    case .text(let chunk):
                        receivedAnything = true
                        text += chunk
                        _ = try? await emit(.assistantChunk(text: chunk), sync: false)
                    case .reasoning(let chunk):
                        receivedAnything = true
                        reasoning += chunk
                        _ = try? await emit(.assistantReasoning(text: chunk), sync: false)
                    case .toolCall(let index, let id, let name, let arguments):
                        receivedAnything = true
                        var accumulator = toolAccumulators[index] ?? ToolCallAccumulator()
                        if let id, !id.isEmpty { accumulator.id = id }
                        if let name, !name.isEmpty { accumulator.name = name }
                        accumulator.arguments += arguments
                        toolAccumulators[index] = accumulator
                    case .usage(let value):
                        usage = value
                    case .done:
                        break
                    }
                }
                break
            } catch {
                if isCancellation(error) { throw CancellationError() }
                let failure = (error as? LLMFailure) ?? LLMFailure(kind: .unknown, message: error.localizedDescription)
                if failure.kind.isRetryable, !receivedAnything, attempt < config.maxRetries {
                    attempt += 1
                    let backoff = min(8_000, 400 * (1 << attempt))
                    _ = try? await emit(.llmRetry(attempt: attempt, backoffMs: Int64(backoff), error: failure.message))
                    try await Task.sleep(nanoseconds: UInt64(backoff) * 1_000_000)
                    continue
                }
                _ = try? await emit(.llmError(kind: failure.kind.rawValue, error: failure.message))
                throw failure
            }
        }

        let calls = toolAccumulators
            .sorted { $0.key < $1.key }
            .map { index, accumulator -> LLMToolCall in
                let id = accumulator.id.isEmpty ? "call_\(index)_\(UUID().uuidString.lowercased())" : accumulator.id
                return LLMToolCall(id: id, name: accumulator.name, arguments: accumulator.arguments)
            }

        if !receivedAnything && calls.isEmpty {
            let failure = LLMFailure(kind: .emptyResponse, message: "The model returned no content")
            _ = try? await emit(.llmError(kind: failure.kind.rawValue, error: failure.message))
            throw failure
        }

        let ids = calls.map(\.id)
        _ = try await emit(.assistantMessage(content: text, toolCallIDs: ids))

        let resolvedUsage = usage ?? LLMUsage(
            promptTokens: estimateTokens(request.messages.map(\.content).joined()),
            completionTokens: estimateTokens(text + reasoning)
        )
        _ = try? await emit(.llmDone(
            promptTokens: resolvedUsage.promptTokens,
            completionTokens: resolvedUsage.completionTokens
        ))

        for call in calls {
            await executeTool(call)
        }

        return !calls.isEmpty
    }

    // MARK: - 工具执行

    private func executeTool(_ call: LLMToolCall) async {
        let callID = ToolCallID(rawValue: call.id)
        let input = JSONValue.parse(call.arguments) ?? .object([:])
        _ = try? await emit(.toolCall(callID: callID, tool: call.name, input: input))

        guard let tool = tools.tool(named: call.name) else {
            _ = try? await emit(.toolResult(
                callID: callID,
                output: "Unknown tool: \(call.name). Available: \(tools.names.joined(separator: ", "))",
                isError: true
            ))
            return
        }

        let projection = await log.projection()
        let policy = projection.approvalPolicy ?? .askDangerous
        if ApprovalGate.requiresApproval(tool: tool, policy: policy) {
            let requestID = ApprovalRequestID.generate()
            let summary = ApprovalGate.summary(tool: tool, input: input)
            _ = try? await emit(.approvalAsked(requestID: requestID, tool: tool.name, summary: summary))
            let allowed: Bool
            if let approval {
                allowed = await approval(ApprovalRequest(
                    requestID: requestID,
                    tool: tool.name,
                    summary: summary,
                    input: input
                ))
            } else {
                allowed = false
            }
            _ = try? await emit(.approvalDecided(requestID: requestID, allowed: allowed))
            guard allowed else {
                _ = try? await emit(.toolResult(callID: callID, output: "Tool call denied by user.", isError: true))
                return
            }
        }

        let context = ToolContext(
            sessionID: sessionID,
            workspace: workspace,
            callID: callID,
            sandbox: sandbox,
            emit: { [weak self] data in
                guard let self else { return }
                _ = try? await self.emit(data, sync: false)
            }
        )

        do {
            let result = try await tool.execute(context, input)
            let limited = tools.truncate(
                result.output,
                callID: callID,
                spillDirectory: store.map { $0.root.appendingPathComponent(sessionID.rawValue).appendingPathComponent("spill") }
            )
            _ = try? await emit(.toolResult(
                callID: callID,
                output: limited.output,
                isError: result.isError || limited.isError,
                truncated: limited.truncated,
                spillPath: limited.spillPath
            ))
        } catch {
            let message = (error as? ToolError)?.message ?? error.localizedDescription
            _ = try? await emit(.toolResult(callID: callID, output: message, isError: true))
        }
    }

    // MARK: - 上下文组装

    private func buildMessages(from events: [SessionEvent]) -> [LLMMessage] {
        var toolMeta: [String: (name: String, input: JSONValue)] = [:]
        for event in events where event.type == .toolCall {
            guard let callID = event.callID else { continue }
            toolMeta[callID.rawValue] = (
                event.toolName ?? "tool",
                event.data["input"] ?? .object([:])
            )
        }

        var messages: [LLMMessage] = []
        for event in events {
            switch event.type {
            case .userMessage:
                messages.append(.user(event.content ?? ""))
            case .assistantMessage:
                let content = event.content ?? ""
                let ids = event.data["toolCallIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
                let calls = ids.compactMap { id -> LLMToolCall? in
                    guard let meta = toolMeta[id] else { return nil }
                    return LLMToolCall(id: id, name: meta.name, arguments: meta.input.jsonString())
                }
                if content.isEmpty && calls.isEmpty { continue }
                messages.append(.assistant(content, toolCalls: calls))
            case .toolResult:
                guard let callID = event.callID else { continue }
                messages.append(.tool(callID: callID.rawValue, event.output ?? ""))
            case .toolError:
                guard let callID = event.callID else { continue }
                messages.append(.tool(callID: callID.rawValue, "[tool error] " + (event.data["error"]?.stringValue ?? "")))
            default:
                break
            }
        }
        return messages
    }

    /// 请求级裁剪：只保留最近能放进上下文的完整尾部；不修改事件日志。
    private func trim(_ messages: [LLMMessage]) -> [LLMMessage] {
        let budget = Int(Double(config.contextWindow) * config.compactionThreshold * 3.2)
        var total = messages.reduce(0) { $0 + $1.content.count }
        guard total > budget else { return messages }

        var kept: [LLMMessage] = []
        var keptChars = 0
        for message in messages.reversed() {
            if !kept.isEmpty && keptChars + message.content.count > budget { break }
            kept.append(message)
            keptChars += message.content.count
        }
        kept.reverse()
        // 不要把孤立的 tool 消息放在最前面。
        while let first = kept.first, first.role == .tool { kept.removeFirst() }
        kept.insert(.user("[Earlier conversation was trimmed to fit the context window. Continue from the latest messages.]"), at: 0)
        total = kept.reduce(0) { $0 + $1.content.count }
        _ = total
        return kept
    }

    // MARK: - 事件

    @discardableResult
    private func emit(_ data: EventData, sync: Bool = true) async throws -> SessionEvent {
        let event = try await log.appendEvent(data)
        if let store {
            try await store.append(event, to: sessionID, sync: sync)
        }
        return event
    }

    private func maybeWriteTitle(input: String) async {
        let events = await log.snapshot()
        guard !events.contains(where: { $0.type == .sessionTitle }) else { return }
        let firstLine = input.split(separator: "\n").first.map(String.init) ?? input
        let title = String(firstLine.prefix(48))
        guard !title.isEmpty else { return }
        _ = try? await emit(.sessionTitle(title))
    }

    private func estimateTokens(_ text: String) -> Int {
        max(1, text.count / 4)
    }

    private func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let failure = error as? LLMFailure, failure.kind == .cancelled { return true }
        return false
    }
}

private struct ToolCallAccumulator {
    var id: String = ""
    var name: String = ""
    var arguments: String = ""
}

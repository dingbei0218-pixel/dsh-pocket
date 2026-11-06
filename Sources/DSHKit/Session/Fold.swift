import Foundation

/// 投影出的对话消息（供模型上下文组装）。
public struct ProjectedMessage: Sendable, Equatable, Identifiable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public var id: UInt64 { seq }
    public var seq: UInt64
    public var role: Role
    public var content: String
    public var toolCallIDs: [String]

    public init(seq: UInt64, role: Role, content: String, toolCallIDs: [String] = []) {
        self.seq = seq
        self.role = role
        self.content = content
        self.toolCallIDs = toolCallIDs
    }
}

/// 一次工具调用的完整生命周期（call → result/error）。
public struct ProjectedToolCall: Sendable, Equatable, Identifiable {
    public var id: ToolCallID { callID }
    public var callID: ToolCallID
    public var name: String
    public var input: JSONValue
    public var output: String?
    public var isError: Bool
    public var seq: UInt64
    public var finished: Bool

    public init(callID: ToolCallID, name: String, input: JSONValue, output: String? = nil, isError: Bool = false, seq: UInt64 = 0, finished: Bool = false) {
        self.callID = callID
        self.name = name
        self.input = input
        self.output = output
        self.isError = isError
        self.seq = seq
        self.finished = finished
    }
}

/// UI 可直接渲染的对话条目（已把 chunk 聚合成气泡、tool/result 配对成卡片）。
public struct ChatItem: Sendable, Equatable, Identifiable {
    public enum Kind: String, Sendable {
        case user
        case assistant
        case tool
        case error
    }

    public var id: String
    public var kind: Kind
    public var text: String
    public var reasoning: String
    public var time: Date
    public var toolName: String?
    public var toolInput: JSONValue?
    public var toolOutput: String?
    public var isError: Bool
    public var isStreaming: Bool

    public init(
        id: String,
        kind: Kind,
        text: String = "",
        reasoning: String = "",
        time: Date = Date(),
        toolName: String? = nil,
        toolInput: JSONValue? = nil,
        toolOutput: String? = nil,
        isError: Bool = false,
        isStreaming: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.text = text
        self.reasoning = reasoning
        self.time = time
        self.toolName = toolName
        self.toolInput = toolInput
        self.toolOutput = toolOutput
        self.isError = isError
        self.isStreaming = isStreaming
    }
}

public struct GoalState: Sendable, Equatable {
    public var id: String
    public var phase: GoalPhase
    public var description: String
    public var maxRounds: Int
    public var revision: UInt64
    public var rounds: Int
    public var blockReason: GoalBlockReason?

    public init(id: String, phase: GoalPhase, description: String = "", maxRounds: Int = 0, revision: UInt64 = 1, rounds: Int = 0, blockReason: GoalBlockReason? = nil) {
        self.id = id
        self.phase = phase
        self.description = description
        self.maxRounds = maxRounds
        self.revision = revision
        self.rounds = rounds
        self.blockReason = blockReason
    }
}

public struct PendingApproval: Sendable, Equatable {
    public var requestID: ApprovalRequestID
    public var tool: String
    public var summary: String

    public init(requestID: ApprovalRequestID, tool: String, summary: String) {
        self.requestID = requestID
        self.tool = tool
        self.summary = summary
    }
}

public struct UsageTotals: Sendable, Equatable {
    public var promptTokens: Int = 0
    public var completionTokens: Int = 0
    public var promptCacheHitTokens: Int = 0
    public var promptCacheMissTokens: Int = 0
    public var lastPromptTokens: Int = 0

    public var totalTokens: Int { promptTokens + completionTokens }
    public init() {}
}

/// 会话派生投影（纯函数，任何时刻重放事件即可得到相同结果）。
public struct SessionProjection: Sendable, Equatable {
    public var sessionID: SessionID
    public var items: [ChatItem] = []
    public var messages: [ProjectedMessage] = []
    public var toolCalls: [ProjectedToolCall] = []
    public var goal: GoalState?
    public var todos: [TodoItem] = []
    public var title: String?
    public var usage = UsageTotals()
    public var planMode = false
    public var preset: String?
    public var sandboxMode: SandboxMode?
    public var approvalPolicy: ApprovalPolicy?
    public var pendingApproval: PendingApproval?
    public var agentStatus: String?
    public var lastError: String?
    public var turnCount = 0
    public var openTurn: UInt64?
    public var isStreaming = false

    public init(sessionID: SessionID) {
        self.sessionID = sessionID
    }

    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        if let first = items.first(where: { $0.kind == .user }), !first.text.isEmpty {
            let line = first.text.split(separator: "\n").first.map(String.init) ?? first.text
            return String(line.prefix(48))
        }
        return "New chat"
    }

    public var lastAssistantText: String? {
        items.last(where: { $0.kind == .assistant && !$0.text.isEmpty })?.text
    }
}

public enum Fold {
    /// 应用 surface replace 后的有效事件序列。
    public static func effectiveEvents(_ events: [SessionEvent]) -> [SessionEvent] {
        var hidden = Set<UInt64>()
        for event in events {
            guard let op = event.surfaceOp, op.op == .replace,
                  let start = op.start, let end = op.end else { continue }
            var seq = start
            while seq <= end && seq <= event.seq {
                hidden.insert(seq)
                seq += 1
            }
        }
        return events.filter { !hidden.contains($0.seq) }
    }

    public static func project(_ events: [SessionEvent], sessionID: SessionID) -> SessionProjection {
        var projection = SessionProjection(sessionID: sessionID)
        let effective = effectiveEvents(events)
        var assistantCursor: Int?
        var toolCursor: [String: Int] = [:]
        var goalRounds = 0

        for event in effective {
            switch event.type {
            case .userMessage:
                projection.messages.append(.init(seq: event.seq, role: .user, content: event.content ?? ""))
                projection.items.append(ChatItem(
                    id: "user-\(event.seq)",
                    kind: .user,
                    text: event.content ?? "",
                    time: event.time
                ))
                assistantCursor = nil

            case .assistantChunk:
                let text = event.text ?? ""
                if let index = assistantCursor {
                    projection.items[index].text += text
                } else {
                    projection.items.append(ChatItem(
                        id: "assistant-\(event.seq)",
                        kind: .assistant,
                        text: text,
                        time: event.time,
                        isStreaming: true
                    ))
                    assistantCursor = projection.items.count - 1
                }

            case .assistantReasoning:
                let text = event.text ?? ""
                if let index = assistantCursor {
                    projection.items[index].reasoning += text
                } else {
                    projection.items.append(ChatItem(
                        id: "assistant-\(event.seq)",
                        kind: .assistant,
                        reasoning: text,
                        time: event.time,
                        isStreaming: true
                    ))
                    assistantCursor = projection.items.count - 1
                }

            case .assistantMessage:
                let content = event.content ?? ""
                let ids = event.data["toolCallIds"]?.arrayValue?.compactMap(\.stringValue) ?? []
                projection.messages.append(.init(seq: event.seq, role: .assistant, content: content, toolCallIDs: ids))
                if let index = assistantCursor {
                    projection.items[index].text = content
                    projection.items[index].isStreaming = false
                } else if !content.isEmpty {
                    projection.items.append(ChatItem(
                        id: "assistant-\(event.seq)",
                        kind: .assistant,
                        text: content,
                        time: event.time
                    ))
                    assistantCursor = projection.items.count - 1
                }

            case .toolCall:
                guard let callID = event.callID else { break }
                let name = event.toolName ?? "tool"
                let input = event.data["input"] ?? .object([:])
                projection.toolCalls.append(ProjectedToolCall(
                    callID: callID, name: name, input: input, seq: event.seq
                ))
                projection.items.append(ChatItem(
                    id: "tool-\(callID.rawValue)",
                    kind: .tool,
                    time: event.time,
                    toolName: name,
                    toolInput: input,
                    isStreaming: true
                ))
                toolCursor[callID.rawValue] = projection.items.count - 1
                assistantCursor = nil

            case .toolResult:
                guard let callID = event.callID else { break }
                applyToolResult(projection: &projection, toolCursor: toolCursor, callID: callID, output: event.output ?? "", isError: event.isError, time: event.time)

            case .toolError:
                guard let callID = event.callID else { break }
                let message = event.data["error"]?.stringValue ?? "tool failed"
                applyToolResult(projection: &projection, toolCursor: toolCursor, callID: callID, output: message, isError: true, time: event.time)

            case .agentError:
                let message = event.data["message"]?.stringValue ?? "agent error"
                projection.lastError = message
                projection.items.append(ChatItem(id: "error-\(event.seq)", kind: .error, text: message, time: event.time))

            case .llmError:
                let message = event.data["error"]?.stringValue ?? "llm error"
                projection.lastError = message

            case .goalChange:
                let id = event.data["goalId"]?.stringValue ?? "goal"
                let phase = GoalPhase(rawValue: event.data["phase"]?.stringValue ?? "") ?? .active
                let revision = event.data["revision"]?.uint64Value ?? 1
                if projection.goal == nil || revision >= (projection.goal?.revision ?? 0) {
                    var blockReason: GoalBlockReason?
                    if let raw = event.data["blockedReason"], let code = raw["code"]?.stringValue {
                        blockReason = GoalBlockReason(code: code, message: raw["message"]?.stringValue ?? "")
                    }
                    projection.goal = GoalState(
                        id: id,
                        phase: phase,
                        description: event.data["description"]?.stringValue ?? "",
                        maxRounds: event.data["maxRounds"]?.intValue ?? 0,
                        revision: revision,
                        rounds: goalRounds,
                        blockReason: blockReason
                    )
                }

            case .goalRound:
                goalRounds = event.data["round"]?.intValue ?? goalRounds
                projection.goal?.rounds = goalRounds

            case .todoWrite:
                let entries = event.data["entries"]?.arrayValue ?? []
                if entries.isEmpty {
                    let items = event.data["items"]?.arrayValue?.compactMap(\.stringValue) ?? []
                    projection.todos = items.map { TodoItem(content: $0) }
                } else {
                    projection.todos = entries.compactMap(TodoItem.init(json:))
                }

            case .sessionTitle:
                projection.title = event.data["title"]?.stringValue

            case .llmDone:
                let prompt = event.data["promptTokens"]?.intValue ?? 0
                let completion = event.data["completionTokens"]?.intValue ?? 0
                projection.usage.promptTokens += prompt
                projection.usage.completionTokens += completion
                projection.usage.lastPromptTokens = prompt

            case .planMode:
                projection.planMode = (event.data["mode"]?.stringValue == "on")

            case .presetChange:
                let preset = event.data["preset"]?.stringValue
                projection.preset = preset
                if let preset {
                    projection.sandboxMode = resolveSandboxMode(forPreset: preset)
                    projection.approvalPolicy = ApprovalPolicy.from(preset: preset)
                }

            case .sandboxMode:
                if let raw = event.data["mode"]?.stringValue, let mode = SandboxMode(rawValue: raw) {
                    projection.sandboxMode = mode
                }

            case .approvalAsked:
                guard let raw = event.data["requestId"]?.stringValue else { break }
                projection.pendingApproval = PendingApproval(
                    requestID: ApprovalRequestID(rawValue: raw),
                    tool: event.data["tool"]?.stringValue ?? "",
                    summary: event.data["summary"]?.stringValue ?? ""
                )

            case .approvalDecided:
                projection.pendingApproval = nil

            case .agentStatus:
                projection.agentStatus = event.data["status"]?.stringValue

            case .turnStart:
                projection.turnCount += 1
                projection.openTurn = event.turn
                projection.isStreaming = true

            case .turnEnd:
                projection.openTurn = nil
                projection.isStreaming = false
                if let index = assistantCursor {
                    projection.items[index].isStreaming = false
                }
                assistantCursor = nil

            default:
                break
            }
        }

        // 仍有未结束的流式块 → 标记
        if let index = assistantCursor {
            projection.items[index].isStreaming = projection.openTurn != nil
        }

        // 标题回退：取首条用户消息
        if projection.title == nil,
           let first = projection.items.first(where: { $0.kind == .user }) {
            let line = first.text.split(separator: "\n").first.map(String.init) ?? first.text
            if !line.isEmpty { projection.title = String(line.prefix(48)) }
        }

        return projection
    }

    private static func applyToolResult(
        projection: inout SessionProjection,
        toolCursor: [String: Int],
        callID: ToolCallID,
        output: String,
        isError: Bool,
        time: Date
    ) {
        if let index = toolCursor[callID.rawValue], projection.items.indices.contains(index) {
            projection.items[index].toolOutput = output
            projection.items[index].isError = isError
            projection.items[index].isStreaming = false
        } else {
            projection.items.append(ChatItem(
                id: "tool-\(callID.rawValue)",
                kind: .tool,
                time: time,
                toolName: "tool",
                toolOutput: output,
                isError: isError
            ))
        }
        if let index = projection.toolCalls.firstIndex(where: { $0.callID == callID }) {
            projection.toolCalls[index].output = output
            projection.toolCalls[index].isError = isError
            projection.toolCalls[index].finished = true
        }
    }
}


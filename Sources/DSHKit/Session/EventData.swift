import Foundation

/// 待办条目（对齐官方 TodoItem 三态）。
public struct TodoItem: Codable, Hashable, Sendable, Identifiable {
    public enum Status: String, Codable, Sendable, CaseIterable {
        case pending
        case inProgress = "in_progress"
        case completed
    }

    public var content: String
    public var status: Status
    public var id: String { content + "|" + status.rawValue }

    public init(content: String, status: Status = .pending) {
        self.content = content
        self.status = status
    }

    public var json: JSONValue {
        .object(["content": .string(content), "status": .string(status.rawValue)])
    }

    public init?(json: JSONValue) {
        guard let content = json["content"]?.stringValue else { return nil }
        let raw = json["status"]?.stringValue ?? Status.pending.rawValue
        self.content = content
        self.status = Status(rawValue: raw) ?? .pending
    }
}

/// 目标阻塞原因（官方 GoalBlockReason{code,message}）。
public struct GoalBlockReason: Codable, Hashable, Sendable {
    public var code: String
    public var message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }

    public var json: JSONValue { .object(["code": .string(code), "message": .string(message)]) }
}

/// 事件构造工厂：负责把强类型输入映射到与 dsh-go 一致的 JSON payload。
///
/// 只有 Agent / UI / 测试需要的核心事件有强类型 case；其余事件用 `.raw` 原样透传，
/// 既保留完整词汇表，又避免 56 个样板结构体。
public enum EventData: Sendable {
    // Turn / Step
    case turnStart(turn: UInt64)
    case turnEnd(turn: UInt64, reason: TurnEndReason)
    case turnStopping(reason: String?)
    case stepStart(turn: UInt64, step: UInt64)
    case stepEnd(turn: UInt64, step: UInt64)
    case agentError(message: String, pkg: String = "pkg/agent")
    case agentPreStep(blocked: Bool)
    case agentRequest(provider: String, model: String)
    case agentStatus(status: String)
    case agentInboxSpliced(target: String, start: Int, removedCount: Int, inserted: [String], outcome: String?)

    // 消息
    case userMessage(content: String, source: String? = nil)
    case assistantMessage(content: String, toolCallIDs: [String] = [])
    case assistantChunk(text: String)
    case assistantReasoning(text: String)
    case injectionContext(name: String, content: String, hash: String?)
    case sessionTitle(String)

    // 工具
    case toolCall(callID: ToolCallID, tool: String, input: JSONValue)
    case toolResult(callID: ToolCallID, output: String, isError: Bool = false, truncated: Bool = false, spillPath: String? = nil)
    case toolError(callID: ToolCallID, error: String)
    case toolObserved(callID: ToolCallID, kind: String)
    case toolPresentation(callID: ToolCallID, card: String)

    // 规划
    case planMode(on: Bool)
    case planApproval(approved: Bool)
    case goalChange(goalID: String, phase: GoalPhase, description: String, maxRounds: Int, revision: UInt64, blockedReason: GoalBlockReason? = nil)
    case goalRound(Int)
    case todoWrite(items: [TodoItem])
    case endSeed(parentSession: SessionID?)
    case planUpdate(content: String)

    // 请求与审批
    case requestHeader(configEpoch: UInt64, systemHash: String, toolCount: Int)
    case requestContext(provider: String, model: String, contextWindow: Int, reason: String)
    case approvalAsked(requestID: ApprovalRequestID, tool: String, summary: String)
    case approvalDecided(requestID: ApprovalRequestID, allowed: Bool)
    case presetChange(String)
    case agentPresetChange(String)
    case commandRun(command: String, args: String?)
    case commandDone(command: String)

    // LLM
    case llmRequest(provider: String, model: String)
    case llmStream(text: String)
    case llmRetry(attempt: Int, backoffMs: Int64, error: String)
    case llmError(kind: String, error: String)
    case llmDone(promptTokens: Int, completionTokens: Int)

    // 杂项
    case sandboxMode(mode: SandboxMode, source: String?)
    case userQuestion(question: String, answer: String?)
    case workspaceChange(workspaceID: WorkspaceID, root: String)
    case raw(EventType, JSONValue)

    public var type: EventType {
        switch self {
        case .turnStart: return .turnStart
        case .turnEnd: return .turnEnd
        case .turnStopping: return .turnStopping
        case .stepStart: return .stepStart
        case .stepEnd: return .stepEnd
        case .agentError: return .agentError
        case .agentPreStep: return .agentPreStep
        case .agentRequest: return .agentRequest
        case .agentStatus: return .agentStatus
        case .agentInboxSpliced: return .agentInboxSpliced
        case .userMessage: return .userMessage
        case .assistantMessage: return .assistantMessage
        case .assistantChunk: return .assistantChunk
        case .assistantReasoning: return .assistantReasoning
        case .injectionContext: return .injectionContext
        case .sessionTitle: return .sessionTitle
        case .toolCall: return .toolCall
        case .toolResult: return .toolResult
        case .toolError: return .toolError
        case .toolObserved: return .toolObserved
        case .toolPresentation: return .toolPresentation
        case .planMode: return .planMode
        case .planApproval: return .planApproval
        case .goalChange: return .goalChange
        case .goalRound: return .goalRound
        case .todoWrite: return .todoWrite
        case .endSeed: return .endSeed
        case .planUpdate: return .planUpdate
        case .requestHeader: return .requestHeader
        case .requestContext: return .requestContext
        case .approvalAsked: return .approvalAsked
        case .approvalDecided: return .approvalDecided
        case .presetChange: return .presetChange
        case .agentPresetChange: return .agentPresetChange
        case .commandRun: return .commandRun
        case .commandDone: return .commandDone
        case .llmRequest: return .llmRequest
        case .llmStream: return .llmStream
        case .llmRetry: return .llmRetry
        case .llmError: return .llmError
        case .llmDone: return .llmDone
        case .sandboxMode: return .sandboxMode
        case .userQuestion: return .userQuestion
        case .workspaceChange: return .workspaceChange
        case .raw(let type, _): return type
        }
    }

    public var payload: JSONValue {
        switch self {
        case .turnStart(let turn):
            return .object(["turn": .uint64(turn)])
        case .turnEnd(let turn, let reason):
            return .object(["turn": .uint64(turn), "reason": .string(reason.rawValue)])
        case .turnStopping(let reason):
            return reason.map { .object(["reason": .string($0)]) } ?? .object([:])
        case .stepStart(let turn, let step):
            return .object(["turn": .uint64(turn), "step": .uint64(step)])
        case .stepEnd(let turn, let step):
            return .object(["turn": .uint64(turn), "step": .uint64(step)])
        case .agentError(let message, let pkg):
            return .object(["message": .string(message), "pkg": .string(pkg)])
        case .agentPreStep(let blocked):
            return blocked ? .object(["blocked": .bool(true)]) : .object([:])
        case .agentRequest(let provider, let model):
            return .object(["provider": .string(provider), "model": .string(model)])
        case .agentStatus(let status):
            return .object(["status": .string(status)])
        case .agentInboxSpliced(let target, let start, let removed, let inserted, let outcome):
            var object: [String: JSONValue] = [
                "target": .string(target),
                "start": .int(start),
                "inserted": .array(inserted.map { .string($0) }),
            ]
            if removed != 0 { object["removedCount"] = .int(removed) }
            if let outcome { object["outcome"] = .string(outcome) }
            return .object(object)
        case .userMessage(let content, let source):
            var object: [String: JSONValue] = ["content": .string(content)]
            if let source, !source.isEmpty { object["source"] = .string(source) }
            return .object(object)
        case .assistantMessage(let content, let toolCallIDs):
            var object: [String: JSONValue] = ["content": .string(content)]
            if !toolCallIDs.isEmpty { object["toolCallIds"] = .array(toolCallIDs.map { .string($0) }) }
            return .object(object)
        case .assistantChunk(let text):
            return text.isEmpty ? .object([:]) : .object(["text": .string(text)])
        case .assistantReasoning(let text):
            return text.isEmpty ? .object([:]) : .object(["text": .string(text)])
        case .injectionContext(let name, let content, let hash):
            var object: [String: JSONValue] = ["name": .string(name), "content": .string(content)]
            if let hash { object["hash"] = .string(hash) }
            return .object(object)
        case .sessionTitle(let title):
            return .object(["title": .string(title)])
        case .toolCall(let callID, let tool, let input):
            return .object([
                "callId": .string(callID.rawValue),
                "tool": .string(tool),
                "input": input,
            ])
        case .toolResult(let callID, let output, let isError, let truncated, let spillPath):
            var object: [String: JSONValue] = [
                "callId": .string(callID.rawValue),
                "output": .string(output),
            ]
            if isError { object["isError"] = .bool(true) }
            if truncated { object["truncated"] = .bool(true) }
            if let spillPath { object["spillPath"] = .string(spillPath) }
            return .object(object)
        case .toolError(let callID, let error):
            return .object(["callId": .string(callID.rawValue), "error": .string(error)])
        case .toolObserved(let callID, let kind):
            return .object(["callId": .string(callID.rawValue), "kind": .string(kind)])
        case .toolPresentation(let callID, let card):
            return .object(["callId": .string(callID.rawValue), "card": .string(card)])
        case .planMode(let on):
            return .object(["mode": .string(on ? "on" : "off")])
        case .planApproval(let approved):
            return .object(["approved": .bool(approved)])
        case .goalChange(let goalID, let phase, let description, let maxRounds, let revision, let blockedReason):
            var object: [String: JSONValue] = [
                "goalId": .string(goalID),
                "phase": .string(phase.rawValue),
                "revision": .uint64(revision),
            ]
            if !description.isEmpty { object["description"] = .string(description) }
            if maxRounds != 0 { object["maxRounds"] = .int(maxRounds) }
            if let blockedReason { object["blockedReason"] = blockedReason.json }
            return .object(object)
        case .goalRound(let round):
            return .object(["round": .int(round)])
        case .todoWrite(let items):
            return .object([
                "entries": .array(items.map(\.json)),
                "items": .array(items.map { .string($0.content) }),
            ])
        case .endSeed(let parent):
            if let parent {
                return .object(["parentSession": .string(parent.rawValue)])
            }
            return .object([:])
        case .planUpdate(let content):
            if content.isEmpty { return .object([:]) }
            return .object(["content": .string(content)])
        case .requestHeader(let epoch, let hash, let count):
            var object: [String: JSONValue] = ["configEpoch": .uint64(epoch)]
            if !hash.isEmpty { object["systemHash"] = .string(hash) }
            if count != 0 { object["toolCount"] = .int(count) }
            return .object(object)
        case .requestContext(let provider, let model, let window, let reason):
            var object: [String: JSONValue] = [
                "provider": .string(provider),
                "model": .string(model),
                "reason": .string(reason),
            ]
            if window != 0 { object["contextWindow"] = .int(window) }
            return .object(object)
        case .approvalAsked(let requestID, let tool, let summary):
            return .object([
                "requestId": .string(requestID.rawValue),
                "tool": .string(tool),
                "summary": .string(summary),
            ])
        case .approvalDecided(let requestID, let allowed):
            return .object(["requestId": .string(requestID.rawValue), "allowed": .bool(allowed)])
        case .presetChange(let preset):
            return .object(["preset": .string(preset)])
        case .agentPresetChange(let preset):
            return .object(["preset": .string(preset)])
        case .commandRun(let command, let args):
            var object: [String: JSONValue] = ["command": .string(command)]
            if let args, !args.isEmpty { object["args"] = .string(args) }
            return .object(object)
        case .commandDone(let command):
            return .object(["command": .string(command)])
        case .llmRequest(let provider, let model):
            return .object(["provider": .string(provider), "model": .string(model)])
        case .llmStream(let text):
            return text.isEmpty ? .object([:]) : .object(["text": .string(text)])
        case .llmRetry(let attempt, let backoffMs, let error):
            return .object([
                "attempt": .int(attempt),
                "backoffMs": .int64(backoffMs),
                "error": .string(error),
            ])
        case .llmError(let kind, let error):
            return .object(["kind": .string(kind), "error": .string(error)])
        case .llmDone(let prompt, let completion):
            return .object([
                "promptTokens": .int(prompt),
                "completionTokens": .int(completion),
            ])
        case .sandboxMode(let mode, let source):
            var object: [String: JSONValue] = ["mode": .string(mode.rawValue)]
            if let source { object["source"] = .string(source) }
            return .object(object)
        case .userQuestion(let question, let answer):
            var object: [String: JSONValue] = ["question": .string(question)]
            if let answer { object["answer"] = .string(answer) }
            return .object(object)
        case .workspaceChange(let workspaceID, let root):
            return .object(["workspaceId": .string(workspaceID.rawValue), "root": .string(root)])
        case .raw(_, let json):
            return json
        }
    }
}

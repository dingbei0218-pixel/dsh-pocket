import Foundation

/// 事件类型。
///
/// 用 `struct + RawRepresentable` 而不是 `enum`，是为了：
/// - 与 dsh-go / 官方 DSH 的字符串词汇表逐字对齐；
/// - 未来新增事件（更高格式版本）可以被读取、原样保存，而不是解码失败。
public struct EventType: RawRepresentable, Codable, Hashable, Sendable, CustomStringConvertible {
    public let rawValue: String
    public init(rawValue: String) { self.rawValue = rawValue }
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }

    // 簇 A：Turn / Step 双循环
    public static let turnStart = EventType("turn/start")
    public static let turnEnd = EventType("turn/end")
    public static let turnStopping = EventType("turn/stopping")
    public static let stepStart = EventType("step/start")
    public static let stepEnd = EventType("step/end")
    public static let agentError = EventType("agent/error")
    public static let agentPreStep = EventType("agent/pre-step")
    public static let agentRequest = EventType("agent/request")
    public static let agentStatus = EventType("agent/status")
    public static let agentInboxSpliced = EventType("agent/inbox/spliced")

    // 簇 B：消息
    public static let userMessage = EventType("user/message")
    public static let assistantMessage = EventType("assistant/message")
    public static let assistantChunk = EventType("assistant/chunk")
    public static let assistantReasoning = EventType("assistant/reasoning")
    public static let injectionContext = EventType("injection/context")
    public static let sessionTitle = EventType("session/title")

    // 簇 C：工具
    public static let toolCall = EventType("tool/call")
    public static let toolResult = EventType("tool/result")
    public static let toolError = EventType("tool/error")
    public static let toolObserved = EventType("tool/observed")
    public static let toolPresentation = EventType("tool/presentation")

    // 簇 D：规划
    public static let planMode = EventType("plan/mode")
    public static let planApproval = EventType("plan/approval")
    public static let goalChange = EventType("goal/change")
    public static let goalRound = EventType("goal/round")
    public static let todoWrite = EventType("todo/write")
    public static let endSeed = EventType("session/end-seed")
    public static let planUpdate = EventType("project/plan-update")

    // 簇 E：请求与审批
    public static let requestHeader = EventType("request/header")
    public static let requestContext = EventType("request/context")
    public static let approvalAsked = EventType("approval/asked")
    public static let approvalDecided = EventType("approval/decided")
    public static let presetChange = EventType("permission/preset-change")
    public static let agentPresetChange = EventType("agent/preset-change")
    public static let commandRun = EventType("command/run")
    public static let commandDone = EventType("command/done")

    // 簇 F：文件系统
    public static let fsWriteIntent = EventType("fs/write-intent")
    public static let fsEditIntent = EventType("fs/edit-intent")
    public static let fsObserved = EventType("fs/observed")
    public static let fsVersionBump = EventType("fs/version-bump")
    public static let fsRead = EventType("fs/read")
    public static let fsDirList = EventType("fs/dir-list")

    // 簇 G：技能
    public static let skillsChange = EventType("skills/change")
    public static let skillsCatalog = EventType("skills/catalog")
    public static let skillInject = EventType("skill/inject")

    // 簇 H：LLM
    public static let llmRequest = EventType("llm/request")
    public static let llmStream = EventType("llm/stream")
    public static let llmRetry = EventType("llm/retry")
    public static let llmError = EventType("llm/error")
    public static let llmDone = EventType("llm/done")

    // 簇 I：表面替换与杂项
    public static let surfaceReplace = EventType("surface/replace")
    public static let attachmentAdded = EventType("attachment/added")
    public static let sessionProjectionUpdate = EventType("session/projection-updated")
    public static let workspaceChange = EventType("workspace/change")
    public static let userQuestion = EventType("user/question")
    public static let sandboxMode = EventType("sandbox/mode")

    /// 与 dsh-go `AllEventTypes` 对齐的完整词汇表（56 种）。
    public static let allKnown: [EventType] = [
        .turnStart, .turnEnd, .turnStopping, .stepStart, .stepEnd,
        .agentError, .agentPreStep, .agentRequest, .agentStatus, .agentInboxSpliced,
        .userMessage, .assistantMessage, .assistantChunk, .assistantReasoning,
        .injectionContext, .sessionTitle,
        .toolCall, .toolResult, .toolError, .toolObserved, .toolPresentation,
        .planMode, .planApproval, .goalChange, .goalRound, .todoWrite,
        .endSeed, .planUpdate,
        .requestHeader, .requestContext, .approvalAsked, .approvalDecided,
        .presetChange, .agentPresetChange, .commandRun, .commandDone,
        .fsWriteIntent, .fsEditIntent, .fsObserved, .fsVersionBump, .fsRead, .fsDirList,
        .skillsChange, .skillsCatalog, .skillInject,
        .llmRequest, .llmStream, .llmRetry, .llmError, .llmDone,
        .surfaceReplace, .attachmentAdded, .sessionProjectionUpdate, .workspaceChange,
        .userQuestion, .sandboxMode,
    ]

    public var isKnown: Bool { Self.knownSet.contains(self) }

    private static let knownSet = Set(allKnown)
}

/// Turn 关闭原因（对齐官方 `TurnEndReasonMap`）。
public enum TurnEndReason: String, Codable, Sendable {
    case completed
    case finished
    case interrupted
    case aborted
    case blocked
    case error
    case maxTokens = "max-tokens"
}

/// 目标阶段（dsh-go `goal.Phase` 四态）。
public enum GoalPhase: String, Codable, Sendable, CaseIterable {
    case active
    case paused
    case blocked
    case complete
}

/// 沙箱模式。
public enum SandboxMode: String, Codable, Sendable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

/// 审批策略。
public enum ApprovalPolicy: String, Codable, Sendable {
    case allowAll = "allow-all"
    case denyAll = "deny-all"
    case askDangerous = "ask-dangerous"
    case askDangerousToolEdit = "ask-dangerous-tool-edit"

    /// 由权限预设推导（对齐 dsh-go `presetApproval`）。
    public static func from(preset: String) -> ApprovalPolicy {
        switch preset {
        case "danger": return .allowAll
        case "review": return .askDangerousToolEdit
        default: return .askDangerous
        }
    }
}

/// 由权限预设推导沙箱模式（对齐 dsh-go `presetSandbox`）。
public func resolveSandboxMode(forPreset preset: String) -> SandboxMode {
    switch preset {
    case "safe", "review": return .readOnly
    case "danger": return .dangerFullAccess
    default: return .workspaceWrite
    }
}


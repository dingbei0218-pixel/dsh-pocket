import Foundation

/// 会话时序不变量违规。
public struct SessionInvariantError: Error, LocalizedError, Sendable, Equatable {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { "session invariant: \(message)" }
}

/// 事件溯源会话日志（唯一写入路径）。
///
/// 与 dsh-go `SessionLog` 对齐：
/// - `seq` 从 1 开始严格连续；
/// - `time` 单调不减；
/// - turn/step/tool 三类配对在 append 时即校验，违规立即拒绝且不消耗 seq；
/// - 读取方只能拿到快照（值语义），无法原地修改历史。
public actor SessionLog {
    public nonisolated let sessionID: SessionID

    private var events: [SessionEvent] = []
    private var seq: UInt64 = 0
    private var lastTime: Date = .distantPast
    private var observers: [UUID: AsyncStream<SessionEvent>.Continuation] = [:]

    // 开放结构状态
    private var turnOpen = false
    private var stepOpen = false
    private var openTurn: UInt64 = 0
    private var openStep: UInt64 = 0
    private var nextTurn: UInt64 = 0
    private var nextStep: UInt64 = 1
    private var toolCalls: [String: Bool] = [:] // callID -> 已有 result

    public init(id: SessionID) {
        self.sessionID = id
    }

    // MARK: - 读

    public var count: Int { events.count }
    public var lastSeq: UInt64 { seq }
    public var nextTurnNumber: UInt64 { nextTurn }
    public var nextStepNumber: UInt64 { nextStep }
    public var isTurnOpen: Bool { turnOpen }
    public var isStepOpen: Bool { stepOpen }

    public func snapshot() -> [SessionEvent] { events }

    public func openTurnNumber() -> UInt64? { turnOpen ? openTurn : nil }
    public func openStepNumber() -> UInt64? { stepOpen ? openStep : nil }

    /// 派生投影（全量 fold）。Apple 端事件量在数千级，O(n) 足够；
    /// 如需更大规模可替换为增量 Folder（接口保持不变）。
    public func projection() -> SessionProjection {
        Fold.project(events, sessionID: sessionID)
    }

    public func check() -> [String] {
        var errors: [String] = []
        if turnOpen { errors.append("unclosed turn at end of log") }
        if stepOpen { errors.append("unclosed step at end of log") }
        for (callID, done) in toolCalls where !done {
            errors.append("unmatched tool/call \(callID)")
        }
        return errors
    }

    // MARK: - 写

    /// 追加事件；返回完整事件（供持久化层落盘）。
    public func appendEvent(_ data: EventData, at time: Date = Date()) throws -> SessionEvent {
        let resolvedTime = max(time, lastTime)
        let candidate = SessionEvent(
            seq: seq + 1,
            time: resolvedTime,
            type: data.type,
            data: data.payload
        )
        try applyState(candidate)
        seq = candidate.seq
        lastTime = resolvedTime
        events.append(candidate)
        publish(candidate)
        return candidate
    }

    /// 追加事件；返回分配的 seq。
    @discardableResult
    public func append(_ data: EventData, at time: Date = Date()) throws -> UInt64 {
        try appendEvent(data, at: time).seq
    }

    /// 追加一条已经带 seq/time 的事件（导入、fork 种子、测试用）。
    /// 调用方须保证 seq 连续；失败会回滚状态。
    @discardableResult
    public func appendExisting(_ event: SessionEvent, validate: Bool = true) throws -> UInt64 {
        var candidate = event
        if validate, event.seq != seq + 1 {
            throw SessionInvariantError("non-contiguous seq: expected \(seq + 1), got \(event.seq)")
        }
        candidate.seq = seq + 1
        if candidate.time < lastTime { candidate.time = lastTime }
        if validate { try applyState(candidate) }
        seq = candidate.seq
        lastTime = candidate.time
        events.append(candidate)
        publish(candidate)
        return candidate.seq
    }

    /// 恢复：用已持久化的事件重建日志（会重放状态并校验配对）。
    /// - Parameter repair: 若结尾存在半开 turn/step/tool，自动补齐中断事件（崩溃修复）。
    public func restore(_ restored: [SessionEvent], repair: Bool = true) throws {
        var sorted = restored.sorted { $0.seq < $1.seq }
        if repair {
            repairOrphanTurnInternal(&sorted)
        }
        events = []
        seq = 0
        resetState()
        for event in sorted {
            try appendExisting(event, validate: true)
        }
    }

    /// 崩溃修复：补齐未闭合的 tool/result、step/end、turn/end。
    /// 对齐 dsh-go `repairOrphanTurn`：保留已写入的 chunk/tool 事件，只补配对。
    @discardableResult
    public func repairOrphanTurn() -> Int {
        var copy = events
        let changed = repairOrphanTurnInternal(&copy)
        if changed > 0 {
            // 修复只追加尾部事件；用 restore 重放，保证状态一致。
            try? restore(copy, repair: false)
        }
        return changed
    }

    /// 压缩：把 `[start, end]` 这段历史替换成一条摘要（surface replace）。
    ///
    /// 源事件保持不可变；fold 在读取时隐藏该区间。这是 compaction 唯一合法写路径。
    @discardableResult
    public func appendSurfaceReplace(start: UInt64, end: UInt64, summary: String, at time: Date = Date()) throws -> UInt64 {
        guard start >= 1, start <= end else {
            throw SessionInvariantError("surface/replace invalid range \(start)...\(end)")
        }
        guard end < seq + 1 else {
            throw SessionInvariantError("surface/replace range \(start)...\(end) exceeds current seq \(seq)")
        }
        let payload: JSONValue = .object([
            "start": .uint64(start),
            "end": .uint64(end),
            "data": .object(["summary": .string(summary)]),
        ])
        let event = SessionEvent(
            seq: seq + 1,
            time: max(time, lastTime),
            type: .surfaceReplace,
            data: payload,
            surfaceOp: SurfaceOp(op: .replace, start: start, end: end, data: .object(["summary": .string(summary)]))
        )
        // surface/replace 不改变 turn/step 状态
        seq = event.seq
        lastTime = event.time
        events.append(event)
        publish(event)
        return event.seq
    }

    // MARK: - 观察

    /// 事件流。UI / CLI 可订阅做增量刷新；终止后自动移除。
    public func updates() -> AsyncStream<SessionEvent> {
        AsyncStream { continuation in
            let token = UUID()
            observers[token] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(token) }
            }
        }
    }

    private func publish(_ event: SessionEvent) {
        for continuation in observers.values {
            continuation.yield(event)
        }
    }

    private func removeObserver(_ token: UUID) {
        observers[token] = nil
    }

    // MARK: - 状态机

    private func resetState() {
        turnOpen = false
        stepOpen = false
        openTurn = 0
        openStep = 0
        nextTurn = 0
        nextStep = 1
        toolCalls = [:]
        lastTime = .distantPast
    }

    private func applyState(_ event: SessionEvent) throws {
        switch event.type {
        case .turnStart:
            guard !turnOpen else { throw SessionInvariantError("turn/start while turn already open") }
            let turn = event.turn ?? 0
            guard turn == nextTurn else {
                throw SessionInvariantError("turn/start expected turn \(nextTurn), got \(turn)")
            }
            turnOpen = true
            openTurn = turn
            nextStep = 1

        case .turnEnd:
            guard turnOpen else { throw SessionInvariantError("turn/end without open turn/start") }
            guard !stepOpen else { throw SessionInvariantError("turn/end while step still open") }
            let turn = event.turn ?? 0
            guard turn == openTurn else {
                throw SessionInvariantError("turn/end turn \(turn) does not match open turn \(openTurn)")
            }
            turnOpen = false
            openTurn = 0
            nextTurn += 1

        case .turnStopping:
            guard turnOpen else { throw SessionInvariantError("turn/stopping without open turn") }

        case .stepStart:
            guard turnOpen else { throw SessionInvariantError("step/start without open turn") }
            guard !stepOpen else { throw SessionInvariantError("step/start while step already open") }
            let turn = event.turn ?? 0
            let step = event.step ?? 0
            guard turn == openTurn else {
                throw SessionInvariantError("step/start in turn \(turn) but open turn is \(openTurn)")
            }
            guard step == nextStep else {
                throw SessionInvariantError("step/start expected step \(nextStep), got \(step)")
            }
            stepOpen = true
            openStep = step
            nextStep += 1

        case .stepEnd:
            guard stepOpen else { throw SessionInvariantError("step/end without open step/start") }
            let turn = event.turn ?? 0
            let step = event.step ?? 0
            guard turn == openTurn else {
                throw SessionInvariantError("step/end in turn \(turn) but open turn is \(openTurn)")
            }
            guard step == openStep else {
                throw SessionInvariantError("step/end step \(step) does not match open step \(openStep)")
            }
            stepOpen = false
            openStep = 0

        case .toolCall:
            guard stepOpen else { throw SessionInvariantError("tool/call without open step") }
            guard let callID = event.callID else {
                throw SessionInvariantError("tool/call missing callId")
            }
            guard toolCalls[callID.rawValue] == nil else {
                throw SessionInvariantError("duplicate tool/call \(callID.rawValue)")
            }
            toolCalls[callID.rawValue] = false

        case .toolResult, .toolError:
            guard let callID = event.callID else {
                throw SessionInvariantError("tool result missing callId")
            }
            guard let open = toolCalls[callID.rawValue] else {
                throw SessionInvariantError("tool/result for unknown call \(callID.rawValue)")
            }
            guard !open else {
                throw SessionInvariantError("duplicate tool/result for call \(callID.rawValue)")
            }
            toolCalls[callID.rawValue] = true

        default:
            break
        }
    }

    // MARK: - 崩溃修复实现

    private func repairOrphanTurnInternal(_ events: inout [SessionEvent]) -> Int {
        guard let last = events.last else { return 0 }
        var repaired = 0
        var nextSeq = last.seq + 1
        let now = max(last.time, Date())

        // 1) 未闭合的工具调用：补 tool/result。
        var openCalls: [String] = []
        for event in events {
            switch event.type {
            case .toolCall:
                if let id = event.callID?.rawValue, !openCalls.contains(id) { openCalls.append(id) }
            case .toolResult, .toolError:
                if let id = event.callID?.rawValue { openCalls.removeAll { $0 == id } }
            default: break
            }
        }
        for callID in openCalls {
            events.append(SessionEvent(
                seq: nextSeq,
                time: now,
                type: .toolResult,
                data: EventData.toolResult(
                    callID: ToolCallID(rawValue: callID),
                    output: "[interrupted before tool result was persisted]",
                    isError: true
                ).payload
            ))
            nextSeq += 1
            repaired += 1
        }

        // 2) 未闭合的 step。
        if SessionLog.openStep(in: events) {
            let turn = SessionLog.openTurn(in: events) ?? 0
            let step = SessionLog.lastOpenStepNumber(in: events) ?? 1
            events.append(SessionEvent(
                seq: nextSeq,
                time: now,
                type: .stepEnd,
                data: EventData.stepEnd(turn: turn, step: step).payload
            ))
            nextSeq += 1
            repaired += 1
        }

        // 3) 未闭合的 turn。
        if let turn = SessionLog.openTurn(in: events) {
            events.append(SessionEvent(
                seq: nextSeq,
                time: now,
                type: .turnEnd,
                data: EventData.turnEnd(turn: turn, reason: .interrupted).payload
            ))
            repaired += 1
        }
        return repaired
    }

    private static func openTurn(in events: [SessionEvent]) -> UInt64? {
        var open = false
        var turn: UInt64 = 0
        var stepOpen = false
        for event in events {
            switch event.type {
            case .turnStart:
                open = true
                turn = event.turn ?? 0
            case .turnEnd:
                open = false
                stepOpen = false
            case .stepStart:
                stepOpen = true
            case .stepEnd:
                stepOpen = false
            default: break
            }
        }
        return open && !stepOpen ? turn : nil
    }

    private static func openStep(in events: [SessionEvent]) -> Bool {
        var open = false
        for event in events {
            switch event.type {
            case .stepStart: open = true
            case .stepEnd: open = false
            default: break
            }
        }
        return open
    }

    private static func lastOpenStepNumber(in events: [SessionEvent]) -> UInt64? {
        var step: UInt64?
        for event in events {
            switch event.type {
            case .stepStart: step = event.step
            case .stepEnd: step = nil
            default: break
            }
        }
        return step
    }
}

// MARK: - 便捷方法

public extension SessionLog {
    func appendTurnStart(turn: UInt64) async throws { _ = try await append(.turnStart(turn: turn)) }
    func appendTurnEnd(turn: UInt64, reason: TurnEndReason) async throws { _ = try await append(.turnEnd(turn: turn, reason: reason)) }
    func appendUser(_ text: String, source: String = "run") async throws { _ = try await append(.userMessage(content: text, source: source)) }
}


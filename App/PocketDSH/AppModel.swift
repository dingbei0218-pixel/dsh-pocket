import Foundation
import Combine
import DSHKit

@MainActor
final class AppModel: ObservableObject {
    // 会话
    @Published private(set) var sessions: [SessionSummary] = []
    @Published private(set) var projection: SessionProjection?
    @Published private(set) var currentID: SessionID?
    @Published private(set) var isRunning = false
    @Published private(set) var pinned: Set<String> = []
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var showTodos = false
    @Published var showGoal = false
    @Published var showSkinCenter = false
    @Published var startInDetail = false

    // 配置
    @Published var config: DSHConfig {
        didSet { persistConfig() }
    }
    @Published private(set) var hasAPIKey = false

    let approvals = ApprovalBroker()

    private let store: SessionStore
    private let keyStore = KeychainAPIKeyStore()
    private let defaults = UserDefaults.standard
    private let configKey = "dsh.config.v1"
    private let pinnedKey = "dsh.sessions.pinned"
    private var agent: Agent? = nil
    private var eventTask: Task<Void, Never>? = nil
    private var chunkCounter = 0

    let workspace: URL

    init() {
        if let data = UserDefaults.standard.data(forKey: "dsh.config.v1"),
           let decoded = try? JSONDecoder().decode(DSHConfig.self, from: data) {
            config = decoded
        } else {
            config = .default
        }

        // iOS：放在 Documents 下，用户可以在「文件」App 里直接查看/导入工作区文件。
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
        let root = documents.appendingPathComponent("DSH", isDirectory: true)
        workspace = root.appendingPathComponent("Workspace", isDirectory: true)
        store = SessionStore(root: root.appendingPathComponent("sessions", isDirectory: true))

        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        pinned = Set(UserDefaults.standard.stringArray(forKey: "dsh.sessions.pinned") ?? [])

        Task {
            await self.bootstrap()
        }
    }

    // MARK: - 启动

    func bootstrap() async {
        hasAPIKey = (await keyStore.apiKey())?.isEmpty == false
        await refreshSessions()
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-demo") {
            await createDemoSession()
        }
        if ProcessInfo.processInfo.arguments.contains("-newchat") {
            await createSession()
            startInDetail = true
        }
        if ProcessInfo.processInfo.arguments.contains("-skins") {
            showSkinCenter = true
        }
        if ProcessInfo.processInfo.arguments.contains("-settings") {
            showSettings = true
        }
        #endif
    }

    func refreshSessions() async {
        do {
            let list = try await store.listSessions()
            sessions = list.sorted { lhs, rhs in
                let lp = pinned.contains(lhs.id.rawValue)
                let rp = pinned.contains(rhs.id.rawValue)
                if lp != rp { return lp }
                return lhs.updatedAt > rhs.updatedAt
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    var modelDisplayName: String {
        switch config.model {
        case "deepseek-chat": return "DeepSeek Chat"
        case "deepseek-reasoner": return "DeepSeek Reasoner"
        default: return config.model
        }
    }

    var permissionDisplayName: String {
        switch config.permissionPreset {
        case "safe": return "只读"
        case "review": return "改前确认"
        case "danger": return "完全权限"
        default: return "工作区写入"
        }
    }

    func isPinned(_ id: SessionID) -> Bool {
        pinned.contains(id.rawValue)
    }

    func togglePin(_ id: SessionID) async {
        if pinned.contains(id.rawValue) {
            pinned.remove(id.rawValue)
        } else {
            pinned.insert(id.rawValue)
        }
        defaults.set(Array(pinned), forKey: pinnedKey)
        await refreshSessions()
    }

    // MARK: - 会话生命周期

    func createSession() async {
        do {
            let agent = try await DSHFactory.createAgent(
                store: store,
                workspace: workspace,
                config: config,
                keyStore: keyStore,
                approval: approvalHandler
            )
            activate(agent: agent)
            await refreshSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func open(_ summary: SessionSummary) async {
        guard summary.id != currentID || agent == nil else { return }
        do {
            let agent = try await DSHFactory.openAgent(
                store: store,
                sessionID: summary.id,
                workspace: workspace,
                config: config,
                keyStore: keyStore,
                approval: approvalHandler
            )
            activate(agent: agent)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ summary: SessionSummary) async {
        do {
            try await store.deleteSession(summary.id)
            if currentID == summary.id {
                eventTask?.cancel()
                agent = nil
                projection = nil
                currentID = nil
            }
            await refreshSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if DEBUG
    /// 仅用于模拟器演示/截图：没有 API Key 也能看到完整对话界面。
    func createDemoSession() async {
        do {
            let header = try await store.createSession(cwd: workspace.path)
            let log = SessionLog(id: header.id)
            let markdown = """
            我按 DSH Desktop 的视觉层级重做了一版，核心是三个 token 层：

            | 层级 | 用途 | 颜色 |
            |---|---|---|
            | base | 画布 | #151517 |
            | layer-1 | 侧栏 / 卡片 | #232323 |
            | layer-2 | 输入卡 | #2c2c2e |

            皮肤从 Git 同步，`skin.css` 里的 `--dsw-alias-*` 直接映射到 SwiftUI：

            ```swift
            let theme = AppTheme(manifest: manifest, tokens: SkinCSS.tokens(from: css))
            ```

            工具调用和审批、语音输入、文件导入也都接上了。
            """
            try await log.append(.turnStart(turn: 0))
            try await log.append(.userMessage(content: "默认跟 DSH Mac 版一样，能同步 Git 上的皮肤，交互再顺一点。"))
            try await log.append(.stepStart(turn: 0, step: 1))
            try await log.append(.assistantReasoning(text: "先对齐桌面版的 token 与布局，再补皮肤中心和移动端交互。"))
            try await log.append(.assistantMessage(content: markdown))
            try await log.append(.toolCall(callID: "call_demo", tool: "read_file", input: .object(["path": .string("App/PocketDSH/Skin/AppTheme.swift")])))
            try await log.append(.toolResult(callID: "call_demo", output: "AppTheme.swift · 297 lines · 4.2 KB"))
            try await log.append(.stepEnd(turn: 0, step: 1))
            try await log.append(.turnStopping(reason: "completed"))
            try await log.append(.turnEnd(turn: 0, reason: .completed))
            try await log.append(.sessionTitle("DSH 风格与皮肤系统"))
            for event in await log.snapshot() {
                try await store.append(event, to: header.id)
            }
            let agent = try await DSHFactory.openAgent(
                store: store,
                sessionID: header.id,
                workspace: workspace,
                config: config,
                keyStore: keyStore,
                approval: approvalHandler
            )
            activate(agent: agent)
            startInDetail = true
            await refreshSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    #endif

    func rename(session: SessionSummary, to title: String) async {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if session.id != currentID { await open(session) }
        guard let agent, session.id == currentID else { return }
        let log = await agent.eventLog()
        _ = try? await log.append(.sessionTitle(trimmed))
        await refreshProjection()
        await refreshSessions()
    }

    func renameCurrent(_ title: String) async {
        guard let agent, !title.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let log = await agent.eventLog()
        _ = try? await log.append(.sessionTitle(title))
        await refreshProjection()
        await refreshSessions()
    }

    private func activate(agent: Agent) {
        eventTask?.cancel()
        self.agent = agent
        currentID = agent.sessionID
        isRunning = false
        projection = nil
        observe(agent)
        Task {
            await refreshProjection()
            await refreshSessions()
        }
    }

    private func observe(_ agent: Agent) {
        eventTask = Task { [weak self] in
            let stream = await agent.events()
            for await event in stream {
                guard !Task.isCancelled else { break }
                await self?.handle(event, from: agent)
            }
        }
    }

    private func handle(_ event: SessionEvent, from agent: Agent) async {
        switch event.type {
        case .assistantChunk, .assistantReasoning, .llmStream:
            chunkCounter += 1
            if chunkCounter % 6 == 0 { await refreshProjection() }
        case .turnEnd:
            isRunning = false
            await refreshProjection()
            await refreshSessions()
        case .agentError, .llmError:
            isRunning = false
            await refreshProjection()
        case .toolCall, .toolResult, .approvalAsked, .goalChange, .todoWrite:
            await refreshProjection()
        default:
            break
        }
        _ = agent
    }

    func refreshProjection() async {
        guard let agent else { return }
        projection = await agent.projection()
        isRunning = await agent.running
    }

    // MARK: - 发送 / 停止

    func send(_ text: String) async {
        if agent == nil {
            await createSession()
        }
        guard let agent else { return }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isRunning = true
        do {
            try await agent.send(trimmed)
            await refreshProjection()
        } catch {
            isRunning = false
            errorMessage = error.localizedDescription
        }
    }

    func stop() async {
        await agent?.cancel()
    }

    func respondToApproval(_ allowed: Bool) {
        approvals.resolve(allowed)
    }

    // MARK: - Goal

    func setGoal(_ description: String, maxRounds: Int) async {
        guard let agent, !description.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        let log = await agent.eventLog()
        let revision = (projection?.goal?.revision ?? 0) + 1
        let id = projection?.goal?.id ?? "goal_\(UUID().uuidString.lowercased())"
        _ = try? await log.append(.goalChange(
            goalID: id,
            phase: .active,
            description: description,
            maxRounds: maxRounds,
            revision: revision
        ))
        await refreshProjection()
    }

    func clearGoal() async {
        guard let agent, let goal = projection?.goal else { return }
        let log = await agent.eventLog()
        _ = try? await log.append(.goalChange(
            goalID: goal.id,
            phase: .complete,
            description: goal.description,
            maxRounds: goal.maxRounds,
            revision: goal.revision + 1
        ))
        await refreshProjection()
    }

    // MARK: - 设置

    func saveAPIKey(_ key: String) async {
        do {
            if key.isEmpty {
                try await keyStore.clearAPIKey()
                hasAPIKey = false
            } else {
                try await keyStore.setAPIKey(key)
                hasAPIKey = true
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func loadAPIKey() async -> String {
        (await keyStore.apiKey()) ?? ""
    }

    private func persistConfig() {
        if let data = try? JSONEncoder().encode(config) {
            defaults.set(data, forKey: configKey)
        }
        // 配置变化后，下一次新建会话生效；当前会话保持其既有 sandbox/model。
    }

    private var approvalHandler: ApprovalHandler {
        { [weak self] request in
            guard let self else { return false }
            return await self.approvals.request(request)
        }
    }
}


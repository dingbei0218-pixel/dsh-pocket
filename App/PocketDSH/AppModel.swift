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
    @Published var errorMessage: String?
    @Published var showSettings = false
    @Published var showTodos = false
    @Published var showGoal = false

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
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Documents")
        let root = documents.appendingPathComponent("DSH", isDirectory: true)
        workspace = root.appendingPathComponent("Workspace", isDirectory: true)
        store = SessionStore(root: root.appendingPathComponent("sessions", isDirectory: true))

        try? FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        Task {
            await self.bootstrap()
        }
    }

    // MARK: - 启动

    func bootstrap() async {
        hasAPIKey = (await keyStore.apiKey())?.isEmpty == false
        await refreshSessions()
    }

    func refreshSessions() async {
        do {
            sessions = try await store.listSessions()
        } catch {
            errorMessage = error.localizedDescription
        }
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


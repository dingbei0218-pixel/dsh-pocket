import Foundation

/// 组装 provider / tools / agent 的便捷工厂。
public enum DSHFactory {
    public static func provider(config: DSHConfig, keyStore: APIKeyStore) throws -> LLMProvider {
        try config.provider {
            try await keyStore.apiKey() ?? ""
        }
    }

    public static func openAgent(
        store: SessionStore,
        sessionID: SessionID,
        workspace: URL,
        config: DSHConfig,
        keyStore: APIKeyStore,
        approval: ApprovalHandler?,
        extraTools: [Tool] = []
    ) async throws -> Agent {
        let provider = try provider(config: config, keyStore: keyStore)
        var tools = config.tools()
        for tool in extraTools { tools.register(tool) }
        return try await Agent.open(
            store: store,
            sessionID: sessionID,
            workspace: workspace,
            provider: provider,
            tools: tools,
            sandbox: SandboxGuard(root: workspace, mode: config.sandboxMode),
            config: config.agentConfig,
            approval: approval
        )
    }

    /// 新会话：创建 header 后立即打开 Agent。
    public static func createAgent(
        store: SessionStore,
        workspace: URL,
        config: DSHConfig,
        keyStore: APIKeyStore,
        approval: ApprovalHandler?,
        extraTools: [Tool] = []
    ) async throws -> Agent {
        let header = try await store.createSession(cwd: workspace.path)
        return try await openAgent(
            store: store,
            sessionID: header.id,
            workspace: workspace,
            config: config,
            keyStore: keyStore,
            approval: approval,
            extraTools: extraTools
        )
    }
}

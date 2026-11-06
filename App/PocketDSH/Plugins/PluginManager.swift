import Foundation
import Combine
import DSHKit

struct FunctionPlugin: Identifiable, Codable, Hashable {
    enum Kind: String, Codable { case skill, mcp, tool }
    var id: String
    var name: String
    var summary: String
    var detail: String
    var kind: Kind
    var author: String
    var version: String
    var tags: [String]
    var prompt: String?
}

struct MCPServerConfig: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var url: String
    var token: String
    var enabled: Bool
    var toolCount: Int
}

@MainActor
final class PluginManager: ObservableObject {
    @Published private(set) var installedSkills: Set<String>
    @Published private(set) var mcpServers: [MCPServerConfig]
    @Published private(set) var mcpTools: [String: [MCPToolInfo]] = [:]
    @Published var errorMessage: String?

    private let defaults = UserDefaults.standard
    private let installedKey = "dsh.plugins.skills"
    private let mcpKey = "dsh.plugins.mcp"

    let skills: [FunctionPlugin] = [
        FunctionPlugin(
            id: "code-review",
            name: "严格代码审查",
            summary: "先找风险，再给可执行的 patch 建议",
            detail: "按正确性、并发、边界条件、错误处理、性能与可维护性分档；每条问题给出文件/行为/修复方向，不泛泛而谈。",
            kind: .skill, author: "DSH Pocket", version: "1.0.0", tags: ["代码", "审查"],
            prompt: "你是一名严格的高级代码审查员。审查时先列出会导致错误、数据损坏、安全问题或并发问题的缺陷，再列可维护性问题；每条给出具体文件/函数、触发条件和修复方向。不要用泛泛的风格建议凑数。"
        ),
        FunctionPlugin(
            id: "commit-writer",
            name: "提交信息生成",
            summary: "从 diff 生成 Conventional Commits",
            detail: "读取改动，按 feat/fix/refactor/docs/test/chore 归类，标题控制在 72 字符内，正文说明动机与验证。",
            kind: .skill, author: "DSH Pocket", version: "1.0.0", tags: ["Git", "写作"],
            prompt: "根据当前改动生成一条 Conventional Commits 提交信息：标题不超过 72 字符，使用 feat/fix/refactor/docs/test/chore 前缀；正文说明动机、行为变化和验证方式。不要编造未发生的改动。"
        ),
        FunctionPlugin(
            id: "tech-writer",
            name: "技术写作",
            summary: "把实现讲成可读的文档",
            detail: "先给结论，再给结构；代码、命令、边界条件分开写；避免营销词和空泛总结。",
            kind: .skill, author: "DSH Pocket", version: "1.0.0", tags: ["写作", "文档"],
            prompt: "你是一名技术文档作者。先给结论，再给必要的背景、步骤和边界条件；代码、命令、配置分开呈现；避免营销词、空泛总结和重复。读者是能看懂代码的工程师。"
        ),
        FunctionPlugin(
            id: "ashare-review",
            name: "A 股复盘",
            summary: "按情绪、资金、主线、个股四层复盘",
            detail: "先给市场环境结论，再拆涨停结构、资金流向、主线延续性与次日验证点；区分事实与推断。",
            kind: .skill, author: "DSH Pocket", version: "1.0.0", tags: ["交易", "复盘"],
            prompt: "你是 A 股复盘助手。按市场情绪、资金面、主线结构、个股强弱四层分析；先给结论，再给证据和次日验证点；严格区分盘面事实与推断，不把传闻当事实。"
        ),
        FunctionPlugin(
            id: "translator",
            name: "中英翻译润色",
            summary: "保留技术含义的自然翻译",
            detail: "术语保持一致，代码/命令不翻译；先准确，再自然，不扩写原文没有的信息。",
            kind: .skill, author: "DSH Pocket", version: "1.0.0", tags: ["翻译", "写作"],
            prompt: "中英互译时保留技术术语、代码、命令和标识符；先保证含义准确，再让表达自然；不增删原文没有的信息。"
        ),
        FunctionPlugin(
            id: "spec-splitter",
            name: "需求拆解",
            summary: "把模糊需求拆成可验收步骤",
            detail: "输出目标、非目标、依赖、风险、验收标准和最小执行顺序；缺信息时明确列出假设。",
            kind: .skill, author: "DSH Pocket", version: "1.0.0", tags: ["产品", "计划"],
            prompt: "把用户的需求拆成可执行计划：目标、非目标、依赖、风险、验收标准、最小执行顺序。信息不足时列出明确假设，不要假装确定。"
        ),
    ]

    init() {
        installedSkills = Set(defaults.stringArray(forKey: installedKey) ?? [])
        if let data = defaults.data(forKey: mcpKey),
           let servers = try? JSONDecoder().decode([MCPServerConfig].self, from: data) {
            mcpServers = servers
        } else {
            mcpServers = []
        }
    }

    var installedSkillPlugins: [FunctionPlugin] {
        skills.filter { installedSkills.contains($0.id) }
    }

    var skillPrompt: String {
        let parts = installedSkillPlugins.map { "### \($0.name)\n\($0.prompt ?? "")" }
        guard !parts.isEmpty else { return "" }
        return "## Installed skills\n" + parts.joined(separator: "\n\n")
    }

    func isInstalled(_ plugin: FunctionPlugin) -> Bool {
        installedSkills.contains(plugin.id)
    }

    func toggle(_ plugin: FunctionPlugin) {
        if installedSkills.contains(plugin.id) {
            installedSkills.remove(plugin.id)
        } else {
            installedSkills.insert(plugin.id)
        }
        defaults.set(Array(installedSkills).sorted(), forKey: installedKey)
    }

    func addServer(_ server: MCPServerConfig) {
        mcpServers.removeAll { $0.id == server.id }
        mcpServers.append(server)
        persistServers()
        Task { await refresh(server) }
    }

    func removeServer(_ server: MCPServerConfig) {
        mcpServers.removeAll { $0.id == server.id }
        mcpTools[server.id] = nil
        persistServers()
    }

    func refreshAll() async {
        for server in mcpServers where server.enabled {
            await refresh(server)
        }
    }

    func refresh(_ server: MCPServerConfig) async {
        do {
            let client = MCPClient(urlString: server.url, token: server.token)
            let tools = try await client.listTools()
            mcpTools[server.id] = tools
            if let index = mcpServers.firstIndex(where: { $0.id == server.id }) {
                mcpServers[index].toolCount = tools.count
                persistServers()
            }
        } catch {
            mcpTools[server.id] = []
            errorMessage = "MCP「\(server.name)」连接失败：\(error.localizedDescription)"
        }
    }

    /// 供 Agent 使用的动态 MCP 工具。
    func tools() async -> [Tool] {
        var output: [Tool] = []
        for server in mcpServers where server.enabled {
            let client = MCPClient(urlString: server.url, token: server.token)
            guard let tools = try? await client.listTools() else { continue }
            for info in tools {
                output.append(Tool(
                    name: info.name,
                    description: info.description,
                    parameters: info.inputSchema,
                    isDangerous: true,
                    isReadOnly: false,
                    execute: { _, args in
                        let text = try await client.callTool(name: info.name, arguments: args)
                        return ToolResult.text(text)
                    }
                ))
            }
        }
        return output
    }

    private func persistServers() {
        if let data = try? JSONEncoder().encode(mcpServers) {
            defaults.set(data, forKey: mcpKey)
        }
    }
}

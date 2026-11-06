import SwiftUI
import DSHKit

struct PluginCenterView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var plugins: PluginManager
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var tab = 0
    @State private var query = ""
    @State private var showAddServer = false

    private var filteredSkills: [FunctionPlugin] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return plugins.skills }
        return plugins.skills.filter {
            $0.name.localizedCaseInsensitiveContains(value) ||
            $0.summary.localizedCaseInsensitiveContains(value) ||
            $0.tags.contains { $0.localizedCaseInsensitiveContains(value) }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("分类", selection: $tab) {
                    Text("技能").tag(0)
                    Text("MCP").tag(1)
                    Text("工具").tag(2)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)

                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        switch tab {
                        case 0: skillsSection
                        case 1: mcpSection
                        default: toolsSection
                        }
                    }
                    .padding(16)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("功能插件")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                if tab == 1 {
                    ToolbarItem(placement: .confirmationAction) {
                        Button { showAddServer = true } label: {
                            Image(systemName: "plus")
                        }
                    }
                }
            }
            .sheet(isPresented: $showAddServer) {
                AddMCPServerView { server in
                    plugins.addServer(server)
                }
                .environmentObject(plugins)
                .environmentObject(model)
            }
            .preferredColorScheme(.dark)
        }
    }

    private var skillsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            searchField
            HStack {
                Text("可选技能")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Text("已装 \(plugins.installedSkills.count) / \(plugins.skills.count)")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
            }
            ForEach(filteredSkills) { plugin in
                skillRow(plugin)
            }
            Text("技能会追加到 system prompt，新会话或重新打开会话后生效。")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
                .padding(.top, 2)
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
            TextField("搜索技能 / 标签", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.stroke, lineWidth: 1))
    }

    private func skillRow(_ plugin: FunctionPlugin) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "sparkles")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(plugin.tags.contains("交易") ? theme.warning : theme.accent)
                    .frame(width: 28, height: 28)
                    .background(theme.surfaceHover, in: RoundedRectangle(cornerRadius: 7))
                VStack(alignment: .leading, spacing: 2) {
                    Text(plugin.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(plugin.summary)
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button {
                    Haptics.tap()
                    plugins.toggle(plugin)
                } label: {
                    Text(plugins.isInstalled(plugin) ? "卸载" : "安装")
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(plugins.isInstalled(plugin) ? theme.textSecondary : theme.onAccent)
                        .padding(.horizontal, 11)
                        .frame(height: 26)
                        .background(plugins.isInstalled(plugin) ? theme.surfaceHover : theme.accent, in: RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }
            HStack(spacing: 6) {
                ForEach(plugin.tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 8.5, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(theme.surface, in: Capsule())
                }
                Spacer()
                Text("v\(plugin.version)")
                    .font(.system(size: 8.5, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
            }
        }
        .padding(10)
        .background(theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(
            plugins.isInstalled(plugin) ? theme.accent.opacity(0.35) : theme.stroke, lineWidth: 1
        ))
    }

    private var mcpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("MCP 服务器")
                    .font(.system(size: 10.5, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Button {
                    Task { await plugins.refreshAll() }
                } label: {
                    Label("刷新工具", systemImage: "arrow.clockwise")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }

            if plugins.mcpServers.isEmpty {
                Text("还没有 MCP 服务器。右上角 + 添加一个 Streamable HTTP MCP 地址，安装后它的工具会进入 agent 工具表。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
            } else {
                ForEach(plugins.mcpServers) { server in
                    serverRow(server)
                }
            }

            if let error = plugins.errorMessage {
                Text(error)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.danger)
            }
            Text("支持 Streamable HTTP（JSON/SSE）；stdio 与 OAuth 浏览器流程在 iOS 上不可用。工具调用按危险操作走审批。")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
    }

    private func serverRow(_ server: MCPServerConfig) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(server.name)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text(server.url)
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: Binding(
                    get: { server.enabled },
                    set: { value in
                        var updated = server
                        updated.enabled = value
                        plugins.addServer(updated)
                    }
                ))
                .labelsHidden()
                .tint(theme.accent)
            }
            HStack(spacing: 8) {
                Text("\(plugins.mcpTools[server.id]?.count ?? server.toolCount) 个工具")
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                if let tools = plugins.mcpTools[server.id], !tools.isEmpty {
                    Text(tools.prefix(4).map(\.name).joined(separator: " · "))
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                Spacer()
                Button(role: .destructive) {
                    plugins.removeServer(server)
                } label: {
                    Text("删除")
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.danger)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .background(theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(theme.stroke, lineWidth: 1))
    }

    private var toolsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("内置工具")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.textTertiary)

            Toggle(isOn: $model.config.enableWeb) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("联网抓取")
                        .font(.system(size: 13, weight: .medium))
                    Text("web_fetch：抓取用户明确给出的 URL")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .tint(theme.accent)

            ForEach([
                ("read_file / write_file / edit_file", "工作区文件读写"),
                ("glob / grep", "工作区搜索"),
                ("todo_write", "计划与进度"),
                ("update_goal / get_goal", "持久目标"),
            ], id: \.0) { name, desc in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .font(.system(size: 11.5, design: .monospaced))
                        Text(desc)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.textTertiary)
                    }
                    Spacer()
                    Text("内置")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.textTertiary)
                }
                .padding(.vertical, 3)
            }

            Text("MCP 工具：\(plugins.mcpTools.values.reduce(0) { $0 + $1.count }) 个。新增工具会在下次创建会话时装入 agent。")
                .font(.system(size: 10))
                .foregroundStyle(theme.textTertiary)
        }
    }
}

private struct AddMCPServerView: View {
    @EnvironmentObject private var plugins: PluginManager
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var url = ""
    @State private var token = ""

    let onAdd: (MCPServerConfig) -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("服务器") {
                    TextField("名称，例如 DeepWiki", text: $name)
                    TextField("https://example.com/mcp", text: $url)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    SecureField("Bearer Token（可选）", text: $token)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                Section {
                    Text("只支持 Streamable HTTP MCP；Token 仅保存在本机。")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("添加 MCP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("添加") {
                        let server = MCPServerConfig(
                            id: UUID().uuidString,
                            name: name.isEmpty ? "MCP Server" : name,
                            url: url,
                            token: token,
                            enabled: true,
                            toolCount: 0
                        )
                        onAdd(server)
                        dismiss()
                    }
                    .disabled(url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

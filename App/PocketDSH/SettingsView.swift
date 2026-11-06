import SwiftUI
import DSHKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var skins: SkinManager
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    @State private var draft = DSHConfig.default
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var showSkinCenter = false

    private let presets: [(String, String)] = [
        ("safe", "只读 · 危险操作逐次确认"),
        ("review", "审阅 · 改文件前确认"),
        ("default", "工作区 · 默认审批"),
        ("danger", "完全权限 · 不再询问"),
    ]

    var body: some View {
        NavigationStack {
            List {
                Section {
                    header
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets(top: 8, leading: 0, bottom: 12, trailing: 0))
                }

                Section("外观") {
                    Button {
                        showSkinCenter = true
                    } label: {
                        HStack(spacing: 10) {
                            SkinSwatch(theme: skins.theme)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("皮肤中心")
                                    .font(.system(size: 13, weight: .medium))
                                Text(skins.theme.id == "dsh-default" ? "DSH 默认" : skins.theme.name)
                                    .font(.system(size: 11))
                                    .foregroundStyle(theme.textTertiary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                        }
                    }
                    .buttonStyle(.plain)
                }

                Section("DeepSeek") {
                    labelled("API Key") {
                        HStack(spacing: 8) {
                        Group {
                            if showKey {
                                TextField("sk-…", text: $apiKey)
                            } else {
                                SecureField("sk-…", text: $apiKey)
                            }
                        }
                        .font(.system(size: 12, design: .monospaced))
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()

                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .buttonStyle(.plain)
                        }
                    }

                    HStack {
                        Circle()
                            .fill(model.hasAPIKey ? theme.success : theme.warning)
                            .frame(width: 6, height: 6)
                        Text(model.hasAPIKey ? "Key 已存入 Keychain" : "未保存 Key")
                            .font(.system(size: 11))
                            .foregroundStyle(theme.textTertiary)
                        Spacer()
                        if model.hasAPIKey {
                            Button("清除") {
                                apiKey = ""
                                Task { await model.saveAPIKey("") }
                            }
                            .font(.system(size: 11))
                            .foregroundStyle(theme.danger)
                        }
                    }

                    Link(destination: URL(string: "https://platform.deepseek.com/api_keys")!) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up.right.square")
                            Text("获取 API Key")
                        }
                        .font(.system(size: 11))
                        .foregroundStyle(theme.accent)
                    }

                    labelled("模型") {
                        TextField("deepseek-chat", text: $draft.model)
                            .font(.system(size: 12, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                    labelled("Base URL") {
                        TextField("https://api.deepseek.com", text: $draft.baseURL)
                            .font(.system(size: 12, design: .monospaced))
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                    }
                }

                Section("权限") {
                    Picker("预设", selection: $draft.permissionPreset) {
                        ForEach(presets, id: \.0) { preset in
                            Text(presetName(preset.0)).tag(preset.0)
                        }
                    }
                    Text(presets.first { $0.0 == draft.permissionPreset }?.1 ?? "")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                    #if os(iOS)
                    Text("iOS 不允许子进程，所以没有 shell 工具；文件与联网工具都被限制在工作区内。")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.textTertiary)
                    #endif
                }

                Section("工具") {
                    Toggle("联网抓取", isOn: $draft.enableWeb)
                    #if os(macOS)
                    Toggle("Shell（zsh）", isOn: $draft.enableShell)
                    #endif
                }

                Section("上下文") {
                    Stepper("上下文窗口：\(draft.contextWindow / 1000)k", value: $draft.contextWindow, in: 16_000...256_000, step: 16_000)
                    Stepper("每轮最多 \(draft.maxSteps) 步", value: $draft.maxSteps, in: 4...64)
                    TextField("自定义指令", text: $draft.customInstructions, axis: .vertical)
                        .lineLimit(2...5)
                        .font(.system(size: 12))
                }

                Section {
                    Button {
                        save()
                    } label: {
                        Text("保存").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                } footer: {
                    Text("工作区：\(model.workspace.path)")
                        .font(.system(size: 9.5, design: .monospaced))
                }
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("设置")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .fontWeight(.semibold)
                }
            }
            .onAppear {
                draft = model.config
                Task { apiKey = await model.loadAPIKey() }
            }
            .sheet(isPresented: $showSkinCenter) {
                SkinCenterView()
                    .environmentObject(skins)
            }
            .preferredColorScheme(.dark)
        }
    }

    private func save() {
        Task {
            if apiKey != "" || !model.hasAPIKey {
                await model.saveAPIKey(apiKey)
            }
            model.config = draft
            dismiss()
        }
    }

    private func labelled<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(theme.textTertiary)
            content()
        }
        .padding(.vertical, 2)
    }

    private func presetName(_ value: String) -> String {
        switch value {
        case "safe": return "只读"
        case "review": return "改前确认"
        case "danger": return "完全允许"
        default: return "工作区写入"
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            DSHMark(size: 42)
            VStack(alignment: .leading, spacing: 2) {
                Text("DSH Pocket")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text("DeepSeek Harness · iOS 原生内核")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            Spacer()
            Text("1.0.0")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
        }
    }
}

struct SkinSwatch: View {
    @Environment(\.appTheme) private var theme
    let themeValue: AppTheme

    init(theme: AppTheme) {
        self.themeValue = theme
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [themeValue.background, themeValue.accent.opacity(0.85)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 30, height: 30)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.white.opacity(0.15), lineWidth: 1)
            )
    }
}

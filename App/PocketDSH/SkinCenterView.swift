import SwiftUI
import Foundation

/// 皮肤中心：已安装皮肤 + 从 Git 仓库同步 + 一键安装/应用。
struct SkinCenterView: View {
    @EnvironmentObject private var skins: SkinManager
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var source = SkinManager.defaultRepository
    @State private var showToken = false
    @State private var didAutoSync = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    gitSection
                    installedSection
                    remoteSection
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("皮肤中心")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await skins.sync() }
                    } label: {
                        if skins.isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .disabled(skins.isSyncing)
                }
            }
            .onAppear {
                source = skins.repositoryURL
                Task {
                    await skins.reload()
                    guard !didAutoSync, skins.remote.isEmpty else { return }
                    didAutoSync = true
                    await skins.sync()
                }
            }
            .alert("皮肤中心", isPresented: Binding(
                get: { skins.errorMessage != nil },
                set: { if !$0 { skins.errorMessage = nil } }
            )) {
                Button("好", role: .cancel) { skins.errorMessage = nil }
            } message: {
                Text(skins.errorMessage ?? "")
            }
            .preferredColorScheme(.dark)
        }
    }

    // MARK: - Git source

    private var gitSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("GIT 皮肤源", subtitle: "同步 skins/<id>/skin.json 结构")
            HStack(spacing: 8) {
                TextField("https://github.com/owner/repo", text: $source)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 11.5, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(height: 34)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.stroke, lineWidth: 1))

                Button {
                    skins.repositoryURL = source
                    Task { await skins.sync() }
                } label: {
                    Text(skins.isSyncing ? "同步中" : "同步")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(theme.onAccent)
                        .padding(.horizontal, 13)
                        .frame(height: 34)
                        .background(theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(skins.isSyncing)
            }

            HStack(spacing: 6) {
                Button {
                    showToken.toggle()
                } label: {
                    Label(showToken ? "收起 Token" : "GitHub Token（可选）", systemImage: "key")
                        .font(.system(size: 10.5))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
                Spacer()
                if let status = skins.statusMessage {
                    Text(status)
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            if showToken {
                SecureField("ghp_…（提高 API 限额）", text: $skins.githubToken)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.system(size: 11, design: .monospaced))
                    .padding(.horizontal, 9)
                    .frame(height: 32)
                    .background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.stroke, lineWidth: 1))
            }
        }
    }

    // MARK: - Installed

    private var installedSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("已安装", subtitle: "\(skins.installed.count + 1) 款")
            LazyVGrid(columns: columns, spacing: 10) {
                defaultCard
                ForEach(skins.installed) { skin in
                    installedCard(skin)
                }
            }
        }
    }

    private var defaultCard: some View {
        Button {
            Haptics.tap()
            skins.applyDefault()
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    LinearGradient(
                        colors: [Color(red: 0.08, green: 0.09, blue: 0.11), Color(red: 0.16, green: 0.20, blue: 0.28)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                    Text("DSH")
                        .font(.system(size: 18, weight: .heavy, design: .rounded))
                        .foregroundStyle(Color(red: 0.30, green: 0.58, blue: 0.97))
                }
                .frame(height: 74)
                .overlay(alignment: .topTrailing) {
                    if skins.activeID == "dsh-default" { activeBadge }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text("DSH 默认")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("官方暗色 · 玻璃面板")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                .padding(9)
            }
            .background(theme.surface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(skins.activeID == "dsh-default" ? theme.accent.opacity(0.6) : theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func installedCard(_ skin: InstalledSkin) -> some View {
        Button {
            Haptics.tap()
            skins.apply(skin)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    theme.surfaceHover
                    if let url = skins.previewURL(for: skin) {
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Color.clear
                            }
                        }
                    } else {
                        Text(skin.manifest.name)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .foregroundStyle(theme.textSecondary)
                    }
                }
                .frame(height: 74)
                .clipped()
                .overlay(alignment: .topTrailing) {
                    if skins.activeID == skin.id { activeBadge }
                }

                VStack(alignment: .leading, spacing: 2) {
                    Text(skin.manifest.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .lineLimit(1)
                    Text("\(skin.manifest.author) · v\(skin.manifest.version)")
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textTertiary)
                        .lineLimit(1)
                }
                .padding(9)
            }
            .background(theme.surface.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(skins.activeID == skin.id ? theme.accent.opacity(0.6) : theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("删除", role: .destructive) { skins.remove(skin) }
        }
    }

    private var activeBadge: some View {
        Text("使用中")
            .font(.system(size: 8.5, weight: .semibold))
            .foregroundStyle(theme.onAccent)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(theme.accent, in: Capsule())
            .padding(6)
    }

    // MARK: - Remote

    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("仓库里的皮肤", subtitle: skins.remote.isEmpty ? "点右上角刷新" : "\(skins.remote.count) 款")
            if skins.remote.isEmpty {
                Text(skins.isSyncing ? "正在拉取仓库目录…" : "还没有同步。填入皮肤仓库地址后点「同步」。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(theme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
            } else {
                LazyVStack(spacing: 8) {
                    ForEach(skins.remote) { skin in
                        remoteRow(skin)
                    }
                }
            }
        }
    }

    private func remoteRow(_ skin: RemoteSkin) -> some View {
        HStack(spacing: 10) {
            ZStack {
                theme.surfaceHover
                if let url = skins.previewURL(for: skin) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFill()
                        } else {
                            Color.clear
                        }
                    }
                }
            }
            .frame(width: 84, height: 50)
            .clipped()
            .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 2) {
                Text(skin.manifest.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                Text(skin.manifest.tagline ?? skin.manifest.description ?? "")
                    .font(.system(size: 10))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
                Text("\(skin.manifest.author) · \(String(format: "%.1f", Double(skin.files.reduce(0) { $0 + $1.size }) / 1_048_576)) MB")
                    .font(.system(size: 9))
                    .foregroundStyle(theme.textTertiary.opacity(0.8))
            }

            Spacer()

            if skins.installed.contains(where: { $0.id == skin.id }) {
                Text("已安装")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(theme.success)
            } else {
                Button {
                    Haptics.tap()
                    Task { await skins.install(skin) }
                } label: {
                    if skins.installingID == skin.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("安装")
                            .font(.system(size: 10.5, weight: .semibold))
                            .foregroundStyle(theme.onAccent)
                            .padding(.horizontal, 11)
                            .frame(height: 26)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 6))
                    }
                }
                .buttonStyle(.plain)
                .disabled(skins.installingID != nil)
            }
        }
        .padding(8)
        .background(theme.surface.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.stroke, lineWidth: 1))
    }

    private func sectionTitle(_ title: String, subtitle: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 10.5, weight: .semibold))
                .tracking(0.4)
                .foregroundStyle(theme.textTertiary)
            Spacer()
            Text(subtitle)
                .font(.system(size: 9.5))
                .foregroundStyle(theme.textTertiary.opacity(0.75))
        }
    }
}

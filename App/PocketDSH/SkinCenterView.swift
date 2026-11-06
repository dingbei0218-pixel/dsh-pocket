import SwiftUI
import Foundation
import UniformTypeIdentifiers

/// 皮肤中心：已安装皮肤 + 从 Git 仓库同步 + 一键安装/应用。
struct SkinCenterView: View {
    @EnvironmentObject private var skins: SkinManager
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var source = SkinManager.defaultRepository
    @State private var showToken = false
    @State private var didAutoSync = false
    @State private var query = ""
    @State private var selectedTag = ""
    @State private var selection: SkinSelection?
    @State private var showImporter = false

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    gitSection
                    searchField
                    tagFilter
                    installedSection
                    remoteSection
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle("插件库")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Menu {
                        Button {
                            Task { await skins.sync() }
                        } label: {
                            Label("同步仓库", systemImage: "arrow.clockwise")
                        }
                        .disabled(skins.isSyncing)
                        Button {
                            showImporter = true
                        } label: {
                            Label("从文件导入皮肤", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        if skins.isSyncing {
                            ProgressView().controlSize(.small)
                        } else {
                            Image(systemName: "ellipsis.circle")
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
            .sheet(item: $selection) { value in
                SkinDetailView(selection: value)
                    .environmentObject(skins)
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: [.folder], allowsMultipleSelection: false) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first {
                        Task { await skins.importFolder(url) }
                    }
                case .failure(let error):
                    skins.errorMessage = error.localizedDescription
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
            sectionTitle("已安装插件", subtitle: "\(skins.installed.count + 1) 款")
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
            selection = .installed(skin)
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                ZStack {
                    theme.surfaceHover
                    if let url = skins.previewURL(for: skin) {
                        SkinPreviewImage(url: url)
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

    private var filteredRemote: [RemoteSkin] {
        let value = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return skins.remote.filter { skin in
            let matchesText = value.isEmpty ||
                skin.manifest.name.localizedCaseInsensitiveContains(value) ||
                skin.manifest.nameEn.localizedCaseInsensitiveContains(value) ||
                (skin.manifest.tagline ?? "").localizedCaseInsensitiveContains(value) ||
                skin.manifest.author.localizedCaseInsensitiveContains(value) ||
                (skin.manifest.tags ?? []).contains { $0.localizedCaseInsensitiveContains(value) }
            let matchesTag = selectedTag.isEmpty || (skin.manifest.tags ?? []).contains(selectedTag)
            return matchesText && matchesTag
        }
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
            TextField("搜索插件 / 作者 / 标签", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 34)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.stroke, lineWidth: 1))
    }

    private var availableTags: [String] {
        var counts: [String: Int] = [:]
        for skin in skins.remote {
            for tag in skin.manifest.tags ?? [] { counts[tag, default: 0] += 1 }
        }
        return counts.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .prefix(10)
            .map(\.key)
    }

    private var tagFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                tagChip("全部", value: "")
                ForEach(availableTags, id: \.self) { tag in
                    tagChip(tag, value: tag)
                }
            }
        }
    }

    private func tagChip(_ label: String, value: String) -> some View {
        Button {
            selectedTag = value
            Haptics.tap()
        } label: {
            Text(label)
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(selectedTag == value ? theme.onAccent : theme.textSecondary)
                .padding(.horizontal, 9)
                .frame(height: 25)
                .background(selectedTag == value ? theme.accent : theme.surface, in: Capsule())
                .overlay(Capsule().strokeBorder(selectedTag == value ? .clear : theme.stroke, lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var remoteSection: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionTitle("可安装插件", subtitle: skins.remote.isEmpty ? "点右上角刷新" : (query.isEmpty ? "\(skins.remote.count) 款" : "\(filteredRemote.count) / \(skins.remote.count) 款"))
            if skins.remote.isEmpty {
                Text(skins.isSyncing ? "正在拉取仓库目录…" : "还没有同步。填入皮肤仓库地址后点「同步」。")
                    .font(.system(size: 11.5))
                    .foregroundStyle(theme.textTertiary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(12)
                    .background(theme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
            } else {
                if filteredRemote.isEmpty {
                    Text("没有匹配「\(query)」的插件")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                        .background(theme.surface.opacity(0.45), in: RoundedRectangle(cornerRadius: 9))
                } else {
                    LazyVStack(spacing: 8) {
                        ForEach(filteredRemote) { skin in
                            remoteRow(skin)
                        }
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
                    SkinPreviewImage(url: url)
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
        .contentShape(Rectangle())
        .onTapGesture { selection = .remote(skin) }
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


private struct SkinPreviewImage: View {
    @Environment(\.appTheme) private var theme
    let url: URL?

    var body: some View {
        AsyncImage(url: url) { phase in
            switch phase {
            case .success(let image):
                image.resizable().scaledToFill()
            case .failure:
                placeholder
            default:
                placeholder
                    .overlay(ProgressView().controlSize(.mini))
            }
        }
    }

    private var placeholder: some View {
        ZStack {
            LinearGradient(
                colors: [theme.surfaceHover, theme.accent.opacity(0.12)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Image(systemName: "paintpalette")
                .font(.system(size: 15, weight: .light))
                .foregroundStyle(theme.textTertiary)
        }
    }
}


enum SkinSelection: Identifiable {
    case remote(RemoteSkin)
    case installed(InstalledSkin)

    var id: String {
        switch self {
        case .remote(let skin): return "remote-\(skin.id)"
        case .installed(let skin): return "installed-\(skin.id)"
        }
    }
}

struct SkinDetailView: View {
    @EnvironmentObject private var skins: SkinManager
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    let selection: SkinSelection
    @State private var working = false

    private var remote: RemoteSkin? {
        if case .remote(let skin) = selection { return skin }
        return nil
    }

    private var installed: InstalledSkin? {
        switch selection {
        case .installed(let skin): return skin
        case .remote(let skin): return skins.installed.first { $0.id == skin.id }
        }
    }

    private var manifest: SkinManifest {
        if let installed { return installed.manifest }
        return remote!.manifest
    }

    private var previewURL: URL? {
        if let installed { return skins.previewURL(for: installed) }
        if let remote { return skins.previewURL(for: remote) }
        return nil
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    preview
                    header
                    if let description = manifest.description, !description.isEmpty {
                        Text(description)
                            .font(.system(size: 12))
                            .foregroundStyle(theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    if let tags = manifest.tags, !tags.isEmpty {
                        tagsView(tags)
                    }
                    paletteView
                    detectionView
                    actions
                }
                .padding(16)
            }
            .scrollContentBackground(.hidden)
            .background(theme.background)
            .navigationTitle(manifest.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
            .preferredColorScheme(.dark)
        }
    }

    private var preview: some View {
        ZStack {
            theme.surfaceHover
            if let previewURL {
                AsyncImage(url: previewURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
            }
        }
        .frame(height: 210)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.stroke, lineWidth: 1))
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(manifest.name)
                    .font(.system(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Spacer()
                Text("v\(manifest.version)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
            }
            Text("\(manifest.author) · \(manifest.nameEn)")
                .font(.system(size: 11))
                .foregroundStyle(theme.textTertiary)
            if let tagline = manifest.tagline, !tagline.isEmpty {
                Text(tagline)
                    .font(.system(size: 12.5))
                    .foregroundStyle(theme.textSecondary)
            }
        }
    }

    private func tagsView(_ tags: [String]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(theme.surface, in: Capsule())
                }
            }
        }
    }

    private var paletteView: some View {
        let colors = palette
        return VStack(alignment: .leading, spacing: 7) {
            Text("色板")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            if colors.isEmpty {
                Text("安装后可读取 skin.css 的 token 色板")
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textTertiary)
            } else {
                HStack(spacing: 7) {
                    ForEach(colors, id: \.0) { name, color in
                        RoundedRectangle(cornerRadius: 5)
                            .fill(color.color)
                            .frame(height: 28)
                            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(theme.stroke, lineWidth: 1))
                            .help(name)
                    }
                }
            }
        }
    }

    private var palette: [(String, CSSColor)] {
        guard let installed,
              let css = try? String(contentsOf: installed.cssURL, encoding: .utf8) else { return [] }
        let tokens = SkinCSS.tokens(from: css)
        let keys = [
            "--dsw-alias-brand-primary", "--dsw-alias-accent", "--dsw-alias-bg-base",
            "--dsw-alias-bg-layer-1", "--dsw-alias-bg-layer-2", "--dsw-alias-label-primary",
            "--dsw-alias-label-secondary", "--dsw-alias-border-l3",
        ]
        var seen = Set<String>()
        return keys.compactMap { key in
            guard let raw = tokens[key], let color = CSSColor(css: raw), seen.insert(raw).inserted else { return nil }
            return (key, color)
        }
    }

    private var detectionView: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("原生渲染")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(theme.textTertiary)
            if let installed {
                if SkinArtwork.find(in: installed.directory) != nil {
                    Label("已识别皮肤自带的线稿 / 插画", systemImage: "photo")
                } else if SkinPattern.parse(patches: installed.patchesURL) != nil {
                    Label("已从 patches.css 识别网格纹理", systemImage: "grid")
                } else if installed.manifest.darkBackground != nil {
                    Label("使用 backgroundMedia 背景", systemImage: "rectangle.on.rectangle")
                } else {
                    Label("仅应用颜色 token", systemImage: "paintpalette")
                }
            } else {
                Label("安装后自动检测插画 / 网格 / backgroundMedia", systemImage: "wand.and.stars")
            }
        }
        .font(.system(size: 10.5))
        .foregroundStyle(theme.textSecondary)
    }

    private var actions: some View {
        VStack(spacing: 10) {
            if let installed {
                if skins.activeID == installed.id {
                    Label("当前正在使用", systemImage: "checkmark.circle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.success)
                        .frame(maxWidth: .infinity)
                        .frame(height: 42)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 10))
                } else {
                    Button {
                        Haptics.tap()
                        skins.apply(installed)
                        dismiss()
                    } label: {
                        Text("应用这款皮肤")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(theme.onAccent)
                            .frame(maxWidth: .infinity)
                            .frame(height: 42)
                            .background(theme.accent, in: RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                }
                Button(role: .destructive) {
                    skins.remove(installed)
                    dismiss()
                } label: {
                    Text("删除皮肤")
                        .font(.system(size: 11.5))
                        .foregroundStyle(theme.danger)
                }
            } else if let remote {
                Button {
                    working = true
                    Task {
                        await skins.install(remote)
                        working = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if working { ProgressView().controlSize(.small) }
                        Text(working ? "安装中…" : "安装并应用")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 42)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(working || skins.installingID != nil)
            }
        }
    }
}

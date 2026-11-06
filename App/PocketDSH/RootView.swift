import SwiftUI
import DSHKit
#if os(iOS)
import UIKit
#endif

enum Haptics {
    static func tap() {
        #if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        #endif
    }

    static func success() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        #endif
    }

    static func warning() {
        #if os(iOS)
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        #endif
    }
}

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var skins: SkinManager
    @Environment(\.appTheme) private var theme
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var showSidebar = true

    var body: some View {
        ZStack {
            AppBackground()

            #if os(iOS)
            if horizontalSizeClass == .compact {
                if showSidebar || model.currentID == nil {
                    SidebarView(columnVisibility: $columnVisibility, onOpen: { showSidebar = false })
                        .transition(.move(edge: .leading).combined(with: .opacity))
                } else {
                    ChatScreen(onBack: { showSidebar = true })
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            } else {
                splitView
            }
            #else
            splitView
            #endif
        }
        .preferredColorScheme(.dark)
        .onChange(of: model.startInDetail) { _, value in
            if value { showSidebar = false }
        }
        .task {
            if model.startInDetail { showSidebar = false }
        }
        .overlay(alignment: .bottom) {
            ApprovalOverlay(broker: model.approvals)
                .padding(.bottom, 10)
        }
        .sheet(isPresented: $model.showSkinCenter) {
            SkinCenterView()
                .environmentObject(skins)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
                .environmentObject(model)
                .environmentObject(skins)
        }
        .sheet(isPresented: $model.showTodos) {
            TodoSheet(items: model.projection?.todos ?? [])
                .environmentObject(skins)
                #if os(iOS)
                .presentationDetents([.medium, .large])
                #endif
        }
        .sheet(isPresented: $model.showGoal) {
            GoalSheet()
                .environmentObject(model)
                .environmentObject(skins)
        }
        .alert("出错了", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("知道了", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var splitView: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView(columnVisibility: $columnVisibility, onOpen: {})
                .navigationSplitViewColumnWidth(min: 252, ideal: 272, max: 300)
        } detail: {
            ChatScreen()
        }
        .tint(theme.accent)
        .background(Color.clear)
    }
}

/// 可被皮肤替换的背景：纯色 + 皮肤图 + 渐变压暗。
struct AppBackground: View {
    @EnvironmentObject private var skins: SkinManager
    @Environment(\.appTheme) private var theme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                theme.background
                if let pattern = skins.backgroundPattern {
                    SkinGridView(pattern: pattern)
                }
                if let image = skins.backgroundImage {
                    if skins.backgroundIsArtwork {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .center)
                            .opacity(0.38)
                            .overlay(theme.background.opacity(0.18))
                    } else {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFill()
                            .frame(width: proxy.size.width, height: proxy.size.height)
                            .clipped()
                            .blur(radius: skins.backgroundIsPreview ? 10 : 0)
                            .opacity(skins.backgroundIsPreview ? 0.68 : 0.72)
                            .overlay(theme.background.opacity(skins.backgroundIsPreview ? 0.42 : 0.35))
                    }
                }
                RadialGradient(
                    colors: [theme.accent.opacity(0.07), .clear],
                    center: .topLeading,
                    startRadius: 0,
                    endRadius: 520
                )
                LinearGradient(
                    colors: [theme.background.opacity(0.2), theme.background.opacity(0.55), theme.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @Binding var columnVisibility: NavigationSplitViewVisibility
    var onOpen: () -> Void = {}
    @State private var search = ""
    @State private var renameTarget: SessionSummary?
    @State private var renameText = ""

    private var filtered: [SessionSummary] {
        guard !search.trimmingCharacters(in: .whitespaces).isEmpty else { return model.sessions }
        return model.sessions.filter {
            $0.title.localizedCaseInsensitiveContains(search) ||
            $0.preview.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            brandBar
            if !model.hasAPIKey { connectBanner }
            newChatButton
            navRows
            Divider().overlay(theme.stroke)
            sessionHeader
            sessionList
            footer
        }
        .background(theme.sidebar)
    }

    private var brandBar: some View {
        HStack(spacing: 9) {
            DSHMark(size: 26)
            Text("DSH")
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundStyle(theme.textPrimary)
            Text("POCKET")
                .font(.system(size: 8, weight: .heavy, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(theme.textSecondary)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .overlay(
                    RoundedRectangle(cornerRadius: 3)
                        .strokeBorder(theme.strokeStrong, lineWidth: 1)
                )
            Spacer()
            Button {
                model.showSettings = true
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 14)
        .padding(.bottom, 12)
    }

    private var connectBanner: some View {
        Button {
            Haptics.tap()
            model.showSettings = true
        } label: {
            HStack(spacing: 9) {
                Image(systemName: "key.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.accent)
                    .frame(width: 22, height: 22)
                    .background(theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
                VStack(alignment: .leading, spacing: 1) {
                    Text("连接 DeepSeek")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Text("填入 API Key 后开始")
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textTertiary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 10)
            .frame(height: 42)
            .background(theme.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.accent.opacity(0.22), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private var newChatButton: some View {
        Button {
            Haptics.tap()
            onOpen()
            Task { await model.createSession() }
        } label: {
            HStack(spacing: 7) {
                Image(systemName: "plus")
                    .font(.system(size: 12, weight: .bold))
                Text("新会话")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                Text("⌘N")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
            }
            .foregroundStyle(theme.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(theme.surfaceHover, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(theme.stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 12)
        .keyboardShortcut("n", modifiers: .command)
    }

    private var navRows: some View {
        VStack(spacing: 1) {
            navRow(icon: "bubble.left.and.bubble.right", title: "对话", active: true) {}
            navRow(icon: "paintpalette", title: "皮肤中心") { model.showSettings = true }
            navRow(icon: "target", title: "目标") { model.showGoal = true }
            navRow(icon: "checklist", title: "计划") { model.showTodos = true }
        }
        .padding(.horizontal, 8)
        .padding(.top, 12)
    }

    private func navRow(icon: String, title: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .medium))
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13, weight: active ? .semibold : .regular))
                Spacer()
            }
            .foregroundStyle(active ? theme.textPrimary : theme.textSecondary)
            .padding(.horizontal, 9)
            .frame(height: 30)
            .background(active ? theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    private var sessionHeader: some View {
        VStack(spacing: 8) {
            HStack {
                Text("会话")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textTertiary)
            }
            TextField("搜索会话", text: $search)
                .textFieldStyle(.plain)
                .font(.system(size: 12))
                .foregroundStyle(theme.textPrimary)
                .padding(.horizontal, 9)
                .frame(height: 28)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.stroke, lineWidth: 1))
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 8)
    }

    private var sessionList: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if filtered.isEmpty {
                    Text(model.sessions.isEmpty ? "还没有会话" : "没有匹配的会话")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                ForEach(filtered) { session in
                    SessionRow(session: session, selected: session.id == model.currentID, pinned: model.isPinned(session.id))
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Haptics.tap()
                            onOpen()
                            Task { await model.open(session) }
                        }
                        .contextMenu {
                            Button(model.isPinned(session.id) ? "取消置顶" : "置顶") {
                                Task { await model.togglePin(session.id) }
                            }
                            Button("重命名") {
                                renameTarget = session
                                renameText = session.title
                            }
                            Button("删除", role: .destructive) {
                                Task { await model.delete(session) }
                            }
                        }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 12)
        }
        .alert("重命名会话", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("标题", text: $renameText)
            Button("取消", role: .cancel) { renameTarget = nil }
            Button("保存") {
                if let target = renameTarget {
                    Task { await model.rename(session: target, to: renameText) }
                }
                renameTarget = nil
            }
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            Divider().overlay(theme.stroke)
            HStack(spacing: 8) {
                Circle()
                    .fill(model.hasAPIKey ? theme.success : theme.warning)
                    .frame(width: 6, height: 6)
                Text(model.hasAPIKey ? "已连接 DeepSeek" : "未设置 API Key")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.textSecondary)
                Spacer()
                Text(model.modelDisplayName)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(theme.textTertiary)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 10)
        }
        .background(.ultraThinMaterial)
    }
}

private struct SessionRow: View {
    @Environment(\.appTheme) private var theme
    let session: SessionSummary
    let selected: Bool
    let pinned: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Text(session.title)
                    .font(.system(size: 12.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? theme.textPrimary : theme.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: 4)
                if pinned {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 8))
                        .foregroundStyle(theme.accent.opacity(0.8))
                }
                Text(relativeTime(session.updatedAt))
                    .font(.system(size: 9.5))
                    .foregroundStyle(theme.textTertiary)
            }
            if !session.preview.isEmpty {
                Text(session.preview)
                    .font(.system(size: 10.5))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 7)
        .background(selected ? theme.selection : Color.clear, in: RoundedRectangle(cornerRadius: 7))
    }

    private func relativeTime(_ date: Date) -> String {
        if date >= Date().addingTimeInterval(-1) { return "刚刚" }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    var onBack: (() -> Void)? = nil
    @State private var prompt = ""

    private let suggestions = [
        ("理解这个项目", "先读 README 和目录结构，告诉我它是做什么的"),
        ("修一个 bug", "帮我定位并修复当前工作区里的一个失败"),
        ("写测试", "给核心模块补一组边界测试"),
        ("做一个计划", "把这件事拆成可执行的步骤"),
    ]

    var body: some View {
        VStack(spacing: 18) {
            Spacer(minLength: 40)

            DSHMark(size: 54)
                .shadow(color: theme.accent.opacity(0.35), radius: 24)

            if !model.hasAPIKey {
                Button {
                    model.showSettings = true
                } label: {
                    HStack(spacing: 7) {
                        Image(systemName: "key.fill")
                        Text("先连接 DeepSeek")
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                    }
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(theme.accent, in: Capsule())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 6) {
                Text("今天想做点什么？")
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                Text("DSH 在设备本地运行 · \(model.modelDisplayName)")
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textTertiary)
            }

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.0) { item in
                    Button {
                        prompt = item.1
                        Haptics.tap()
                    } label: {
                        HStack(spacing: 10) {
                            Text(item.0)
                                .font(.system(size: 12.5, weight: .medium))
                                .foregroundStyle(theme.textPrimary)
                                .frame(width: 92, alignment: .leading)
                            Text(item.1)
                                .font(.system(size: 12))
                                .foregroundStyle(theme.textTertiary)
                                .lineLimit(1)
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(theme.textTertiary)
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 42)
                        .glassCard(theme, cornerRadius: 11)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 470)

            Spacer(minLength: 20)
            ComposerView(text: $prompt)
                .frame(maxWidth: 760)
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .topLeading) {
            if let onBack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 30, height: 30)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
                .padding(.leading, 16)
            }
        }
    }
}

// MARK: - Brand mark

struct DSHMark: View {
    @Environment(\.appTheme) private var theme
    var size: CGFloat = 26

    var body: some View {
        Image("BrandMark")
            .resizable()
            .interpolation(.none)
            .scaledToFit()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.24, style: .continuous)
                    .strokeBorder(theme.stroke, lineWidth: 0.5)
            )
    }
}


private struct SkinGridView: View {
    let pattern: SkinPattern

    var body: some View {
        Canvas { context, size in
            var path = Path()
            let spacing = max(8, pattern.spacing)
            for x in stride(from: 0, through: size.width, by: spacing) {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 0, through: size.height, by: spacing) {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(path, with: .color(pattern.color.color.opacity(0.55)), lineWidth: 0.5)
            if let major = pattern.majorSpacing, major > spacing * 2 {
                var majorPath = Path()
                for x in stride(from: 0, through: size.width, by: major) {
                    majorPath.move(to: CGPoint(x: x, y: 0))
                    majorPath.addLine(to: CGPoint(x: x, y: size.height))
                }
                for y in stride(from: 0, through: size.height, by: major) {
                    majorPath.move(to: CGPoint(x: 0, y: y))
                    majorPath.addLine(to: CGPoint(x: size.width, y: y))
                }
                context.stroke(majorPath, with: .color(pattern.color.color.opacity(0.8)), lineWidth: 0.7)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

import SwiftUI
import DSHKit
import UniformTypeIdentifiers
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Chat screen

struct ChatScreen: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    var onBack: (() -> Void)? = nil
    @State private var draft = ""

    private var hasConversation: Bool {
        !(model.projection?.items.isEmpty ?? true)
    }

    var body: some View {
        ZStack {
            if hasConversation, let projection = model.projection {
                VStack(spacing: 0) {
                    ChatHeader(projection: projection, onBack: onBack)
                    Divider().overlay(theme.stroke)
                    TranscriptView(items: projection.items, isRunning: model.isRunning)
                    if let goal = projection.goal, goal.phase == .active || goal.phase == .blocked {
                        GoalBar(goal: goal)
                    }
                    ComposerView(text: $draft)
                }
            } else {
                EmptyStateView()
            }
        }
    }
}

private struct ChatHeader: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    let projection: SessionProjection
    var onBack: (() -> Void)? = nil

    private var contextFraction: Double {
        guard model.config.contextWindow > 0 else { return 0 }
        return min(1, Double(projection.usage.lastPromptTokens) / Double(model.config.contextWindow))
    }

    var body: some View {
        HStack(spacing: 12) {
            if let onBack {
                Button {
                    onBack()
                } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                        .frame(width: 28, height: 28)
                        .background(theme.surface, in: RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(projection.displayTitle)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1)
                HStack(spacing: 7) {
                    chip(model.modelDisplayName, icon: "cpu")
                    chip(model.permissionDisplayName, icon: "lock.shield")
                    if projection.todos.isEmpty == false {
                        chip("\(projection.todos.filter { $0.status == .completed }.count)/\(projection.todos.count)", icon: "checklist")
                    }
                }
            }
            Spacer()

            ContextRing(fraction: contextFraction, tokens: projection.usage.lastPromptTokens)
                .frame(width: 26, height: 26)

            Button {
                model.showTodos = true
            } label: {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            Button {
                model.showGoal = true
            } label: {
                Image(systemName: "target")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(projection.goal?.phase == .active ? theme.accent : theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            Menu {
                Button {
                    copyTranscript()
                } label: {
                    Label("复制全文", systemImage: "doc.on.doc")
                }
                ShareLink(item: transcriptText) {
                    Label("导出 Markdown", systemImage: "square.and.arrow.up")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .frame(width: 28, height: 28)
                    .background(theme.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 7))
            }

            if model.isRunning {
                Button {
                    Haptics.warning()
                    Task { await model.stop() }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "stop.fill").font(.system(size: 9, weight: .bold))
                        Text("停止").font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(theme.danger)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(theme.danger.opacity(0.12), in: Capsule())
                    .overlay(Capsule().strokeBorder(theme.danger.opacity(0.25), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.leading, onBack == nil ? 16 : 10)
        .padding(.trailing, 16)
        .frame(height: 54)
        .background(.ultraThinMaterial)
    }

    private var transcriptText: String {
        var lines: [String] = ["# \(projection.displayTitle)", ""]
        for item in projection.items {
            switch item.kind {
            case .user:
                lines.append("**你**\n\n\(item.text)")
            case .assistant:
                if !item.text.isEmpty { lines.append("**DSH**\n\n\(item.text)") }
            case .tool:
                lines.append("`\(item.toolName ?? "tool")` → \(item.toolOutput ?? "(running)")")
            case .error:
                lines.append("> error: \(item.text)")
            }
            lines.append("")
        }
        return lines.joined(separator: "\n")
    }

    private func copyTranscript() {
        #if os(macOS)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcriptText, forType: .string)
        #else
        UIPasteboard.general.string = transcriptText
        #endif
        Haptics.success()
    }

    private func chip(_ text: String, icon: String) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon).font(.system(size: 8.5, weight: .medium))
            Text(text).font(.system(size: 10, weight: .medium, design: .monospaced))
        }
        .foregroundStyle(theme.textTertiary)
        .padding(.horizontal, 5)
        .frame(height: 16)
        .background(theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 4))
    }
}

private struct ContextRing: View {
    @Environment(\.appTheme) private var theme
    let fraction: Double
    let tokens: Int

    var body: some View {
        ZStack {
            Circle().stroke(theme.strokeStrong, lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: max(0.02, fraction))
                .stroke(theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Transcript

private struct TranscriptView: View {
    @Environment(\.appTheme) private var theme
    let items: [ChatItem]
    let isRunning: Bool

    private var scrollToken: String {
        let last = items.last
        return "\(items.count)-\(last?.text.count ?? 0)-\(last?.toolOutput?.count ?? 0)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(items) { item in
                        MessageRow(item: item)
                            .id(item.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 18)
                .padding(.top, 20)
                .padding(.bottom, 14)
                .frame(maxWidth: 820, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: scrollToken) { _, _ in
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo("bottom", anchor: .bottom)
                }
            }
            .onAppear {
                proxy.scrollTo("bottom", anchor: .bottom)
            }
        }
    }
}

private struct MessageRow: View {
    @Environment(\.appTheme) private var theme
    let item: ChatItem

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 48)
                Text(item.text)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .padding(.horizontal, 13)
                    .padding(.vertical, 9)
                    .background(theme.userBubble, in: RoundedRectangle(cornerRadius: 13, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 13, style: .continuous)
                            .strokeBorder(theme.userBubbleStroke, lineWidth: 1)
                    )
                    .textSelection(.enabled)
            }

        case .assistant:
            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 6) {
                    Text("DSH")
                        .font(.system(size: 9.5, weight: .heavy, design: .rounded))
                        .foregroundStyle(theme.accent)
                    Text(timeText)
                        .font(.system(size: 9.5))
                        .foregroundStyle(theme.textTertiary)
                    if item.isStreaming {
                        Circle().fill(theme.accent).frame(width: 4, height: 4)
                            .modifier(Pulse())
                    }
                    Spacer()
                }
                if !item.reasoning.isEmpty {
                    ReasoningView(text: item.reasoning)
                }
                if !item.text.isEmpty {
                    MarkdownText(text: item.text, isStreaming: item.isStreaming)
                        .textSelection(.enabled)
                } else if item.isStreaming {
                    Text("正在思考…")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.textTertiary)
                }
                if !item.text.isEmpty {
                    HStack(spacing: 12) {
                        CopyButton(text: item.text)
                        Text("\(item.text.count) 字")
                            .font(.system(size: 9.5))
                            .foregroundStyle(theme.textTertiary)
                    }
                    .padding(.top, 1)
                }
            }
            .padding(.leading, 2)

        case .tool:
            ToolCardView(item: item)

        case .error:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(theme.danger)
                Text(item.text)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.danger)
                    .textSelection(.enabled)
                Spacer()
            }
            .padding(10)
            .background(theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.danger.opacity(0.18), lineWidth: 1))
        }
    }

    private var timeText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: item.time)
    }
}

private struct Pulse: ViewModifier {
    @State private var on = false

    func body(content: Content) -> some View {
        content
            .opacity(on ? 1 : 0.25)
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: on)
            .onAppear { on = true }
    }
}

private struct CopyButton: View {
    @Environment(\.appTheme) private var theme
    let text: String
    @State private var copied = false

    var body: some View {
        Button {
            #if os(macOS)
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            #else
            UIPasteboard.general.string = text
            #endif
            copied = true
            Haptics.success()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                Text(copied ? "已复制" : "复制")
            }
            .font(.system(size: 9.5))
            .foregroundStyle(theme.textTertiary)
        }
        .buttonStyle(.plain)
    }
}

private struct ReasoningView: View {
    @Environment(\.appTheme) private var theme
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 8, weight: .semibold))
                    Text("思考 · \(text.count) 字")
                        .font(.system(size: 10))
                }
                .foregroundStyle(theme.textTertiary)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(text)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textSecondary)
                    .textSelection(.enabled)
                    .padding(.leading, 9)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(theme.strokeStrong).frame(width: 1)
                    }
            }
        }
    }
}

// MARK: - Markdown

struct MarkdownText: View {
    @Environment(\.appTheme) private var theme
    let text: String
    var isStreaming = false

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(MarkdownSegment.parse(text).enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let value):
                    Text(attributed(value))
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let language, let value):
                    CodeBlockView(language: language, code: value)
                case .table(let headers, let rows):
                    TableBlockView(headers: headers, rows: rows)
                }
            }
            if isStreaming {
                Text("▍")
                    .font(.system(size: 13))
                    .foregroundStyle(theme.accent)
                    .modifier(Pulse())
            }
        }
    }

    private func attributed(_ value: String) -> AttributedString {
        (try? AttributedString(
            markdown: value,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(value)
    }
}

enum MarkdownSegment {
    case text(String)
    case code(String?, String)
    case table([String], [[String]])

    static func parse(_ input: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        var buffer: [String] = []
        var inCode = false
        var language: String?
        var code: [String] = []
        let lines = input.components(separatedBy: "\n")
        var index = 0

        func flushText() {
            let value = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { segments.append(.text(value)) }
            buffer.removeAll()
        }

        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("```") {
                if inCode {
                    segments.append(.code(language, code.joined(separator: "\n")))
                    code.removeAll()
                    inCode = false
                    language = nil
                } else {
                    flushText()
                    inCode = true
                    language = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    if language?.isEmpty == true { language = nil }
                }
                index += 1
                continue
            }
            if inCode {
                code.append(line)
                index += 1
                continue
            }
            if line.contains("|"), index + 1 < lines.count, isTableSeparator(lines[index + 1]) {
                flushText()
                let headers = splitRow(line)
                var rows: [[String]] = []
                index += 2
                while index < lines.count, lines[index].contains("|"), !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
                    rows.append(splitRow(lines[index]))
                    index += 1
                }
                segments.append(.table(headers, rows))
                continue
            }
            buffer.append(line)
            index += 1
        }
        if inCode {
            segments.append(.code(language, code.joined(separator: "\n")))
        } else {
            flushText()
        }
        if segments.isEmpty { segments.append(.text(input)) }
        return segments
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.contains("-"), trimmed.contains("|") else { return false }
        return trimmed.allSatisfy { "|-: ".contains($0) }
    }

    private static func splitRow(_ line: String) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }
        return trimmed.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }
}

private struct TableBlockView: View {
    @Environment(\.appTheme) private var theme
    let headers: [String]
    let rows: [[String]]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 7) {
                GridRow {
                    ForEach(headers.indices, id: \.self) { index in
                        Text(headers[index])
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(theme.textPrimary)
                    }
                }
                ForEach(rows.indices, id: \.self) { rowIndex in
                    GridRow {
                        ForEach(0..<headers.count, id: \.self) { columnIndex in
                            Text(columnIndex < rows[rowIndex].count ? rows[rowIndex][columnIndex] : "")
                                .font(.system(size: 11))
                                .foregroundStyle(theme.textSecondary)
                        }
                    }
                }
            }
            .padding(10)
        }
        .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(theme.stroke, lineWidth: 1))
    }
}

private struct CodeBlockView: View {
    @Environment(\.appTheme) private var theme
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                Spacer()
                Button {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(code, forType: .string)
                    #else
                    UIPasteboard.general.string = code
                    #endif
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                } label: {
                    Image(systemName: copied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 10))
                        .foregroundStyle(theme.textTertiary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 6)
            Divider().overlay(theme.stroke)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(theme.textPrimary)
                    .textSelection(.enabled)
                    .padding(11)
            }
        }
        .background(Color.black.opacity(0.26), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.stroke, lineWidth: 1))
    }
}

// MARK: - Tool card

private struct ToolCardView: View {
    @Environment(\.appTheme) private var theme
    let item: ChatItem
    @State private var expanded = false

    private var status: String {
        if item.isError { return "失败" }
        if item.isStreaming { return "运行中" }
        return "完成"
    }

    private var statusColor: Color {
        item.isError ? theme.danger : (item.isStreaming ? theme.warning : theme.success)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 7) {
                    Image(systemName: iconName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(theme.accent)
                        .frame(width: 20, height: 20)
                        .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 5))
                    Text(item.toolName ?? "tool")
                        .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
                        .foregroundStyle(theme.textSecondary)
                    if let input = item.toolInput, let path = input["path"]?.stringValue ?? input["command"]?.stringValue {
                        Text(path)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(theme.textTertiary)
                            .lineLimit(1)
                    }
                    Spacer()
                    Circle().fill(statusColor).frame(width: 5, height: 5)
                    Text(status).font(.system(size: 9.5)).foregroundStyle(theme.textTertiary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                if let input = item.toolInput, !input.isNull {
                    labelled("输入", text: input.jsonString(pretty: true))
                }
                if let output = item.toolOutput, !output.isEmpty {
                    labelled("输出", text: String(output.prefix(6_000)))
                } else if item.isStreaming {
                    Text("等待结果…").font(.system(size: 10)).foregroundStyle(theme.textTertiary)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(theme.surface.opacity(0.55), in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(theme.stroke, lineWidth: 1))
    }

    private func labelled(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.textTertiary)
            Text(text)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(theme.textSecondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(Color.black.opacity(0.2), in: RoundedRectangle(cornerRadius: 6))
    }

    private var iconName: String {
        switch item.toolName {
        case "read_file": return "doc.text"
        case "write_file", "edit_file": return "square.and.pencil"
        case "list_dir": return "folder"
        case "glob": return "magnifyingglass"
        case "grep": return "text.magnifyingglass"
        case "shell": return "terminal"
        case "web_fetch": return "globe"
        case "todo_write": return "checklist"
        default: return "wrench.and.screwdriver"
        }
    }
}

// MARK: - Composer

struct ComposerView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @Binding var text: String
    @FocusState private var focused: Bool
    @State private var showImporter = false
    @State private var importError: String?
    @StateObject private var speech = SpeechRecognizer()

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 9) {
                Button {
                    showImporter = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(theme.textSecondary)
                        .frame(width: 28, height: 28)
                        .background(theme.surface, in: Circle())
                        .overlay(Circle().strokeBorder(theme.stroke, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(.leading, 5)
                .padding(.bottom, 8)

                TextField("发消息，@ 引用文件", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, design: .rounded))
                    .foregroundStyle(theme.textPrimary)
                    .lineLimit(1...7)
                    .focused($focused)
                    .submitLabel(.send)
                    .onSubmit(submit)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)

                Button {
                    speech.toggle()
                } label: {
                    Image(systemName: speech.isRecording ? "waveform" : "mic")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(speech.isRecording ? theme.danger : theme.textSecondary)
                        .frame(width: 30, height: 30)
                        .background(theme.surface, in: Circle())
                }
                .buttonStyle(.plain)
                .padding(.bottom, 7)

                Button(action: submit) {
                    Image(systemName: model.isRunning ? "stop.fill" : "arrow.up")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(canSend || model.isRunning ? theme.onAccent : theme.textTertiary)
                        .frame(width: 30, height: 30)
                        .background(
                            Circle().fill(model.isRunning ? theme.danger : (canSend ? theme.accent : theme.surfaceHover))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canSend && !model.isRunning)
                .padding(.trailing, 7)
                .padding(.bottom, 7)
            }

            HStack(spacing: 8) {
                Menu {
                    ForEach(["safe", "review", "default", "danger"], id: \.self) { preset in
                        Button {
                            model.config.permissionPreset = preset
                        } label: {
                            if model.config.permissionPreset == preset {
                                Label(label(for: preset), systemImage: "checkmark")
                            } else {
                                Text(label(for: preset))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "lock.shield")
                            .font(.system(size: 8.5))
                        Text(model.permissionDisplayName)
                            .font(.system(size: 10, weight: .medium))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .semibold))
                    }
                    .foregroundStyle(theme.textTertiary)
                    .contentShape(Rectangle())
                }

                Picker("模型", selection: $model.config.model) {
                    Text("Chat · 快速").tag("deepseek-chat")
                    Text("Reasoner · 深度").tag("deepseek-reasoner")
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .font(.system(size: 10, weight: .medium))
                .tint(theme.textTertiary)
                .contentShape(Rectangle())

                Spacer()

                if let projection = model.projection {
                    Text("\(projection.usage.lastPromptTokens) / \(model.config.contextWindow / 1000)k")
                        .font(.system(size: 9.5, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
            }
            .padding(.horizontal, 4)
        }
        .padding(8)
        .background(theme.surfaceHover.opacity(0.92), in: RoundedRectangle(cornerRadius: 15, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 15, style: .continuous)
                .strokeBorder(focused ? theme.accent.opacity(0.35) : theme.stroke, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 18, y: 6)
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 10)
        .onChange(of: speech.transcript) { _, value in
            if speech.isRecording {
                text = value
            }
        }
        .alert("语音输入", isPresented: Binding(
            get: { speech.errorMessage != nil },
            set: { if !$0 { speech.errorMessage = nil } }
        )) {
            Button("好", role: .cancel) { speech.errorMessage = nil }
        } message: {
            Text(speech.errorMessage ?? "")
        }
        .fileImporter(isPresented: $showImporter, allowedContentTypes: [.item], allowsMultipleSelection: false) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first { importFile(url) }
            case .failure(let error):
                importError = error.localizedDescription
            }
        }
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private func importFile(_ url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let fileManager = FileManager.default
            var destination = model.workspace.appendingPathComponent(url.lastPathComponent)
            if fileManager.fileExists(atPath: destination.path) {
                let stem = url.deletingPathExtension().lastPathComponent
                let ext = url.pathExtension
                var index = 2
                repeat {
                    let name = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
                    destination = model.workspace.appendingPathComponent(name)
                    index += 1
                } while fileManager.fileExists(atPath: destination.path)
            }
            try fileManager.copyItem(at: url, to: destination)
            let mention = "@\(destination.lastPathComponent)"
            text += text.isEmpty ? mention : " \(mention)"
            Haptics.success()
        } catch {
            importError = error.localizedDescription
        }
    }

    private var canSend: Bool {
        !model.isRunning && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        if !model.hasAPIKey {
            model.showSettings = true
            return
        }
        if model.isRunning {
            Task { await model.stop() }
            return
        }
        guard canSend else { return }
        let value = text
        text = ""
        Haptics.tap()
        Task { await model.send(value) }
    }

    private func label(for preset: String) -> String {
        switch preset {
        case "safe": return "只读"
        case "review": return "改前确认"
        case "danger": return "完全允许"
        default: return "工作区写入"
        }
    }
}

// MARK: - Goal bar

private struct GoalBar: View {
    @Environment(\.appTheme) private var theme
    let goal: GoalState

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: goal.phase == .blocked ? "exclamationmark.octagon.fill" : "target")
                .font(.system(size: 10))
                .foregroundStyle(goal.phase == .blocked ? theme.danger : theme.accent)
            Text(goal.description.isEmpty ? "进行中的目标" : goal.description)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(theme.textSecondary)
                .lineLimit(1)
            Text("\(goal.rounds)/\(max(goal.maxRounds, 1))")
                .font(.system(size: 9.5, design: .monospaced))
                .foregroundStyle(theme.textTertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 30)
        .background(theme.surface.opacity(0.5))
        .overlay(alignment: .top) { Divider().overlay(theme.stroke) }
    }
}

// MARK: - Approval

struct ApprovalOverlay: View {
    @Environment(\.appTheme) private var theme
    @ObservedObject var broker: ApprovalBroker

    var body: some View {
        if let request = broker.pending {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 7) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(theme.warning)
                    Text("需要授权")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(theme.textPrimary)
                    Spacer()
                    Text(request.tool)
                        .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(theme.textTertiary)
                }
                Text(request.summary)
                    .font(.system(size: 12))
                    .foregroundStyle(theme.textSecondary)
                    .lineLimit(2)
                Text(request.input.jsonString(pretty: true))
                    .font(.system(size: 9.5, design: .monospaced))
                    .foregroundStyle(theme.textTertiary)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.black.opacity(0.18), in: RoundedRectangle(cornerRadius: 7))
                HStack {
                    Spacer()
                    Button("拒绝") {
                        Haptics.warning()
                        broker.resolve(false)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.textSecondary)
                    .padding(.horizontal, 12)
                    .frame(height: 30)
                    .background(theme.surfaceHover, in: RoundedRectangle(cornerRadius: 7))

                    Button("总是允许") {
                        Haptics.success()
                        broker.allowAlways()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(theme.accent)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(theme.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))

                    Button("允许一次") {
                        Haptics.success()
                        broker.resolve(true)
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
                    .background(theme.accent, in: RoundedRectangle(cornerRadius: 7))
                }
            }
            .padding(13)
            .frame(maxWidth: 480)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(theme.strokeStrong, lineWidth: 1))
            .shadow(color: .black.opacity(0.35), radius: 24, y: 8)
            .padding(.horizontal, 16)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

// MARK: - Goal editor

struct GoalSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var maxRounds = 10

    var body: some View {
        NavigationStack {
            Form {
                Section("目标") {
                    TextField("想让 DSH 持续做什么？", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                    Stepper("最多 \(maxRounds) 轮", value: $maxRounds, in: 1...50)
                }
                if let goal = model.projection?.goal {
                    Section("当前") {
                        Text(goal.description.isEmpty ? "（无描述）" : goal.description)
                        Text("\(goal.phase.rawValue) · revision \(goal.revision)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("标记完成", role: .destructive) {
                            Task {
                                await model.clearGoal()
                                dismiss()
                            }
                        }
                    }
                }
                Section {
                    Button {
                        Task {
                            await model.setGoal(description, maxRounds: maxRounds)
                            dismiss()
                        }
                    } label: {
                        Text("保存目标").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(theme.accent)
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("目标")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .onAppear {
                if let goal = model.projection?.goal {
                    description = goal.description
                    maxRounds = max(goal.maxRounds, 1)
                }
            }
            .preferredColorScheme(.dark)
        }
    }
}

// MARK: - Todo

struct TodoSheet: View {
    @Environment(\.appTheme) private var theme
    let items: [TodoItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("还没有计划。让 DSH 拆一个任务试试。")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack(spacing: 9) {
                        Image(systemName: symbol(item.status))
                            .font(.system(size: 12))
                            .foregroundStyle(color(item.status))
                        Text(item.content)
                            .font(.system(size: 13))
                            .strikethrough(item.status == .completed)
                            .foregroundStyle(item.status == .completed ? theme.textTertiary : theme.textPrimary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("计划")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { dismiss() }
                }
            }
        }
    }

    private func symbol(_ status: TodoItem.Status) -> String {
        switch status {
        case .pending: return "circle"
        case .inProgress: return "circle.dotted"
        case .completed: return "checkmark.circle.fill"
        }
    }

    private func color(_ status: TodoItem.Status) -> Color {
        switch status {
        case .pending: return theme.textTertiary
        case .inProgress: return theme.warning
        case .completed: return theme.success
        }
    }
}

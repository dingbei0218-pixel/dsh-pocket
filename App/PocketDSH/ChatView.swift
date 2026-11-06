import SwiftUI
import DSHKit
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Chat screen

struct ChatScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var draft = ""

    private var hasConversation: Bool {
        !(model.projection?.items.isEmpty ?? true)
    }

    var body: some View {
        ZStack {
            Theme.backgroundGradient.ignoresSafeArea()
            if hasConversation, let projection = model.projection {
                VStack(spacing: 0) {
                    ChatHeader(projection: projection)
                    Divider().overlay(Theme.stroke)
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
        .toolbar { toolbarContent }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        ToolbarItem(placement: .automatic) {
            Text(model.projection?.displayTitle ?? "DSH Pocket")
                .font(.headline)
        }
        #endif
    }
}

private struct ChatHeader: View {
    @EnvironmentObject private var model: AppModel
    let projection: SessionProjection

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(projection.displayTitle)
                    .font(.system(.headline, design: .rounded, weight: .semibold))
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(model.config.model)
                    Text("·")
                    Text("\(projection.usage.totalTokens) tokens")
                    if projection.isStreaming {
                        Text("·")
                        Text("streaming")
                            .foregroundStyle(Theme.accent)
                    }
                }
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                model.showGoal = true
            } label: {
                Image(systemName: "target")
                    .font(.caption)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            #if os(macOS)
            .help("Set a goal")
            #endif
            if !projection.todos.isEmpty {
                Button {
                    model.showTodos = true
                } label: {
                    Label("\(projection.todos.filter { $0.status == .completed }.count)/\(projection.todos.count)", systemImage: "checklist")
                        .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            if model.isRunning {
                Button {
                    Task { await model.stop() }
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.danger)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
    }
}

// MARK: - Transcript

private struct TranscriptView: View {
    let items: [ChatItem]
    let isRunning: Bool

    private var scrollToken: String {
        let lastText = items.last?.text.count ?? 0
        let outputs = items.reduce(0) { $0 + ($1.toolOutput?.count ?? 0) }
        return "\(items.count)-\(lastText)-\(outputs)"
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    ForEach(items) { item in
                        MessageRow(item: item)
                            .id(item.id)
                    }
                    Color.clear.frame(height: 1).id("bottom")
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 18)
                .frame(maxWidth: 860, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
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
    let item: ChatItem

    var body: some View {
        switch item.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(item.text)
                    .font(.system(.body, design: .rounded))
                    .textSelection(.enabled)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(Theme.accent.opacity(0.18))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1)
                    )
            }

        case .assistant:
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Theme.accent.opacity(0.2))
                    .frame(width: 26, height: 26)
                    .overlay(Image(systemName: "sparkles").font(.system(size: 12, weight: .bold)).foregroundStyle(Theme.accent))
                VStack(alignment: .leading, spacing: 8) {
                    if !item.reasoning.isEmpty {
                        ReasoningView(text: item.reasoning)
                    }
                    MarkdownText(text: item.text, isStreaming: item.isStreaming)
                        .textSelection(.enabled)
                }
                Spacer(minLength: 0)
            }

        case .tool:
            ToolCardView(item: item)

        case .error:
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.danger)
                Text(item.text)
                    .font(.callout)
                    .foregroundStyle(Theme.danger)
                    .textSelection(.enabled)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.danger.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct ReasoningView: View {
    let text: String
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right")
                    Text("Reasoning")
                }
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            if expanded {
                Text(text)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                    .padding(.leading, 10)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.stroke).frame(width: 1)
                    }
            }
        }
    }
}

// MARK: - Markdown

struct MarkdownText: View {
    let text: String
    var isStreaming = false

    private var segments: [MarkdownSegment] {
        MarkdownSegment.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(segments.indices, id: \.self) { index in
                switch segments[index] {
                case .text(let value):
                    Text(attributed(value))
                        .font(.system(.body, design: .rounded))
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
            if isStreaming {
                Text("▍")
                    .font(.body)
                    .foregroundStyle(Theme.accent)
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

    static func parse(_ input: String) -> [MarkdownSegment] {
        var segments: [MarkdownSegment] = []
        var buffer: [String] = []
        var inCode = false
        var language: String?
        var code: [String] = []

        func flushText() {
            let value = buffer.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            if !value.isEmpty { segments.append(.text(value)) }
            buffer.removeAll()
        }

        for line in input.components(separatedBy: "\n") {
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
            } else if inCode {
                code.append(line)
            } else {
                buffer.append(line)
            }
        }
        if inCode {
            segments.append(.code(language, code.joined(separator: "\n")))
        } else {
            flushText()
        }
        if segments.isEmpty { segments.append(.text(input)) }
        return segments
    }
}

private struct CodeBlockView: View {
    let language: String?
    let code: String
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(language ?? "code")
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
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
                        .font(.caption)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            Divider().overlay(Theme.stroke)
            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .padding(12)
            }
        }
        .background(Color.black.opacity(0.28), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.stroke, lineWidth: 1))
    }
}

// MARK: - Tool card

private struct ToolCardView: View {
    let item: ChatItem
    @State private var expanded = false

    private var status: String {
        if item.isError { return "failed" }
        if item.isStreaming { return "running" }
        return "done"
    }

    private var statusColor: Color {
        item.isError ? Theme.danger : (item.isStreaming ? Theme.warning : Theme.success)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iconName)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 24, height: 24)
                        .background(Theme.accent.opacity(0.14), in: Circle())
                    Text(item.toolName ?? "tool")
                        .font(.system(.caption, design: .monospaced, weight: .semibold))
                    Spacer()
                    Circle().fill(statusColor).frame(width: 6, height: 6)
                    Text(status)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Image(systemName: expanded ? "chevron.up" : "chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)

            if expanded {
                if let input = item.toolInput, !input.isNull {
                    labelled("input", text: input.jsonString(pretty: true))
                }
                if let output = item.toolOutput, !output.isEmpty {
                    labelled("output", text: String(output.prefix(6_000)))
                } else if item.isStreaming {
                    Text("Waiting for result…")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 12)
    }

    private func labelled(_ title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.system(.caption2, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(9)
        .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
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
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 10) {
                TextField("Ask DSH to build, fix, or explain…", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .rounded))
                    .lineLimit(1...6)
                    .focused($focused)
                    .onSubmit(submit)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(focused ? Theme.accent.opacity(0.5) : Theme.stroke, lineWidth: 1)
                    )

                Button(action: submit) {
                    Image(systemName: model.isRunning ? "hourglass" : "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .frame(width: 40, height: 40)
                        .background(
                            Circle().fill(canSend ? Theme.accent : Color.white.opacity(0.08))
                        )
                        .foregroundStyle(canSend ? Color.black : Color.secondary)
                }
                .buttonStyle(.plain)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: [.command])
            }

            HStack(spacing: 6) {
                if !model.hasAPIKey {
                    Button {
                        model.showSettings = true
                    } label: {
                        Label("Add your DeepSeek API key to start", systemImage: "key.fill")
                            .font(.caption2)
                            .foregroundStyle(Theme.warning)
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("⏎ send · ⌘⏎ newline")
                        .font(.caption2)
                        .foregroundStyle(.secondary.opacity(0.7))
                }
                Spacer()
                Text(model.config.permissionPreset)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary.opacity(0.7))
            }
            .padding(.horizontal, 6)
        }
        .padding(.horizontal, 18)
        .padding(.top, 10)
        .padding(.bottom, 14)
        .background(.ultraThinMaterial)
    }

    private var canSend: Bool {
        !model.isRunning && !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() {
        guard canSend else { return }
        let value = text
        text = ""
        Task { await model.send(value) }
    }
}

// MARK: - Goal

private struct GoalBar: View {
    let goal: GoalState

    var body: some View {
        HStack(spacing: 9) {
            Image(systemName: goal.phase == .blocked ? "exclamationmark.octagon.fill" : "target")
                .foregroundStyle(goal.phase == .blocked ? Theme.danger : Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(goal.description.isEmpty ? "Active goal" : goal.description)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                Text("round \(goal.rounds)/\(max(goal.maxRounds, 1)) · \(goal.phase.rawValue)")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 8)
        .background(Theme.accent.opacity(0.08))
        .overlay(alignment: .top) { Divider().overlay(Theme.stroke) }
    }
}

// MARK: - Approval

struct ApprovalOverlay: View {
    @ObservedObject var broker: ApprovalBroker

    var body: some View {
        if let request = broker.pending {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "lock.shield.fill").foregroundStyle(Theme.warning)
                    Text("Approval required")
                        .font(.system(.headline, design: .rounded))
                    Spacer()
                }
                Text(request.summary)
                    .font(.callout)
                Text(request.input.jsonString(pretty: true))
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(9)
                    .background(Color.black.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
                HStack {
                    Spacer()
                    Button("Deny", role: .destructive) { broker.resolve(false) }
                        .buttonStyle(.bordered)
                    Button("Allow") { broker.resolve(true) }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.accent)
                }
            }
            .padding(16)
            .frame(maxWidth: 520)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
            .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Theme.stroke, lineWidth: 1))
            .shadow(color: .black.opacity(0.4), radius: 24, y: 8)
            .padding(.horizontal, 18)
            .transition(.move(edge: .top).combined(with: .opacity))
        }
    }
}

// MARK: - Goal editor

struct GoalSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var description = ""
    @State private var maxRounds = 10

    var body: some View {
        NavigationStack {
            Form {
                Section("Goal") {
                    TextField("What should DSH keep working toward?", text: $description, axis: .vertical)
                        .lineLimit(2...5)
                    Stepper("Max rounds: \(maxRounds)", value: $maxRounds, in: 1...50)
                }
                if let goal = model.projection?.goal {
                    Section("Current") {
                        Text(goal.description.isEmpty ? "(no description)" : goal.description)
                        Text("phase: \(goal.phase.rawValue) · revision \(goal.revision)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Button("Mark complete", role: .destructive) {
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
                        Text("Save goal").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                    .disabled(description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Goal")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
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
        .frame(minWidth: 380, minHeight: 360)
    }
}

// MARK: - Todo

struct TodoSheet: View {
    let items: [TodoItem]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if items.isEmpty {
                    Text("No todos yet. Ask DSH to plan a task.")
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    HStack(spacing: 10) {
                        Image(systemName: symbol(item.status))
                            .foregroundStyle(color(item.status))
                        Text(item.content)
                            .strikethrough(item.status == .completed)
                            .foregroundStyle(item.status == .completed ? Color.secondary : Color.primary)
                    }
                    .padding(.vertical, 2)
                }
            }
            .navigationTitle("Plan")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .frame(minWidth: 320, minHeight: 360)
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
        case .pending: return .secondary
        case .inProgress: return Theme.warning
        case .completed: return Theme.success
        }
    }
}

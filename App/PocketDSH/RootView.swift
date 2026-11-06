import SwiftUI
import DSHKit

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            SidebarView()
                .navigationSplitViewColumnWidth(min: 240, ideal: 290, max: 360)
        } detail: {
            ChatScreen()
        }
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .overlay(alignment: .bottom) {
            ApprovalOverlay(broker: model.approvals)
                .padding(.bottom, 12)
        }
        .sheet(isPresented: $model.showSettings) {
            SettingsView()
                .environmentObject(model)
        }
        .sheet(isPresented: $model.showTodos) {
            TodoSheet(items: model.projection?.todos ?? [])
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $model.showGoal) {
            GoalSheet()
                .environmentObject(model)
        }
        .alert("Something went wrong", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}

// MARK: - Sidebar

struct SidebarView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selection: SessionID?

    var body: some View {
        List(selection: $selection) {
            Section {
                Button {
                    Task { await model.createSession() }
                } label: {
                    Label("New chat", systemImage: "plus.circle.fill")
                        .font(.system(.body, design: .rounded, weight: .semibold))
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
            }

            Section("Sessions") {
                if model.sessions.isEmpty {
                    Text("No sessions yet")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                ForEach(model.sessions) { session in
                    SessionRow(session: session, selected: session.id == model.currentID)
                        .tag(session.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            Task { await model.open(session) }
                        }
                        .contextMenu {
                            Button("Delete", role: .destructive) {
                                Task { await model.delete(session) }
                            }
                        }
                }
                .onDelete { indexSet in
                    let targets = indexSet.map { model.sessions[$0] }
                    Task { for target in targets { await model.delete(target) } }
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.backgroundGradient)
        .safeAreaInset(edge: .bottom) {
            HStack(spacing: 10) {
                Button {
                    model.showSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .font(.footnote)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(model.config.model)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .background(.ultraThinMaterial)
        }
        .navigationTitle("DSH Pocket")
    }
}

private struct SessionRow: View {
    let session: SessionSummary
    let selected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .lineLimit(1)
            HStack(spacing: 6) {
                Text(relativeTime(session.updatedAt))
                if session.eventCount > 0 {
                    Text("·")
                    Text("\(session.eventCount) ev")
                }
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .listRowBackground(selected ? Theme.accent.opacity(0.14) : Color.clear)
    }

    private func relativeTime(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

// MARK: - Empty state

struct EmptyStateView: View {
    @EnvironmentObject private var model: AppModel
    @State private var prompt = ""

    private let suggestions = [
        "Explain this codebase",
        "Find and fix a bug",
        "Write tests for a module",
        "Plan a refactor",
    ]

    var body: some View {
        VStack(spacing: 22) {
            Spacer()
            ZStack {
                Circle()
                    .fill(Theme.accent.opacity(0.16))
                    .frame(width: 78, height: 78)
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            VStack(spacing: 6) {
                Text("DSH Pocket")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                Text("DeepSeek Harness, running natively on your Apple device.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                ForEach(suggestions, id: \.self) { suggestion in
                    Button {
                        prompt = suggestion
                    } label: {
                        Text(suggestion)
                            .font(.system(.subheadline, design: .rounded))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .glassCard(cornerRadius: 12)
                    }
                    .buttonStyle(.plain)
                }
            }
            .frame(maxWidth: 380)

            Spacer()
            ComposerView(text: $prompt)
                .frame(maxWidth: 720)
                .padding(.horizontal, 18)
                .padding(.bottom, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.backgroundGradient)
    }
}


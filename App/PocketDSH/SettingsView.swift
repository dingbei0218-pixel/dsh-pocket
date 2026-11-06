import SwiftUI
import DSHKit

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var draft = DSHConfig.default
    @State private var apiKey = ""
    @State private var showKey = false
    @State private var saved = false

    private let presets: [(String, String)] = [
        ("safe", "Safe — read-only, ask for anything dangerous"),
        ("review", "Review — read-only, ask before edits"),
        ("default", "Default — workspace write with approvals"),
        ("danger", "Danger — full access, no approvals"),
    ]

    var body: some View {
        NavigationStack {
            Form {
                Section("DeepSeek") {
                    HStack {
                        Group {
                            if showKey {
                                TextField("sk-…", text: $apiKey)
                            } else {
                                SecureField("sk-…", text: $apiKey)
                            }
                        }
                        .textFieldStyle(.plain)
                        .autocorrectionDisabled()
                        .noAutocapitalization()
                        Button {
                            showKey.toggle()
                        } label: {
                            Image(systemName: showKey ? "eye.slash" : "eye")
                        }
                        .buttonStyle(.plain)
                    }
                    HStack {
                        Text(model.hasAPIKey ? "Key saved in Keychain" : "No key saved")
                            .font(.caption)
                            .foregroundStyle(model.hasAPIKey ? Theme.success : Theme.warning)
                        Spacer()
                        if model.hasAPIKey {
                            Button("Clear", role: .destructive) {
                                apiKey = ""
                                Task { await model.saveAPIKey("") }
                            }
                            .font(.caption)
                        }
                    }

                    TextField("Model", text: $draft.model)
                        .noAutocapitalization()
                        .autocorrectionDisabled()
                    TextField("Base URL", text: $draft.baseURL)
                        .noAutocapitalization()
                        .autocorrectionDisabled()
                }

                Section("Permissions") {
                    Picker("Preset", selection: $draft.permissionPreset) {
                        ForEach(presets.indices, id: \.self) { index in
                            let preset = presets[index]
                            VStack(alignment: .leading) {
                                Text(preset.0.capitalized)
                                Text(preset.1).font(.caption).foregroundStyle(.secondary)
                            }
                            .tag(preset.0)
                        }
                    }
                    #if os(iOS)
                    Text("iOS never exposes a shell tool: subprocesses are not allowed. File and web tools stay inside the app workspace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #endif
                }

                Section("Tools") {
                    Toggle("Web fetch", isOn: $draft.enableWeb)
                    #if os(macOS)
                    Toggle("Shell (zsh)", isOn: $draft.enableShell)
                    Text("Shell escapes the workspace sandbox by design. Keep the default permission preset unless you trust the prompt.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    #endif
                }

                Section("Context") {
                    Stepper("Context window: \(draft.contextWindow / 1000)k tokens", value: $draft.contextWindow, in: 16_000...256_000, step: 16_000)
                    Stepper("Max steps per turn: \(draft.maxSteps)", value: $draft.maxSteps, in: 4...64)
                    TextEditor(text: $draft.customInstructions)
                        .frame(minHeight: 70)
                        .font(.callout)
                    Text("Workspace: \(model.workspace.path)")
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                }

                Section {
                    Button {
                        Task {
                            if apiKey != "" || !model.hasAPIKey {
                                await model.saveAPIKey(apiKey)
                            }
                            model.config = draft
                            saved = true
                            dismiss()
                        }
                    } label: {
                        Text("Save").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.accent)
                }
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                draft = model.config
                apiKey = ""
                Task { apiKey = await model.loadAPIKey() }
            }
            .preferredColorScheme(.dark)
        }
        .frame(minWidth: 420, minHeight: 560)
    }
}


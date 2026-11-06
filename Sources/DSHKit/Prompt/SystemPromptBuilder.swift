import Foundation

#if os(macOS)
let dshPlatformName = "macOS"
#elseif os(iOS)
let dshPlatformName = "iOS/iPadOS"
#elseif os(Windows)
let dshPlatformName = "Windows"
#else
let dshPlatformName = "Swift"
#endif

/// 系统提示词组装（对应 dsh-go `pkg/sysprompt` 的最小可用子集）。
public struct SystemPromptBuilder: Sendable {
    public var customInstructions: String
    public var includeWorkspace: Bool

    public init(customInstructions: String = "", includeWorkspace: Bool = true) {
        self.customInstructions = customInstructions
        self.includeWorkspace = includeWorkspace
    }

    public func build(workspace: URL, sandbox: SandboxGuard, tools: ToolRegistry, projection: SessionProjection) -> String {
        var sections: [String] = []

        sections.append("""
        You are DSH, a DeepSeek Harness coding agent running natively on \(dshPlatformName) inside PocketDSH.
        You help with software engineering: reading and editing code, running commands, searching files, and planning multi-step work.
        Be concise, accurate, and honest about uncertainty. Prefer doing the work over describing it.
        Answer in the user's language.
        """)

        if includeWorkspace {
            sections.append("""
            ## Environment
            - Workspace: \(workspace.path)
            - Platform: \(dshPlatformName)
            - Date: \(Self.dateString())
            - Sandbox: \(sandbox.mode.rawValue)\(sandbox.canWrite ? "" : " (read-only: do not attempt writes)")
            """)
        }

        sections.append("""
        ## Working rules
        - Read a file before editing it. Use edit_file for targeted changes and write_file only for new or fully rewritten files.
        - Use glob/grep to locate code instead of guessing paths.
        - For multi-step tasks, call todo_write with a short plan and update statuses as you go.
        - Never invent command output or file contents. If a tool fails, report the failure and adjust.
        - Keep tool inputs minimal and paths relative to the workspace when possible.
        - Do not run destructive shell commands (rm -rf, git reset --hard, force push) unless the user explicitly asks.
        - When you are done, summarize what changed and how it was verified.
        """)

        if !tools.all.isEmpty {
            let names = tools.names.joined(separator: ", ")
            sections.append("## Available tools\n\(names)")
        }

        if projection.planMode {
            sections.append("## Plan mode\nOnly research and produce a plan. Do not modify files until the user approves the plan.")
        }

        if let goal = projection.goal, goal.phase == .active {
            sections.append("""
            ## Active goal
            \(goal.description)
            Rounds used: \(goal.rounds)/\(goal.maxRounds). Continue until the goal is complete, then mark it complete.
            """)
        }

        if !customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("## User instructions\n\(customInstructions)")
        }

        return sections.joined(separator: "\n\n")
    }

    public static func dateString(_ date: Date = Date()) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm Z"
        return formatter.string(from: date)
    }
}

/// FNV-1a 64 位：用于 prompt/tool 代际哈希（不用于安全用途）。
public func stableHash(_ text: String) -> String {
    var hash: UInt64 = 0xcbf29ce484222325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x100000001b3
    }
    return String(format: "%016llx", hash)
}

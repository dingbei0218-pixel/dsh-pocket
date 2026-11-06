import Foundation
#if os(macOS)

/// 本地 shell 工具（仅 macOS）。
///
/// iOS 不允许创建子进程，因此 iPhone/iPad 版本不会注册该工具。
/// 由于无法对子进程做真正的 seatbelt 沙箱，这里把它标记为 dangerous：
/// 默认策略会要求用户逐次审批，`danger-full-access` 模式才会自动放行。
public enum ShellTool {
    public static func tool() -> Tool {
        Tool(
            name: "shell",
            description: "Run a shell command with /bin/zsh in the workspace. Returns combined stdout/stderr and exit code. Use for builds, tests and git.",
            parameters: Schema.object(properties: [
                "command": Schema.string("Shell command to run."),
                "timeout_seconds": Schema.integer("Timeout in seconds (default 120, max 600).", minimum: 1, maximum: 600),
            ], required: ["command"]),
            isDangerous: true,
            execute: { context, input in
                try context.sandbox.requireWritable()
                let command = try requireString(input, "command")
                let timeout = min(600, max(1, input["timeout_seconds"]?.intValue ?? 120))
                let output = try await run(command: command, cwd: context.workspace, timeout: TimeInterval(timeout))
                return .text(output)
            }
        )
    }

    static func run(command: String, cwd: URL, timeout: TimeInterval) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-lc", command]
        process.currentDirectoryURL = cwd
        var environment = ProcessInfo.processInfo.environment
        environment["PAGER"] = "cat"
        environment["GIT_PAGER"] = "cat"
        process.environment = environment

        let temporary = FileManager.default.temporaryDirectory
            .appendingPathComponent("dsh-shell-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
        let stdoutURL = temporary.appendingPathComponent("stdout")
        let stderrURL = temporary.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdoutHandle = try FileHandle(forWritingTo: stdoutURL)
        let stderrHandle = try FileHandle(forWritingTo: stderrURL)
        process.standardOutput = stdoutHandle
        process.standardError = stderrHandle
        process.standardInput = FileHandle.nullDevice

        defer {
            try? stdoutHandle.close()
            try? stderrHandle.close()
            try? FileManager.default.removeItem(at: temporary)
        }

        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        var timedOut = false
        while process.isRunning {
            if Date() >= deadline {
                timedOut = true
                process.terminate()
                break
            }
            try await Task.sleep(nanoseconds: 50_000_000)
            try Task.checkCancellation()
        }
        process.waitUntilExit()

        let stdout = (try? String(contentsOf: stdoutURL, encoding: .utf8)) ?? ""
        let stderr = (try? String(contentsOf: stderrURL, encoding: .utf8)) ?? ""
        var combined = stdout
        if !stderr.isEmpty {
            if !combined.isEmpty && !combined.hasSuffix("\n") { combined += "\n" }
            combined += stderr
        }
        if combined.count > 40_000 {
            combined = String(combined.prefix(40_000)) + "\n[truncated]"
        }
        let status = process.terminationStatus
        let header = "exit: \(status)\(timedOut ? " (timed out after \(Int(timeout))s)" : "")\n"
        return header + (combined.isEmpty ? "(no output)" : combined)
    }
}
#endif

import Foundation
import DSHKit

#if canImport(Darwin)
import Darwin
#endif

@main
struct DSHCommand {
    static func main() async {
        do {
            try await run()
        } catch {
            FileHandle.standardError.write(Data(("error: \(error.localizedDescription)\n").utf8))
            exit(1)
        }
    }

    static func run() async throws {
        var arguments = Array(CommandLine.arguments.dropFirst())
        let command = arguments.first ?? "help"
        if !arguments.isEmpty { arguments.removeFirst() }

        switch command {
        case "run":
            let parsed = Options.parseWithPositionals(arguments[...])
            try await runOnce(prompt: parsed.positionals.joined(separator: " "), options: parsed.options)
        case "chat":
            try await chat()
        case "sessions":
            try await listSessions()
        case "replay":
            let parsed = Options.parseWithPositionals(arguments[...])
            try await replay(id: parsed.positionals.first, root: parsed.options.root)
        case "help", "--help", "-h":
            printHelp()
        default:
            // 允许 `dsh "直接说一句话"` 直接进入一次性运行
            try await runOnce(prompt: ([command] + arguments).joined(separator: " "), options: Options())
        }
    }

    // MARK: - Commands

    static func runOnce(prompt: String, options: Options) async throws {
        guard !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            print("usage: dsh run \"your prompt\"")
            return
        }
        let context = try await makeContext(options: options)
        let printer = Task { await printEvents(context.agent) }
        do {
            try await context.agent.run(prompt)
        } catch {
            await printer.value
            throw error
        }
        await printer.value
        print("")
        if let projection = try? await context.agent.projection() {
            print("\n[\(projection.usage.totalTokens) tokens · \(projection.sessionID.short)]")
        }
    }

    static func chat() async throws {
        let options = try Options.parse(CommandLine.arguments.dropFirst(2))
        let context = try await makeContext(options: options)
        print("DSH Pocket CLI — session \(context.agent.sessionID.short). Type /exit to quit.")
        while true {
            print("\n› ", terminator: "")
            guard let line = readLine() else { break }
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if text.isEmpty { continue }
            if text == "/exit" || text == "/quit" { break }
            let printer = Task { await printEvents(context.agent) }
            do {
                try await context.agent.run(text)
            } catch {
                print("\nerror: \(error.localizedDescription)")
            }
            await printer.value
        }
    }

    static func listSessions() async throws {
        let options = try Options.parse(CommandLine.arguments.dropFirst(2))
        let store = SessionStore(root: options.root)
        let sessions = try await store.listSessions()
        if sessions.isEmpty {
            print("No sessions yet.")
            return
        }
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        for session in sessions {
            print("\(session.id.rawValue)  \(formatter.string(from: session.updatedAt))  \(session.title)")
        }
    }

    static func replay(id: String?, root: URL) async throws {
        guard let id else {
            print("usage: dsh replay <session-id> [--root <path>]")
            return
        }
        let store = SessionStore(root: root)
        let (header, events) = try await store.load(SessionID(rawValue: id))
        let projection = Fold.project(events, sessionID: header.id)
        print("# \(projection.displayTitle)  (\(events.count) events)\n")
        for item in projection.items {
            switch item.kind {
            case .user:
                print("YOU: \(item.text)")
            case .assistant:
                if !item.text.isEmpty { print("DSH: \(item.text)") }
            case .tool:
                print("TOOL[\(item.toolName ?? "")]: \(item.toolOutput ?? "(running)")")
            case .error:
                print("ERROR: \(item.text)")
            }
            print("")
        }
    }

    // MARK: - Helpers

    struct Context {
        var agent: Agent
    }

    static func makeContext(options: Options) async throws -> Context {
        var config = DSHConfig.default
        if let model = options.model ?? ProcessInfo.processInfo.environment["DSH_MODEL"] { config.model = model }
        if let base = options.baseURL ?? ProcessInfo.processInfo.environment["DSH_BASE_URL"] { config.baseURL = base }
        if let preset = options.preset ?? ProcessInfo.processInfo.environment["DSH_PERMISSION_PRESET"] { config.permissionPreset = preset }
        if let instructions = ProcessInfo.processInfo.environment["DSH_INSTRUCTIONS"] { config.customInstructions = instructions }

        let keyStore = EnvironmentAPIKeyStore()
        let workspace = options.workspace ?? URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let store = SessionStore(root: options.root)
        try await store.ensureRoot()

        let agent: Agent
        if let session = options.session {
            agent = try await DSHFactory.openAgent(
                store: store,
                sessionID: SessionID(rawValue: session),
                workspace: workspace,
                config: config,
                keyStore: keyStore,
                approval: cliApproval
            )
        } else {
            agent = try await DSHFactory.createAgent(
                store: store,
                workspace: workspace,
                config: config,
                keyStore: keyStore,
                approval: cliApproval
            )
        }
        return Context(agent: agent)
    }

    static func printEvents(_ agent: Agent) async {
        var wroteText = false
        for await event in await agent.events() {
            switch event.type {
            case .assistantReasoning:
                if let text = event.text { print("\u{001B}[2m\(text)\u{001B}[0m", terminator: "") }
            case .assistantChunk:
                if let text = event.text {
                    wroteText = true
                    print(text, terminator: "")
                    fflush(stdout)
                }
            case .toolCall:
                if wroteText { print(""); wroteText = false }
                print("\n⚙ \(event.toolName ?? "tool") \(event.data["input"]?.jsonString() ?? "")")
            case .toolResult:
                let output = event.output ?? ""
                let first = output.split(separator: "\n").first.map(String.init) ?? ""
                print("  ↳ \(first.prefix(200))")
            case .turnEnd:
                if wroteText { print("") }
                return
            case .agentError:
                print("\n⚠ \(event.data["message"]?.stringValue ?? "agent error")")
            case .llmError:
                print("\n⚠ LLM: \(event.data["error"]?.stringValue ?? "error")")
            default:
                break
            }
        }
    }

    static let cliApproval: ApprovalHandler = { request in
        print("\n⚠ Approval required: \(request.summary)")
        print("  \(request.input.jsonString(pretty: true))")
        print("Allow? [y/N] ", terminator: "")
        let answer = readLine()?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return answer == "y" || answer == "yes"
    }

    static func printHelp() {
        print("""
        DSH Pocket CLI — DeepSeek Harness agent for Apple platforms (and Windows for testing)

        USAGE
          dsh run "prompt"              Run one turn and print the streamed answer
          dsh chat                      Interactive multi-turn session
          dsh sessions                  List saved sessions
          dsh replay <session-id>       Render a saved session

        OPTIONS
          -C, --workspace <path>        Workspace root (default: current directory)
          --session <id>                Resume an existing session
          --model <name>                Model (default: deepseek-chat)
          --base-url <url>              OpenAI-compatible base URL
          --preset <safe|review|default|danger>
          --root <path>                 Session store root

        ENVIRONMENT
          DEEPSEEK_API_KEY              API key (required)
          DSH_MODEL, DSH_BASE_URL, DSH_PERMISSION_PRESET, DSH_INSTRUCTIONS
          DSH_HOME                      Override session store root
        """)
    }
}

struct Options {
    var workspace: URL?
    var session: String?
    var model: String?
    var baseURL: String?
    var preset: String?
    var root: URL

    init() {
        if let home = ProcessInfo.processInfo.environment["DSH_HOME"], !home.isEmpty {
            root = URL(fileURLWithPath: home)
        } else {
            root = SessionStore.defaultRoot()
        }
    }

    static func parse(_ arguments: ArraySlice<String>) throws -> Options {
        parseWithPositionals(arguments).options
    }

    struct Parsed {
        var options: Options
        var positionals: [String]
    }

    static func parseWithPositionals(_ arguments: ArraySlice<String>) -> Parsed {
        var options = Options()
        var positionals: [String] = []
        var index = arguments.startIndex
        while index < arguments.endIndex {
            let argument = arguments[index]
            func next() -> String? {
                let following = arguments.index(after: index)
                guard following < arguments.endIndex else { return nil }
                index = following
                return arguments[following]
            }
            switch argument {
            case "-C", "--workspace":
                if let value = next() { options.workspace = URL(fileURLWithPath: value) }
            case "--session":
                options.session = next()
            case "--model":
                options.model = next()
            case "--base-url":
                options.baseURL = next()
            case "--preset":
                options.preset = next()
            case "--root":
                if let value = next() { options.root = URL(fileURLWithPath: value) }
            default:
                positionals.append(argument)
            }
            index = arguments.index(after: index)
        }
        return Parsed(options: options, positionals: positionals)
    }
}

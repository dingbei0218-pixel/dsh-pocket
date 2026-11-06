import Foundation

/// 应用/CLI 共享配置。
public struct DSHConfig: Codable, Sendable, Equatable {
    public var model: String
    public var baseURL: String
    public var reasoningEffort: String
    public var temperature: Double?
    public var maxTokens: Int?
    /// safe / review / default / danger（对齐 dsh-go permission presets）
    public var permissionPreset: String
    public var customInstructions: String
    public var enableShell: Bool
    public var enableWeb: Bool
    public var contextWindow: Int
    public var maxSteps: Int
    public var maxRetries: Int

    public init(
        model: String = "deepseek-chat",
        baseURL: String = "https://api.deepseek.com",
        reasoningEffort: String = "",
        temperature: Double? = nil,
        maxTokens: Int? = nil,
        permissionPreset: String = "default",
        customInstructions: String = "",
        enableShell: Bool = true,
        enableWeb: Bool = true,
        contextWindow: Int = 128_000,
        maxSteps: Int = 24,
        maxRetries: Int = 3
    ) {
        self.model = model
        self.baseURL = baseURL
        self.reasoningEffort = reasoningEffort
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.permissionPreset = permissionPreset
        self.customInstructions = customInstructions
        self.enableShell = enableShell
        self.enableWeb = enableWeb
        self.contextWindow = contextWindow
        self.maxSteps = maxSteps
        self.maxRetries = maxRetries
    }

    public static let `default` = DSHConfig()

    public var sandboxMode: SandboxMode { resolveSandboxMode(forPreset: permissionPreset) }
    public var approvalPolicy: ApprovalPolicy { ApprovalPolicy.from(preset: permissionPreset) }

    public var agentConfig: AgentConfig {
        AgentConfig(
            model: model,
            temperature: temperature,
            maxTokens: maxTokens,
            maxSteps: maxSteps,
            maxRetries: maxRetries,
            contextWindow: contextWindow,
            compactionThreshold: 0.8,
            customInstructions: customInstructions
        )
    }

    public func provider(apiKey: @escaping @Sendable () async throws -> String) throws -> LLMProvider {
        guard let url = URL(string: baseURL), url.scheme != nil else {
            throw ConfigError.invalidBaseURL(baseURL)
        }
        return DeepSeekProvider(config: DeepSeekConfig(
            baseURL: url,
            model: model,
            apiKey: apiKey,
            reasoningEffort: reasoningEffort.isEmpty ? nil : reasoningEffort,
            temperature: temperature,
            maxTokens: maxTokens
        ))
    }

    public func tools() -> ToolRegistry {
        var all: [Tool] = []
        all.append(contentsOf: FileTools.all())
        all.append(contentsOf: SearchTools.all())
        all.append(contentsOf: PlanningTools.all())
        if enableWeb { all.append(contentsOf: WebTools.all()) }
        #if os(macOS)
        if enableShell { all.append(ShellTool.tool()) }
        #endif
        return ToolRegistry(tools: all)
    }
}

public enum ConfigError: Error, LocalizedError, Sendable {
    case invalidBaseURL(String)
    case unsupportedOperation(String)

    public var errorDescription: String? {
        switch self {
        case .invalidBaseURL(let value): return "Invalid base URL: \(value)"
        case .unsupportedOperation(let message): return message
        }
    }
}

// MARK: - 凭证

/// API Key 读取接缝。App 用 Keychain 实现；CLI 用环境变量。
public protocol APIKeyStore: Sendable {
    func apiKey() async -> String?
    func setAPIKey(_ key: String) async throws
    func clearAPIKey() async throws
}

public struct EnvironmentAPIKeyStore: APIKeyStore {
    public let variable: String

    public init(variable: String = "DEEPSEEK_API_KEY") {
        self.variable = variable
    }

    public func apiKey() async -> String? {
        ProcessInfo.processInfo.environment[variable]
    }

    public func setAPIKey(_ key: String) async throws {
        #if canImport(Darwin) || os(Linux)
        setenv(variable, key, 1)
        #else
        throw ConfigError.unsupportedOperation("Setting environment variables is not supported on this platform")
        #endif
    }

    public func clearAPIKey() async throws {
        #if canImport(Darwin) || os(Linux)
        unsetenv(variable)
        #else
        throw ConfigError.unsupportedOperation("Clearing environment variables is not supported on this platform")
        #endif
    }
}

/// 测试 / 预览用的内存凭证。
public actor MemoryAPIKeyStore: APIKeyStore {
    private var key: String?

    public init(key: String? = nil) { self.key = key }

    public func apiKey() async -> String? { key }
    public func setAPIKey(_ key: String) async throws { self.key = key }
    public func clearAPIKey() async throws { key = nil }
}


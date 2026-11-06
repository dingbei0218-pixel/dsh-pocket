import Foundation

/// 工作区沙箱：把工具的文件访问限制在会话工作目录内。
///
/// 与 DSH 的 `read-only / workspace-write / danger-full-access` 三态对齐：
/// - `read-only`：只能读；
/// - `workspace-write`：读写都必须在 root 内；
/// - `danger-full-access`：不做路径限制（macOS 本地开发模式）。
///
/// iOS 上 App 本身已处于系统沙箱，这里的 guard 是第二道「工作区」边界。
public struct SandboxGuard: Sendable {
    public let root: URL
    public let mode: SandboxMode

    public init(root: URL, mode: SandboxMode = .workspaceWrite) {
        self.root = root.standardizedFileURL.resolvingSymlinksInPath()
        self.mode = mode
    }

    public var canWrite: Bool { mode != .readOnly }

    /// 把用户/模型给的路径解析成绝对路径，并做越界检查。
    public func resolve(_ path: String, mustExist: Bool = false) throws -> URL {
        guard !path.isEmpty else { throw ToolError("path is empty") }
        let expanded = (path as NSString).expandingTildeInPath
        let url: URL
        if expanded.hasPrefix("/") {
            url = URL(fileURLWithPath: expanded)
        } else {
            url = root.appendingPathComponent(expanded)
        }
        let normalized = url.standardizedFileURL.resolvingSymlinksInPath()
        if mode != .dangerFullAccess {
            let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
            guard normalized.path == root.path || normalized.path.hasPrefix(rootPath) else {
                throw ToolError("path escapes workspace: \(path)")
            }
        }
        if mustExist && !FileManager.default.fileExists(atPath: normalized.path) {
            throw ToolError("path does not exist: \(path)")
        }
        return normalized
    }

    public func requireWritable() throws {
        guard canWrite else { throw ToolError("sandbox is read-only; write operations are blocked") }
    }

    /// 展示用相对路径。
    public func displayPath(_ url: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if url.path.hasPrefix(rootPath) {
            return String(url.path.dropFirst(rootPath.count))
        }
        return url.path
    }
}

import Foundation

/// 搜索工具：glob / grep。
public enum SearchTools {
    private static let skippedDirectories: Set<String> = [".git", ".svn", ".hg", "node_modules", "DerivedData", ".build", ".swiftpm"]

    public static func all() -> [Tool] { [glob(), grep()] }

    // MARK: - glob

    public static func glob() -> Tool {
        Tool(
            name: "glob",
            description: "Find files by glob pattern. Supports *, **, ? and {a,b}. Returns paths relative to the workspace.",
            parameters: Schema.object(properties: [
                "pattern": Schema.string("Glob pattern, e.g. '**/*.swift' or 'Sources/**/*.md'."),
                "path": Schema.string("Directory to search from (default '.')."),
                "limit": Schema.integer("Maximum results (default 200, max 1000).", minimum: 1, maximum: 1000),
            ], required: ["pattern"]),
            isReadOnly: true,
            execute: { context, input in
                let pattern = try requireString(input, "pattern")
                let base = input["path"]?.stringValue ?? "."
                let limit = min(1000, max(1, input["limit"]?.intValue ?? 200))
                let root = try context.sandbox.resolve(base, mustExist: true)
                let matcher = GlobMatcher(pattern)
                var matches: [String] = []
                let keys: [URLResourceKey] = [.isDirectoryKey]
                let enumerator = FileManager.default.enumerator(
                    at: root,
                    includingPropertiesForKeys: keys,
                    options: [.skipsHiddenFiles, .skipsPackageDescendants]
                )
                while let url = enumerator?.nextObject() as? URL {
                    if matches.count >= limit { break }
                    if skippedDirectories.contains(url.lastPathComponent) {
                        enumerator?.skipDescendants()
                        continue
                    }
                    let values = try? url.resourceValues(forKeys: Set(keys))
                    if values?.isDirectory == true { continue }
                    let relative = relativePath(url, from: root)
                    if matcher.matches(relative) || matcher.matches(url.lastPathComponent) {
                        matches.append(relative)
                    }
                }
                matches.sort()
                return .text(matches.isEmpty ? "No files matched \(pattern)" : matches.joined(separator: "\n"))
            }
        )
    }

    // MARK: - grep

    public static func grep() -> Tool {
        Tool(
            name: "grep",
            description: "Search file contents with a regular expression. Returns 'path:line: text'.",
            parameters: Schema.object(properties: [
                "pattern": Schema.string("Regular expression (ICU syntax)."),
                "path": Schema.string("File or directory to search (default '.')."),
                "include": Schema.string("Only search files matching this glob, e.g. '*.swift'."),
                "case_sensitive": Schema.boolean("Case sensitive (default true)."),
                "max_results": Schema.integer("Maximum matching lines (default 100, max 500).", minimum: 1, maximum: 500),
            ], required: ["pattern"]),
            isReadOnly: true,
            execute: { context, input in
                let pattern = try requireString(input, "pattern")
                let base = input["path"]?.stringValue ?? "."
                let include = input["include"]?.stringValue
                let caseSensitive = input["case_sensitive"]?.boolValue ?? true
                let maxResults = min(500, max(1, input["max_results"]?.intValue ?? 100))
                let root = try context.sandbox.resolve(base, mustExist: true)

                let options: NSRegularExpression.Options = caseSensitive ? [] : [.caseInsensitive]
                let regex: NSRegularExpression
                do {
                    regex = try NSRegularExpression(pattern: pattern, options: options)
                } catch {
                    throw ToolError("invalid regular expression: \(error.localizedDescription)")
                }
                let includeMatcher = include.map(GlobMatcher.init)
                var results: [String] = []
                var visited = 0

                func search(_ file: URL) {
                    guard results.count < maxResults, visited < 20_000 else { return }
                    visited += 1
                    let relative = relativePath(file, from: root)
                    if let includeMatcher, !includeMatcher.matches(file.lastPathComponent), !includeMatcher.matches(relative) {
                        return
                    }
                    guard let data = try? Data(contentsOf: file), data.count <= 2 * 1024 * 1024 else { return }
                    if data.prefix(4096).contains(0) { return }
                    guard let text = String(data: data, encoding: .utf8) else { return }
                    var lineNumber = 0
                    for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                        lineNumber += 1
                        guard results.count < maxResults else { return }
                        let string = String(line)
                        let range = NSRange(string.startIndex..<string.endIndex, in: string)
                        if regex.firstMatch(in: string, options: [], range: range) != nil {
                            let trimmed = string.count > 300 ? String(string.prefix(300)) + "…" : string
                            results.append("\(relative):\(lineNumber): \(trimmed)")
                        }
                    }
                }

                var isDirectory: ObjCBool = false
                FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory)
                if isDirectory.boolValue {
                    let enumerator = FileManager.default.enumerator(
                        at: root,
                        includingPropertiesForKeys: [.isDirectoryKey],
                        options: [.skipsHiddenFiles, .skipsPackageDescendants]
                    )
                    while let url = enumerator?.nextObject() as? URL, results.count < maxResults {
                        if skippedDirectories.contains(url.lastPathComponent) {
                            enumerator?.skipDescendants()
                            continue
                        }
                        let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
                        if values?.isDirectory == true { continue }
                        search(url)
                    }
                } else {
                    search(root)
                }

                return .text(results.isEmpty ? "No matches for \(pattern)" : results.joined(separator: "\n"))
            }
        )
    }

    static func relativePath(_ url: URL, from root: URL) -> String {
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        if url.path.hasPrefix(rootPath) { return String(url.path.dropFirst(rootPath.count)) }
        return url.lastPathComponent
    }
}

/// 简化 glob：`**` 跨目录，`*` 不跨 `/`，`?` 单字符，`{a,b}` 选择。
public struct GlobMatcher: Sendable {
    private let regex: NSRegularExpression?

    public init(_ pattern: String) {
        var output = "^"
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            switch character {
            case "*":
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    output += ".*"
                    index = pattern.index(after: next)
                    if index < pattern.endIndex, pattern[index] == "/" {
                        index = pattern.index(after: index)
                        output += "/?"
                    }
                    continue
                }
                output += "[^/]*"
            case "?":
                output += "[^/]"
            case "{":
                if let closing = pattern[index...].firstIndex(of: "}") {
                    let choices = pattern[pattern.index(after: index)..<closing]
                        .split(separator: ",")
                        .map { NSRegularExpression.escapedPattern(for: String($0)) }
                    output += "(" + choices.joined(separator: "|") + ")"
                    index = closing
                } else {
                    output += "\\{"
                }
            case "/", "-", "_", ".", " ":
                output += NSRegularExpression.escapedPattern(for: String(character))
            default:
                if character.isLetter || character.isNumber {
                    output += NSRegularExpression.escapedPattern(for: String(character))
                } else {
                    output += "\\" + String(character)
                }
            }
            index = pattern.index(after: index)
        }
        output += "$"
        regex = try? NSRegularExpression(pattern: output)
    }

    public func matches(_ path: String) -> Bool {
        guard let regex else { return false }
        let range = NSRange(path.startIndex..<path.endIndex, in: path)
        return regex.firstMatch(in: path, options: [], range: range) != nil
    }
}

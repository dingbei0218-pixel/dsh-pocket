import Foundation

/// 文件系统工具：read_file / write_file / edit_file / list_dir。
public enum FileTools {
    public static let maxReadLines = 4_000
    public static let maxFileBytes = 8 * 1024 * 1024

    public static func all() -> [Tool] {
        [readFile(), writeFile(), editFile(), listDir()]
    }

    // MARK: - read_file

    public static func readFile() -> Tool {
        Tool(
            name: "read_file",
            description: "Read a text file from the workspace. Returns numbered lines. Use offset/limit for large files.",
            parameters: Schema.object(properties: [
                "path": Schema.string("File path, absolute or relative to the workspace root."),
                "offset": Schema.integer("1-based first line to read (default 1).", minimum: 1),
                "limit": Schema.integer("Maximum number of lines to read (default 2000, max 4000).", minimum: 1, maximum: maxReadLines),
            ], required: ["path"]),
            isReadOnly: true,
            execute: { context, input in
                let path = try requireString(input, "path")
                let url = try context.sandbox.resolve(path, mustExist: true)
                let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
                if let size = attributes[.size] as? Int, size > maxFileBytes {
                    throw ToolError("file is too large (\(size) bytes; limit \(maxFileBytes))")
                }
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ToolError("file is not valid UTF-8 text")
                }
                let offset = max(1, input["offset"]?.intValue ?? 1)
                let limit = min(maxReadLines, max(1, input["limit"]?.intValue ?? 2000))
                let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
                guard offset <= max(1, lines.count) else {
                    throw ToolError("offset \(offset) is beyond end of file (\(lines.count) lines)")
                }
                let start = offset - 1
                let end = min(lines.count, start + limit)
                var output = ""
                for index in start..<end {
                    let number = String(index + 1)
                    let padding = String(repeating: " ", count: max(0, 6 - number.count))
                    output += "\(padding)\(number)\t\(lines[index])\n"
                }
                if end < lines.count {
                    output += "\n[\(lines.count - end) more lines; use offset=\(end + 1) to continue]\n"
                }
                return .text(output.isEmpty ? "(empty file)" : output)
            }
        )
    }

    // MARK: - write_file

    public static func writeFile() -> Tool {
        Tool(
            name: "write_file",
            description: "Create or overwrite a UTF-8 text file. Parent directories are created automatically. Prefer edit_file for small changes.",
            parameters: Schema.object(properties: [
                "path": Schema.string("File path, absolute or relative to the workspace root."),
                "content": Schema.string("Complete file content."),
            ], required: ["path", "content"]),
            isDangerous: true,
            execute: { context, input in
                try context.sandbox.requireWritable()
                let path = try requireString(input, "path")
                let content = input["content"]?.stringValue ?? ""
                let url = try context.sandbox.resolve(path)
                await context.emit(.toolObserved(callID: context.callID, kind: "fs/write"))
                try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
                let bytes = content.utf8.count
                return .text("Wrote \(bytes) bytes to \(context.sandbox.displayPath(url))")
            }
        )
    }

    // MARK: - edit_file

    public static func editFile() -> Tool {
        Tool(
            name: "edit_file",
            description: "Replace an exact string in a text file. old_string must be unique unless replace_all is true. Read the file first.",
            parameters: Schema.object(properties: [
                "path": Schema.string("File path, absolute or relative to the workspace root."),
                "old_string": Schema.string("Exact text to replace (include surrounding context to make it unique)."),
                "new_string": Schema.string("Replacement text."),
                "replace_all": Schema.boolean("Replace every occurrence (default false)."),
            ], required: ["path", "old_string", "new_string"]),
            isDangerous: true,
            execute: { context, input in
                try context.sandbox.requireWritable()
                let path = try requireString(input, "path")
                let old = try requireString(input, "old_string")
                let new = input["new_string"]?.stringValue ?? ""
                let replaceAll = input["replace_all"]?.boolValue ?? false
                guard !old.isEmpty else { throw ToolError("old_string must not be empty") }
                let url = try context.sandbox.resolve(path, mustExist: true)
                let data = try Data(contentsOf: url)
                guard let text = String(data: data, encoding: .utf8) else {
                    throw ToolError("file is not valid UTF-8 text")
                }
                let occurrences = text.components(separatedBy: old).count - 1
                guard occurrences > 0 else { throw ToolError("old_string was not found in \(path)") }
                if occurrences > 1 && !replaceAll {
                    throw ToolError("old_string appears \(occurrences) times; add more context or set replace_all=true")
                }
                let updated = replaceAll ? text.replacingOccurrences(of: old, with: new) : text.replacingFirstOccurrence(of: old, with: new)
                await context.emit(.toolObserved(callID: context.callID, kind: "fs/edit"))
                try updated.write(to: url, atomically: true, encoding: .utf8)
                return .text("Replaced \(replaceAll ? occurrences : 1) occurrence(s) in \(context.sandbox.displayPath(url))")
            }
        )
    }

    // MARK: - list_dir

    public static func listDir() -> Tool {
        Tool(
            name: "list_dir",
            description: "List files and folders. Directories end with '/'. Default depth is 1.",
            parameters: Schema.object(properties: [
                "path": Schema.string("Directory path (default '.')."),
                "depth": Schema.integer("Recursion depth (1-3, default 1).", minimum: 1, maximum: 3),
                "include_hidden": Schema.boolean("Include dotfiles (default false)."),
            ]),
            isReadOnly: true,
            execute: { context, input in
                let path = input["path"]?.stringValue ?? "."
                let depth = min(3, max(1, input["depth"]?.intValue ?? 1))
                let includeHidden = input["include_hidden"]?.boolValue ?? false
                let url = try context.sandbox.resolve(path, mustExist: true)
                var lines: [String] = ["\(context.sandbox.displayPath(url))/"]
                try walk(url, prefix: "", depth: depth, includeHidden: includeHidden, into: &lines)
                if lines.count > 2_000 { lines = Array(lines.prefix(2_000)) + ["[truncated]"] }
                return .text(lines.joined(separator: "\n"))
            }
        )
    }

    private static func walk(_ directory: URL, prefix: String, depth: Int, includeHidden: Bool, into lines: inout [String]) throws {
        guard depth > 0 else { return }
        var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
        if !includeHidden { options.insert(.skipsHiddenFiles) }
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey],
            options: options
        ).sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }

        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
            let isDirectory = values?.isDirectory ?? false
            if isDirectory {
                lines.append("\(prefix)\(entry.lastPathComponent)/")
                try walk(entry, prefix: prefix + "  ", depth: depth - 1, includeHidden: includeHidden, into: &lines)
            } else {
                let size = values?.fileSize ?? 0
                lines.append("\(prefix)\(entry.lastPathComponent)  (\(size) B)")
            }
        }
    }
}

// MARK: - helpers

func requireString(_ input: JSONValue, _ key: String) throws -> String {
    guard let value = input[key]?.stringValue, !value.isEmpty else {
        throw ToolError("missing required argument: \(key)")
    }
    return value
}

extension String {
    func replacingFirstOccurrence(of target: String, with replacement: String) -> String {
        guard let range = range(of: target) else { return self }
        return replacingCharacters(in: range, with: replacement)
    }
}

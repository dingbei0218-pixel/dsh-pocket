import Foundation

/// 规划工具：todo_write。
public enum PlanningTools {
    public static func all() -> [Tool] { [todoWrite()] }

    public static func todoWrite() -> Tool {
        Tool(
            name: "todo_write",
            description: "Replace the session todo list (last write wins). Use it to plan multi-step work and keep statuses current.",
            parameters: Schema.object(properties: [
                "items": Schema.array(
                    "Todo items. Each item is either a string or an object {content, status: pending|in_progress|completed}.",
                    items: .object(["type": .string("string")])
                ),
            ], required: ["items"]),
            execute: { context, input in
                let raw = input["items"]?.arrayValue ?? []
                var items: [TodoItem] = []
                for entry in raw {
                    if let text = entry.stringValue {
                        items.append(TodoItem(content: text))
                    } else if let item = TodoItem(json: entry) {
                        items.append(item)
                    }
                }
                await context.emit(.todoWrite(items: items))
                let rendered = items.map { item in
                    let mark: String
                    switch item.status {
                    case .completed: mark = "[x]"
                    case .inProgress: mark = "[~]"
                    case .pending: mark = "[ ]"
                    }
                    return "\(mark) \(item.content)"
                }.joined(separator: "\n")
                return .text(rendered.isEmpty ? "Todo list cleared." : rendered)
            }
        )
    }
}

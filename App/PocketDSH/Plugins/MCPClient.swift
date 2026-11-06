import Foundation
import DSHKit

struct MCPToolInfo: Identifiable, Hashable {
    var name: String
    var description: String
    var inputSchema: JSONValue
    var id: String { name }
}

/// 最小 MCP Streamable HTTP 客户端：initialize → tools/list → tools/call。
/// 不支持 stdio / OAuth 浏览器流程；Token 由用户填写，只存本机。
actor MCPClient {
    private let url: URL
    private let token: String
    private var sessionID: String?
    private var nextID = 1
    private var initialized = false

    init(urlString: String, token: String) {
        self.url = URL(string: urlString) ?? URL(string: "http://127.0.0.1:1")!
        self.token = token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func listTools() async throws -> [MCPToolInfo] {
        try await ensureInitialized()
        let result = try await request(method: "tools/list", params: [:])
        guard let tools = result["tools"] as? [[String: Any]] else { return [] }
        return tools.compactMap { item in
            guard let name = item["name"] as? String else { return nil }
            let schema = jsonValue(item["inputSchema"]) ?? .object([
                "type": .string("object"),
                "properties": .object([:]),
            ])
            return MCPToolInfo(
                name: name,
                description: item["description"] as? String ?? "",
                inputSchema: schema
            )
        }
    }

    func callTool(name: String, arguments: JSONValue) async throws -> String {
        try await ensureInitialized()
        let args = jsonObject(arguments) ?? [:]
        let result = try await request(method: "tools/call", params: [
            "name": name,
            "arguments": args,
        ])
        if let content = result["content"] as? [[String: Any]] {
            let text = content.compactMap { item -> String? in
                if let text = item["text"] as? String { return text }
                if let data = try? JSONSerialization.data(withJSONObject: item, options: [.sortedKeys]),
                   let raw = String(data: data, encoding: .utf8) { return raw }
                return nil
            }.joined(separator: "\n")
            if !text.isEmpty { return text }
        }
        if let data = try? JSONSerialization.data(withJSONObject: result, options: [.sortedKeys, .prettyPrinted]),
           let text = String(data: data, encoding: .utf8) {
            return text
        }
        return "MCP tool returned no text content"
    }

    private func ensureInitialized() async throws {
        guard !initialized else { return }
        let result = try await request(method: "initialize", params: [
            "protocolVersion": "2024-11-05",
            "capabilities": [:],
            "clientInfo": ["name": "DSH Pocket", "version": "1.0.0"],
        ])
        _ = result
        try await notify(method: "notifications/initialized", params: [:])
        initialized = true
    }

    private func notify(method: String, params: [String: Any]) async throws {
        var body: [String: Any] = ["jsonrpc": "2.0", "method": method]
        if !params.isEmpty { body["params"] = params }
        _ = try await send(body)
    }

    private func request(method: String, params: [String: Any]) async throws -> [String: Any] {
        let id = nextID
        nextID += 1
        var body: [String: Any] = ["jsonrpc": "2.0", "id": id, "method": method]
        if !params.isEmpty { body["params"] = params }
        let payload = try await send(body)
        if let error = payload["error"] as? [String: Any] {
            throw NSError(domain: "MCP", code: 1, userInfo: [
                NSLocalizedDescriptionKey: error["message"] as? String ?? "MCP error",
            ])
        }
        guard let result = payload["result"] as? [String: Any] else {
            throw NSError(domain: "MCP", code: 2, userInfo: [NSLocalizedDescriptionKey: "MCP response missing result"])
        }
        return result
    }

    private func send(_ body: [String: Any]) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("2024-11-05", forHTTPHeaderField: "MCP-Protocol-Version")
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        if let sessionID {
            request.setValue(sessionID, forHTTPHeaderField: "Mcp-Session-Id")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body, options: [])

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NSError(domain: "MCP", code: 3, userInfo: [NSLocalizedDescriptionKey: "No HTTP response"])
        }
        if let sid = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !sid.isEmpty {
            sessionID = sid
        }
        guard (200..<300).contains(http.statusCode) else {
            let text = String(data: data, encoding: .utf8) ?? ""
            throw NSError(domain: "MCP", code: http.statusCode, userInfo: [
                NSLocalizedDescriptionKey: "HTTP \(http.statusCode) \(text.prefix(160))",
            ])
        }
        guard !data.isEmpty else { return [:] }
        return try parsePayload(data)
    }

    private func parsePayload(_ data: Data) throws -> [String: Any] {
        if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        // Streamable HTTP servers may answer with SSE frames.
        guard let text = String(data: data, encoding: .utf8) else { return [:] }
        for line in text.components(separatedBy: .newlines).reversed() {
            guard line.hasPrefix("data:") else { continue }
            let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
            guard let raw = payload.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else { continue }
            return object
        }
        return [:]
    }

    private func jsonValue(_ any: Any?) -> JSONValue? {
        guard let any, JSONSerialization.isValidJSONObject(any) || any is String || any is NSNumber else { return nil }
        guard let data = try? JSONSerialization.data(withJSONObject: any) else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }

    private func jsonObject(_ value: JSONValue) -> [String: Any]? {
        guard let data = try? JSONEncoder().encode(value),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        return object
    }
}

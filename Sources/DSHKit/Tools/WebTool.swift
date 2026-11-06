import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// 联网抓取：HTML → 纯文本。
public enum WebTools {
    public static func all() -> [Tool] { [fetch()] }

    public static func fetch() -> Tool {
        Tool(
            name: "web_fetch",
            description: "Fetch a public HTTP(S) page and return readable text (HTML tags stripped, max 20k chars).",
            parameters: Schema.object(properties: [
                "url": Schema.string("Absolute http(s) URL."),
                "max_chars": Schema.integer("Maximum characters to return (default 20000, max 60000).", minimum: 1000, maximum: 60000),
            ], required: ["url"]),
            isDangerous: true,
            execute: { _, input in
                let raw = try requireString(input, "url")
                guard let url = URL(string: raw), let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https", let host = url.host else {
                    throw ToolError("invalid URL: \(raw)")
                }
                if isPrivateHost(host) {
                    throw ToolError("refusing to fetch private/local host: \(host)")
                }
                var request = URLRequest(url: url)
                request.timeoutInterval = 30
                request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 14_0) DSHKit/1.0", forHTTPHeaderField: "User-Agent")
                request.setValue("text/html,application/xhtml+xml,text/plain,application/json;q=0.9,*/*;q=0.5", forHTTPHeaderField: "Accept")

                let (data, response) = try await HTTP.data(for: request)
                guard (200..<300).contains(response.statusCode) else {
                    throw ToolError("HTTP \(response.statusCode) for \(url.absoluteString)")
                }
                guard data.count <= 5 * 1024 * 1024 else {
                    throw ToolError("response too large (\(data.count) bytes)")
                }
                let contentType = response.value(forHTTPHeaderField: "Content-Type")?.lowercased() ?? ""
                let decoded = String(data: data, encoding: .utf8)
                    ?? String(data: data, encoding: .isoLatin1)
                    ?? ""
                let text: String
                if contentType.contains("html") || decoded.lowercased().contains("<html") {
                    text = simplifyHTML(decoded)
                } else {
                    text = decoded
                }
                let limit = min(60_000, max(1_000, input["max_chars"]?.intValue ?? 20_000))
                let body = text.count > limit ? String(text.prefix(limit)) + "\n[truncated]" : text
                return .text("URL: \(response.url?.absoluteString ?? url.absoluteString)\nStatus: \(response.statusCode)\n\n\(body)")
            }
        )
    }

    static func isPrivateHost(_ host: String) -> Bool {
        let lower = host.lowercased()
        if lower == "localhost" || lower.hasSuffix(".local") || lower == "::1" { return true }
        let parts = lower.split(separator: ".").compactMap { Int($0) }
        guard parts.count == 4 else { return false }
        if parts[0] == 10 || parts[0] == 127 { return true }
        if parts[0] == 192 && parts[1] == 168 { return true }
        if parts[0] == 172 && (16...31).contains(parts[1]) { return true }
        if parts[0] == 169 && parts[1] == 254 { return true }
        return false
    }

    static func simplifyHTML(_ html: String) -> String {
        var text = html
        for pattern in [
            "(?is)<script[^>]*>.*?</script>",
            "(?is)<style[^>]*>.*?</style>",
            "(?is)<noscript[^>]*>.*?</noscript>",
            "(?is)<!--.*?-->",
        ] {
            text = text.replacingOccurrences(of: pattern, with: " ", options: .regularExpression)
        }
        text = text.replacingOccurrences(of: "(?i)<br\\s*/?>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?i)</(p|div|li|h[1-6]|tr|section|article)>", with: "\n", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        let entities = [
            "&nbsp;": " ", "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&mdash;": "—", "&ndash;": "–", "&hellip;": "…",
        ]
        for (entity, replacement) in entities {
            text = text.replacingOccurrences(of: entity, with: replacement)
        }
        text = text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "\\n\\s*\\n\\s*\\n+", with: "\n\n", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

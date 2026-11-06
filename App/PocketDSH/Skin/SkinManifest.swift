import Foundation

/// DSH Skin Manifest v2（兼容 `https://schemas.linxin666.org/dsh-skin/v2.json`）。
///
/// 这里只解码 App 需要的字段；未知字段会被忽略，因此可以安全读取市场里更新过的皮肤。
struct SkinManifest: Codable, Identifiable, Hashable {
    struct Preview: Codable, Hashable {
        var light: String?
        var dark: String?
    }

    struct BackgroundLayer: Codable, Hashable {
        var type: String
        var src: String
        var scrim: String?
    }

    struct Contributes: Codable, Hashable {
        var stylesheet: String
        var patches: String?
        var backgroundMedia: [String: BackgroundLayer]?
    }

    var skinManifestVersion: Int
    var id: String
    var name: String
    var nameEn: String
    var version: String
    var author: String
    var tagline: String?
    var description: String?
    var tags: [String]?
    var accent: String?
    var order: Int?
    var license: String?
    var attribution: String?
    var preview: Preview?
    var contributes: Contributes

    var displayName: String { name.isEmpty ? nameEn : name }
    var darkBackground: BackgroundLayer? { contributes.backgroundMedia?["dark"] ?? contributes.backgroundMedia?["light"] }
}

/// 从 skin.css 中解析 `--dsw-alias-*` token。
enum SkinCSS {
    /// 返回合并后的 token 表；`body[data-ds-dark-theme]` 块会覆盖 `:root/body` 的浅色值。
    static func tokens(from css: String) -> [String: String] {
        let stripped = stripComments(css)
        var base: [String: String] = [:]
        var dark: [String: String] = [:]

        for block in blocks(in: stripped) {
            let selector = block.selector.lowercased()
            let isDark = selector.contains("dark")
            let isBase = selector.contains(":root") || selector == "body" || selector.hasPrefix("body,")
            guard isDark || isBase else { continue }

            for (name, value) in declarations(in: block.body) where name.hasPrefix("--dsw-alias-") {
                if isDark {
                    dark[name] = value
                } else {
                    base[name] = value
                }
            }
        }

        var merged = base
        for (key, value) in dark { merged[key] = value }

        // 展开一层层 var(...)，最多 8 层，防止皮肤里出现循环引用。
        var resolved: [String: String] = [:]
        for key in merged.keys {
            if let value = resolve(key, in: merged, depth: 0) {
                resolved[key] = value
            }
        }
        return resolved
    }

    /// 解析 CSS 里的 `background: linear-gradient(...)` 中的首个颜色（用于 scrim 兜底）。
    static func firstColor(in value: String) -> String? {
        guard let range = value.range(of: "rgba?\\s*\\([^)]*\\)|#[0-9a-fA-F]{3,8}", options: .regularExpression) else {
            return nil
        }
        return String(value[range])
    }

    // MARK: - Internals

    private static func resolve(_ key: String, in table: [String: String], depth: Int) -> String? {
        guard depth < 8, let raw = table[key] else { return nil }
        let value = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("var(") else { return value }
        guard let close = value.lastIndex(of: ")") else { return value }
        let inner = value[value.index(value.startIndex, offsetBy: 4)..<close]
        let parts = inner.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false)
        let name = parts[0].trimmingCharacters(in: .whitespaces)
        if let resolved = resolve(name, in: table, depth: depth + 1) {
            return resolved
        }
        if parts.count > 1 {
            return String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func stripComments(_ css: String) -> String {
        css.replacingOccurrences(of: "(?s)/\\*.*?\\*/", with: "", options: .regularExpression)
    }

    private static func blocks(in css: String) -> [(selector: String, body: String)] {
        guard let regex = try? NSRegularExpression(pattern: "(?s)([^{}]+)\\{([^{}]*)\\}", options: []) else {
            return []
        }
        let range = NSRange(css.startIndex..<css.endIndex, in: css)
        return regex.matches(in: css, options: [], range: range).compactMap { match in
            guard match.numberOfRanges == 3,
                  let selectorRange = Range(match.range(at: 1), in: css),
                  let bodyRange = Range(match.range(at: 2), in: css) else { return nil }
            return (
                String(css[selectorRange]).trimmingCharacters(in: .whitespacesAndNewlines),
                String(css[bodyRange])
            )
        }
    }

    private static func declarations(in body: String) -> [(String, String)] {
        body.split(separator: ";", omittingEmptySubsequences: true).compactMap { part -> (String, String)? in
            let declaration = String(part)
            guard let colon = declaration.firstIndex(of: ":") else { return nil }
            let name = String(declaration[..<colon]).trimmingCharacters(in: .whitespacesAndNewlines)
            let value = String(declaration[declaration.index(after: colon)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard name.hasPrefix("--"), !value.isEmpty else { return nil }
            return (name, value)
        }
    }
}

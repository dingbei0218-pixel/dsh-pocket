import SwiftUI

/// 一个按 CSS 语义解析出来的颜色（保留 alpha，便于在深色底上合成）。
struct CSSColor: Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let black = CSSColor(red: 0, green: 0, blue: 0, alpha: 1)
    static let white = CSSColor(red: 1, green: 1, blue: 1, alpha: 1)

    var color: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }

    func over(_ base: CSSColor) -> CSSColor {
        let outAlpha = alpha + base.alpha * (1 - alpha)
        guard outAlpha > 0 else { return .black }
        let r = (red * alpha + base.red * base.alpha * (1 - alpha)) / outAlpha
        let g = (green * alpha + base.green * base.alpha * (1 - alpha)) / outAlpha
        let b = (blue * alpha + base.blue * base.alpha * (1 - alpha)) / outAlpha
        return CSSColor(red: r, green: g, blue: b, alpha: outAlpha)
    }

    func withAlpha(_ value: Double) -> CSSColor {
        CSSColor(red: red, green: green, blue: blue, alpha: max(0, min(1, value)))
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// 支持 #RGB / #RGBA / #RRGGBB / #RRGGBBAA / rgb() / rgba() / 具名色。
    init?(css raw: String) {
        var value = raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !value.isEmpty else { return nil }

        if value.hasPrefix("var(") {
            guard let close = value.lastIndex(of: ")") else { return nil }
            let inner = value[value.index(value.startIndex, offsetBy: 4)..<close]
            value = inner.split(separator: ",").first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        }

        switch value {
        case "transparent": return nil
        case "black": self = .black; return
        case "white": self = .white; return
        default: break
        }

        if value.hasPrefix("#") {
            let chars = Array(value.dropFirst())
            func component(_ slice: ArraySlice<Character>) -> Double? {
                guard let int = Int(String(slice), radix: 16) else { return nil }
                return Double(int) / 255.0
            }
            switch chars.count {
            case 3, 4:
                guard let r = component(chars[0...0]), let g = component(chars[1...1]), let b = component(chars[2...2]) else { return nil }
                let a = chars.count == 4 ? component(chars[3...3]) : 1
                self.init(red: r, green: g, blue: b, alpha: a ?? 1)
            case 6, 8:
                guard let r = component(chars[0...1]), let g = component(chars[2...3]), let b = component(chars[4...5]) else { return nil }
                let a = chars.count == 8 ? component(chars[6...7]) : 1
                self.init(red: r, green: g, blue: b, alpha: a ?? 1)
            default:
                return nil
            }
            return
        }

        if value.hasPrefix("rgb") {
            guard let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")") else { return nil }
            var inner = String(value[value.index(after: open)..<close])
            if inner.contains("calc(") {
                // 皮肤用 scrim 变量动态算 alpha；原生端取一个可读的静态值。
                inner = inner.split(separator: ",").prefix(3).joined(separator: ",") + ",0.55"
            }
            let parts = inner
                .replacingOccurrences(of: "/", with: ",")
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
            guard parts.count >= 3 else { return nil }
            func channel(_ text: String) -> Double? {
                if text.hasSuffix("%") {
                    return Double(String(text.dropLast())).map { $0 / 100 }
                }
                return Double(text).map { $0 / 255 }
            }
            guard let r = channel(parts[0]), let g = channel(parts[1]), let b = channel(parts[2]) else { return nil }
            let a: Double
            if parts.count >= 4 {
                if parts[3].hasSuffix("%") {
                    a = Double(String(parts[3].dropLast())).map { $0 / 100 } ?? 1
                } else {
                    a = Double(String(parts[3])) ?? 1
                }
            } else {
                a = 1
            }
            self.init(red: r, green: g, blue: b, alpha: a)
            return
        }

        return nil
    }
}

/// App 的完整视觉令牌。默认值取自 DSH Desktop 的官方暗色 token，
/// 应用皮肤时由 `skin.css` 里的 `--dsw-alias-*` 覆盖。
struct AppTheme {
    var id: String
    var name: String

    var background: Color
    var backgroundLift: Color
    var sidebar: Color
    var surface: Color
    var surfaceHover: Color
    var overlay: Color

    var stroke: Color
    var strokeStrong: Color

    var textPrimary: Color
    var textSecondary: Color
    var textTertiary: Color

    var accent: Color
    var onAccent: Color
    var userBubble: Color
    var userBubbleStroke: Color
    var selection: Color

    var success: Color
    var warning: Color
    var danger: Color

    var isDark: Bool = true
    var hasBackgroundMedia: Bool = false

    var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [background, backgroundLift, background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// DSH Desktop 官方默认外观（深色）。
    static let dsh: AppTheme = {
        let base = CSSColor(red: 21 / 255, green: 21 / 255, blue: 23 / 255)
        let layer1 = CSSColor(red: 27 / 255, green: 27 / 255, blue: 28 / 255)
        let layer2 = CSSColor(red: 35 / 255, green: 35 / 255, blue: 36 / 255)
        let layer3 = CSSColor(red: 44 / 255, green: 44 / 255, blue: 46 / 255)
        let accent = CSSColor(css: "#4d93f8") ?? .white
        return AppTheme(
            id: "dsh-default",
            name: "DSH 默认",
            background: base.color,
            backgroundLift: layer1.color,
            sidebar: CSSColor(red: 35 / 255, green: 35 / 255, blue: 35 / 255).color,
            surface: layer1.color,
            surfaceHover: layer2.color,
            overlay: layer3.color,
            stroke: Color.white.opacity(0.06),
            strokeStrong: Color.white.opacity(0.12),
            textPrimary: (CSSColor(css: "#ebeef2") ?? .white).color,
            textSecondary: (CSSColor(css: "#adb2b8") ?? .white).color,
            textTertiary: (CSSColor(css: "#81858c") ?? .white).color,
            accent: accent.color,
            onAccent: Color.black.opacity(0.9),
            userBubble: accent.withAlpha(0.16).color,
            userBubbleStroke: accent.withAlpha(0.28).color,
            selection: accent.withAlpha(0.18).color,
            success: (CSSColor(css: "#4fe0b0") ?? .white).color,
            warning: (CSSColor(css: "#ffd27a") ?? .white).color,
            danger: (CSSColor(css: "#ff6e8a") ?? .white).color,
            isDark: true,
            hasBackgroundMedia: false
        )
    }()

    /// 从皮肤 manifest + CSS token 构建主题。
    init(manifest: SkinManifest, tokens: [String: String]) {
        let base = CSSColor(css: tokens["--dsw-alias-bg-base"] ?? "")?.over(.black)
            ?? CSSColor(red: 0.06, green: 0.07, blue: 0.09)

        func token(_ names: [String], fallback: CSSColor) -> CSSColor {
            for name in names {
                if let raw = tokens[name], let color = CSSColor(css: raw) {
                    return color.over(base)
                }
            }
            return fallback.over(base)
        }

        let layer1 = token(["--dsw-alias-bg-layer-1"], fallback: base)
        let layer2 = token(["--dsw-alias-bg-layer-2", "--dsw-alias-bg-layer-1"], fallback: layer1)
        let layer3 = token(["--dsw-alias-bg-layer-3", "--dsw-alias-bg-layer-2"], fallback: layer2)
        let accent = CSSColor(css: tokens["--dsw-alias-brand-primary"] ?? manifest.accent ?? "")
            ?? CSSColor(css: manifest.accent ?? "")
            ?? CSSColor(css: "#4d93f8")!

        let overlayRaw = tokens["--dsw-alias-bg-overlay"].flatMap(CSSColor.init(css:))
        let overlay = (overlayRaw ?? layer3).over(base)

        self.init(
            id: manifest.id,
            name: manifest.name,
            background: base.color,
            backgroundLift: layer1.color,
            sidebar: token(["--dsw-alias-bg-layer-1"], fallback: base).color,
            surface: layer1.color,
            surfaceHover: layer2.color,
            overlay: overlay.color,
            stroke: token(["--dsw-alias-border-l1"], fallback: CSSColor(red: 1, green: 1, blue: 1, alpha: 0.06)).color,
            strokeStrong: token(["--dsw-alias-border-l2"], fallback: CSSColor(red: 1, green: 1, blue: 1, alpha: 0.12)).color,
            textPrimary: token(["--dsw-alias-label-primary"], fallback: CSSColor(css: "#ebeef2")!).color,
            textSecondary: token(["--dsw-alias-label-secondary"], fallback: CSSColor(css: "#adb2b8")!).color,
            textTertiary: token(["--dsw-alias-label-tertiary", "--dsw-alias-label-caption"], fallback: CSSColor(css: "#81858c")!).color,
            accent: accent.color,
            onAccent: token(["--dsw-alias-label-primary-foreground"], fallback: .black).color,
            userBubble: accent.withAlpha(0.16).over(base).color,
            userBubbleStroke: accent.withAlpha(0.30).over(base).color,
            selection: token(["--dsw-alias-bg-multi-select"], fallback: accent.withAlpha(0.18)).color,
            success: token(["--dsw-alias-state-success-primary"], fallback: CSSColor(css: "#4fe0b0")!).color,
            warning: token(["--dsw-alias-state-warn-primary", "--dsw-alias-state-warning-primary"], fallback: CSSColor(css: "#ffd27a")!).color,
            danger: token(["--dsw-alias-state-danger-primary", "--dsw-alias-state-error-primary"], fallback: CSSColor(css: "#ff6e8a")!).color,
            isDark: true,
            hasBackgroundMedia: manifest.contributes.backgroundMedia?.isEmpty == false
        )
    }

    private init(
        id: String, name: String,
        background: Color, backgroundLift: Color, sidebar: Color,
        surface: Color, surfaceHover: Color, overlay: Color,
        stroke: Color, strokeStrong: Color,
        textPrimary: Color, textSecondary: Color, textTertiary: Color,
        accent: Color, onAccent: Color, userBubble: Color, userBubbleStroke: Color, selection: Color,
        success: Color, warning: Color, danger: Color,
        isDark: Bool, hasBackgroundMedia: Bool
    ) {
        self.id = id
        self.name = name
        self.background = background
        self.backgroundLift = backgroundLift
        self.sidebar = sidebar
        self.surface = surface
        self.surfaceHover = surfaceHover
        self.overlay = overlay
        self.stroke = stroke
        self.strokeStrong = strokeStrong
        self.textPrimary = textPrimary
        self.textSecondary = textSecondary
        self.textTertiary = textTertiary
        self.accent = accent
        self.onAccent = onAccent
        self.userBubble = userBubble
        self.userBubbleStroke = userBubbleStroke
        self.selection = selection
        self.success = success
        self.warning = warning
        self.danger = danger
        self.isDark = isDark
        self.hasBackgroundMedia = hasBackgroundMedia
    }
}

private struct AppThemeKey: EnvironmentKey {
    static let defaultValue = AppTheme.dsh
}

extension EnvironmentValues {
    var appTheme: AppTheme {
        get { self[AppThemeKey.self] }
        set { self[AppThemeKey.self] = newValue }
    }
}

extension View {
    func glassCard(_ theme: AppTheme, cornerRadius: CGFloat = 14) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(theme.surface.opacity(0.72))
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(theme.stroke, lineWidth: 1)
        )
    }
}

import SwiftUI

enum Theme {
    static let background = Color(red: 0.035, green: 0.05, blue: 0.08)
    static let backgroundLift = Color(red: 0.06, green: 0.08, blue: 0.13)
    static let card = Color.white.opacity(0.06)
    static let stroke = Color.white.opacity(0.10)
    static let accent = Color(red: 0.32, green: 0.72, blue: 1.0)
    static let accentSoft = Color(red: 0.20, green: 0.45, blue: 0.85)
    static let success = Color(red: 0.35, green: 0.85, blue: 0.6)
    static let warning = Color(red: 1.0, green: 0.72, blue: 0.3)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.42)

    static var backgroundGradient: LinearGradient {
        LinearGradient(
            colors: [background, backgroundLift, background],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

extension View {
    func glassCard(cornerRadius: CGFloat = 16) -> some View {
        background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Theme.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}

extension View {
    /// 关闭首字母自动大写（API Key、路径、代码片段）。
    func noAutocapitalization() -> some View {
        textInputAutocapitalization(.never)
    }
}

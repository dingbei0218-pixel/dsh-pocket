import Foundation

/// 统一的 JSON 编解码配置。
///
/// 会话文件的 `time` 字段对齐 Go `time.Time` 的 RFC3339Nano 形状；Swift 的 `Date`
/// 只有亚毫秒精度，因此写出 3 位小数（Go 侧可无损解析），读取时兼容 1–9 位小数。
public enum DSHCoding {
    public static func encoder(pretty: Bool = false) -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(ISO8601.string(from: date))
        }
        encoder.outputFormatting = pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            guard let date = ISO8601.date(from: text) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid RFC3339 date: \(text)"
                )
            }
            return date
        }
        return decoder
    }

    public static func encode<T: Encodable>(_ value: T, pretty: Bool = false) throws -> Data {
        try encoder(pretty: pretty).encode(value)
    }

    public static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try decoder().decode(type, from: data)
    }
}

public enum ISO8601 {
    private static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let plain: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let fallback: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }()

    public static func string(from date: Date) -> String {
        withFractional.string(from: date)
    }

    public static func date(from text: String) -> Date? {
        if let date = withFractional.date(from: text) { return date }
        if let date = plain.date(from: text) { return date }
        if let date = fallback.date(from: text) { return date }

        // Go 的 RFC3339Nano 最多 9 位小数；截断到 3 位再试一次。
        if let dot = text.firstIndex(of: "."),
           let zone = text[dot...].firstIndex(where: { $0 == "Z" || $0 == "+" || $0 == "-" }) {
            let fraction = text[text.index(after: dot)..<zone]
            if fraction.count > 3 {
                let trimmed = String(fraction.prefix(3))
                let repaired = String(text[..<dot]) + "." + trimmed + String(text[zone...])
                return withFractional.date(from: repaired) ?? plain.date(from: repaired)
            }
        }
        return nil
    }
}

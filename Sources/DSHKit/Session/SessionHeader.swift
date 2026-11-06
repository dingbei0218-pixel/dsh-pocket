import Foundation

/// 会话头（静态元数据）。
///
/// 对应 dsh-go `session.SessionHeader`，字段名与 JSON 完全一致，便于桌面端与 Apple 端
/// 共享同一份 `sessions/<id>/header.json`。
public struct SessionHeader: Codable, Hashable, Sendable {
    public static let formatVersion = 1

    public enum Origin: String, Codable, Sendable {
        case created
        case fork
        case resume
    }

    public var version: Int
    public var id: SessionID
    public var createdAt: Date
    public var cwd: String?
    public var parentSession: SessionID?
    public var seedLength: UInt64?
    public var origin: Origin?
    public var delegationDepth: Int?
    public var agentPreset: String?

    public init(
        version: Int = SessionHeader.formatVersion,
        id: SessionID,
        createdAt: Date = Date(),
        cwd: String? = nil,
        parentSession: SessionID? = nil,
        seedLength: UInt64? = nil,
        origin: Origin? = .created,
        delegationDepth: Int? = 0,
        agentPreset: String? = nil
    ) {
        self.version = version
        self.id = id
        self.createdAt = createdAt
        self.cwd = cwd
        self.parentSession = parentSession
        self.seedLength = seedLength
        self.origin = origin
        self.delegationDepth = delegationDepth
        self.agentPreset = agentPreset
    }

    public func validate() throws {
        guard version == Self.formatVersion else {
            throw SessionFormatError.unsupportedVersion(version)
        }
        guard !id.isEmpty else {
            throw SessionFormatError.missingSessionID
        }
        guard createdAt.timeIntervalSince1970 > 0 else {
            throw SessionFormatError.missingCreatedAt
        }
    }

    /// 派生 fork 子会话头（父 ID / 深度 +1）。
    public func fork(childID: SessionID) -> SessionHeader {
        SessionHeader(
            id: childID,
            cwd: cwd,
            parentSession: id,
            seedLength: 0,
            origin: .fork,
            delegationDepth: (delegationDepth ?? 0) + 1,
            agentPreset: agentPreset
        )
    }

    /// 派生 resume 头（沿用同一 ID，seedLength 记录已回放事件数）。
    public func resumed(seedLength: UInt64) -> SessionHeader {
        var copy = self
        copy.origin = .resume
        copy.seedLength = seedLength
        return copy
    }
}

public enum SessionFormatError: Error, LocalizedError, Equatable {
    case unsupportedVersion(Int)
    case missingSessionID
    case missingCreatedAt
    case corruptEvent(seq: UInt64, type: String)
    case invalidHeader(String)
    case ioError(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedVersion(let version):
            return "Session format version \(version) is not supported (want \(SessionHeader.formatVersion))"
        case .missingSessionID:
            return "Session header is missing an id"
        case .missingCreatedAt:
            return "Session header is missing createdAt"
        case .corruptEvent(let seq, let type):
            return "Corrupt event at seq \(seq): unknown type \(type)"
        case .invalidHeader(let message):
            return "Invalid session header: \(message)"
        case .ioError(let message):
            return "Session I/O error: \(message)"
        }
    }
}

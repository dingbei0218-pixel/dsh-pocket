import Foundation

/// 会话摘要（会话列表用）。
public struct SessionSummary: Sendable, Identifiable, Equatable {
    public var id: SessionID { header.id }
    public var header: SessionHeader
    public var title: String
    public var preview: String
    public var eventCount: Int
    public var updatedAt: Date
    public var lastTurnReason: String?

    public init(header: SessionHeader, title: String, preview: String, eventCount: Int, updatedAt: Date, lastTurnReason: String? = nil) {
        self.header = header
        self.title = title
        self.preview = preview
        self.eventCount = eventCount
        self.updatedAt = updatedAt
        self.lastTurnReason = lastTurnReason
    }
}

/// JSONL 会话存储。
///
/// 目录布局与 dsh-go 完全一致：
/// ```
/// <root>/<session-id>/header.json
/// <root>/<session-id>/events.jsonl
/// ```
/// 每行一个 `SessionEvent`。写入使用「打开 → 追加 → synchronize → 关闭」，
/// 保证进程被杀死时最多丢失最后一行；读取时容忍最后一行半截（由 append 原子性保证）。
public actor SessionStore {
    public let root: URL
    private let fileManager = FileManager.default

    public init(root: URL) {
        self.root = root
    }

    /// 默认存储目录：macOS/iOS 的 Application Support/DSH/sessions。
    public static func defaultRoot() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("DSH", isDirectory: true)
            .appendingPathComponent("sessions", isDirectory: true)
    }

    public func ensureRoot() throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
    }

    public func sessionDirectory(_ id: SessionID) -> URL {
        root.appendingPathComponent(id.rawValue, isDirectory: true)
    }

    public func headerURL(_ id: SessionID) -> URL {
        sessionDirectory(id).appendingPathComponent("header.json")
    }

    public func eventsURL(_ id: SessionID) -> URL {
        sessionDirectory(id).appendingPathComponent("events.jsonl")
    }

    // MARK: - 创建 / 保存

    @discardableResult
    public func createSession(cwd: String?, agentPreset: String? = nil, id: SessionID = .generate()) throws -> SessionHeader {
        try ensureRoot()
        let directory = sessionDirectory(id)
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let header = SessionHeader(id: id, cwd: cwd, agentPreset: agentPreset)
        try saveHeader(header)
        if !fileManager.fileExists(atPath: eventsURL(id).path) {
            fileManager.createFile(atPath: eventsURL(id).path, contents: nil)
        }
        return header
    }

    public func saveHeader(_ header: SessionHeader) throws {
        try fileManager.createDirectory(at: sessionDirectory(header.id), withIntermediateDirectories: true)
        let data = try DSHCoding.encode(header, pretty: true)
        try data.write(to: headerURL(header.id), options: .atomic)
    }

    public func loadHeader(_ id: SessionID) throws -> SessionHeader {
        guard fileManager.fileExists(atPath: headerURL(id).path) else {
            throw SessionFormatError.ioError("session \(id.rawValue) not found")
        }
        do {
            let header = try DSHCoding.decode(SessionHeader.self, from: Data(contentsOf: headerURL(id)))
            try header.validate()
            return header
        } catch let error as SessionFormatError {
            throw error
        } catch {
            throw SessionFormatError.invalidHeader(error.localizedDescription)
        }
    }

    // MARK: - 事件

    public func append(_ event: SessionEvent, to id: SessionID, sync: Bool = true) throws {
        var line = try DSHCoding.encode(event)
        line.append(0x0A)
        let url = eventsURL(id)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: line)
        if sync { try handle.synchronize() }
    }

    public func append(events: [SessionEvent], to id: SessionID) throws {
        guard !events.isEmpty else { return }
        var blob = Data()
        for event in events {
            blob.append(try DSHCoding.encode(event))
            blob.append(0x0A)
        }
        let url = eventsURL(id)
        if !fileManager.fileExists(atPath: url.path) {
            fileManager.createFile(atPath: url.path, contents: nil)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: blob)
        try handle.synchronize()
    }

    public func loadEvents(_ id: SessionID) throws -> [SessionEvent] {
        let url = eventsURL(id)
        guard fileManager.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url)
        guard !data.isEmpty else { return [] }
        var events: [SessionEvent] = []
        let lines = data.split(separator: 0x0A, omittingEmptySubsequences: true)
        let decoder = DSHCoding.decoder()
        for (index, line) in lines.enumerated() {
            do {
                let event = try decoder.decode(SessionEvent.self, from: Data(line))
                events.append(event)
            } catch {
                // 最后一行可能是崩溃时写了一半的事件：丢弃；中间行损坏则 fail-closed。
                if index == lines.count - 1 { break }
                throw SessionFormatError.corruptEvent(
                    seq: UInt64(index + 1),
                    type: "unparseable line: \(error.localizedDescription)"
                )
            }
        }
        return events.sorted { $0.seq < $1.seq }
    }

    public func load(_ id: SessionID) throws -> (SessionHeader, [SessionEvent]) {
        let header = try loadHeader(id)
        let events = try loadEvents(id)
        return (header, events)
    }

    // MARK: - 列表 / 删除

    public func listSessions() throws -> [SessionSummary] {
        try ensureRoot()
        let directories = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        var summaries: [SessionSummary] = []
        for directory in directories {
            let values = try? directory.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let id = SessionID(rawValue: directory.lastPathComponent)
            guard let header = try? loadHeader(id) else { continue }
            let events = (try? loadEvents(id)) ?? []
            let projection = Fold.project(events, sessionID: id)
            let lastTime = events.last?.time ?? header.createdAt
            let preview = projection.items.last(where: { $0.text.isEmpty == false })?.text ?? ""
            let lastReason = events.last(where: { $0.type == .turnEnd })?.reason
            summaries.append(SessionSummary(
                header: header,
                title: projection.displayTitle,
                preview: String(preview.prefix(120)),
                eventCount: events.count,
                updatedAt: lastTime,
                lastTurnReason: lastReason
            ))
        }
        return summaries.sorted { $0.updatedAt > $1.updatedAt }
    }

    public func deleteSession(_ id: SessionID) throws {
        let directory = sessionDirectory(id)
        if fileManager.fileExists(atPath: directory.path) {
            try fileManager.removeItem(at: directory)
        }
    }

    public func fork(_ id: SessionID, copyEvents: Bool = true) throws -> SessionHeader {
        let (header, events) = try load(id)
        let child = header.fork(childID: .generate())
        try saveHeader(child)
        if copyEvents {
            var seeded: [SessionEvent] = []
            for event in events {
                var copy = event
                copy.seq = UInt64(seeded.count + 1)
                seeded.append(copy)
            }
            try append(events: seeded, to: child.id)
            try append(EventData.endSeed(parentSession: id).makeEvent(seq: UInt64(seeded.count + 1), time: Date()), to: child.id)
            var updated = child
            updated.seedLength = UInt64(seeded.count)
            try saveHeader(updated)
            return updated
        }
        return child
    }

    /// 重新落盘全部事件（用于 compaction 后压缩文件；源事件仍保留）。
    public func rewrite(_ id: SessionID, events: [SessionEvent]) throws {
        var blob = Data()
        for event in events {
            blob.append(try DSHCoding.encode(event))
            blob.append(0x0A)
        }
        try blob.write(to: eventsURL(id), options: .atomic)
    }
}

extension EventData {
    func makeEvent(seq: UInt64, time: Date = Date()) -> SessionEvent {
        SessionEvent(seq: seq, time: time, type: type, data: payload)
    }
}

import Foundation

/// 已安装的皮肤（本地目录 + manifest）。
struct InstalledSkin: Identifiable, Hashable {
    var manifest: SkinManifest
    var directory: URL

    var id: String { manifest.id }

    var previewURL: URL? {
        guard let preview = manifest.preview?.dark ?? manifest.preview?.light else { return nil }
        return directory.appendingPathComponent(preview)
    }

    var cssURL: URL {
        directory.appendingPathComponent(manifest.contributes.stylesheet)
    }

    var patchesURL: URL? {
        guard let patches = manifest.contributes.patches, !patches.isEmpty else { return nil }
        return directory.appendingPathComponent(patches)
    }

    var backgroundURL: URL? {
        guard let layer = manifest.darkBackground else { return nil }
        // iOS 端不做视频解码：视频皮肤用预览图作为静态背景，保留氛围。
        if layer.type == "video" {
            guard let preview = manifest.preview?.dark ?? manifest.preview?.light else { return nil }
            return directory.appendingPathComponent(preview)
        }
        return directory.appendingPathComponent(layer.src)
    }
}

/// 皮肤的本地仓库：扫描、安装、删除、记录当前选择。
actor SkinStore {
    let root: URL
    private let defaults = UserDefaults.standard
    private let activeKey = "dsh.skin.active"

    init(root: URL? = nil) {
        if let root {
            self.root = root
        } else {
            let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Documents")
            self.root = documents
                .appendingPathComponent("DSH", isDirectory: true)
                .appendingPathComponent("Skins", isDirectory: true)
        }
    }

    func ensureRoot() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func directory(for id: String) -> URL {
        root.appendingPathComponent(Self.safeID(id), isDirectory: true)
    }

    func list() throws -> [InstalledSkin] {
        try ensureRoot()
        let entries = try FileManager.default.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var skins: [InstalledSkin] = []
        for entry in entries {
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { continue }
            let manifestURL = entry.appendingPathComponent("skin.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  let manifest = try? JSONDecoder().decode(SkinManifest.self, from: data),
                  manifest.skinManifestVersion == 2,
                  !manifest.contributes.stylesheet.isEmpty else { continue }
            skins.append(InstalledSkin(manifest: manifest, directory: entry))
        }
        return skins.sorted {
            if ($0.manifest.order ?? 999) != ($1.manifest.order ?? 999) {
                return ($0.manifest.order ?? 999) < ($1.manifest.order ?? 999)
            }
            return $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending
        }
    }

    func importFolder(_ source: URL) throws -> InstalledSkin {
        try ensureRoot()
        let base = Self.safeID(source.lastPathComponent)
        var destination = root.appendingPathComponent(base, isDirectory: true)
        if FileManager.default.fileExists(atPath: destination.path) {
            destination = root.appendingPathComponent("\(base)-\(Int(Date().timeIntervalSince1970))", isDirectory: true)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        let manifestURL = destination.appendingPathComponent("skin.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(SkinManifest.self, from: data),
              manifest.skinManifestVersion == 2 else {
            try? FileManager.default.removeItem(at: destination)
            throw SkinError.invalidManifest
        }
        return InstalledSkin(manifest: manifest, directory: destination)
    }

    func remove(_ id: String) throws {
        let url = directory(for: id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
        if activeID() == id { setActive(nil) }
    }

    func activeID() -> String? {
        defaults.string(forKey: activeKey)
    }

    func setActive(_ id: String?) {
        if let id {
            defaults.set(id, forKey: activeKey)
        } else {
            defaults.removeObject(forKey: activeKey)
        }
    }

    func writeSkin(id: String, files: [String: Data]) throws -> InstalledSkin {
        let destination = directory(for: id)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        for (relative, data) in files {
            let safe = Self.safeRelativePath(relative)
            let url = destination.appendingPathComponent(safe)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: .atomic)
        }
        guard let data = files["skin.json"] ?? (try? Data(contentsOf: destination.appendingPathComponent("skin.json"))),
              let manifest = try? JSONDecoder().decode(SkinManifest.self, from: data) else {
            throw SkinError.invalidManifest
        }
        return InstalledSkin(manifest: manifest, directory: destination)
    }

    static func safeID(_ id: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-")
        let filtered = id.lowercased().unicodeScalars.filter { allowed.contains($0) }.map { Character(String($0)) }
        let value = String(filtered)
        return value.isEmpty ? "skin-\(UUID().uuidString.prefix(8))" : value
    }

    static func safeRelativePath(_ path: String) -> String {
        path.split(separator: "/")
            .filter { $0 != ".." && $0 != "." && !$0.isEmpty }
            .joined(separator: "/")
    }
}

enum SkinError: LocalizedError {
    case invalidManifest
    case invalidRepository
    case noSkinsFound
    case network(String)
    case installFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidManifest: return "皮肤目录缺少合法 skin.json"
        case .invalidRepository: return "Git 仓库地址不合法，示例：https://github.com/owner/repo"
        case .noSkinsFound: return "仓库里没有找到 skins/*/skin.json"
        case .network(let message): return "网络错误：\(message)"
        case .installFailed(let message): return "安装失败：\(message)"
        }
    }
}

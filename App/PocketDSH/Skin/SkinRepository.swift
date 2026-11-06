import Foundation

/// 远端（Git 仓库）里的一个皮肤。
struct RemoteSkin: Identifiable, Hashable {
    var manifest: SkinManifest
    var directory: String
    var files: [GitHubFile]

    var id: String { manifest.id }
}

struct GitHubFile: Hashable {
    var path: String
    var size: Int
}

/// 从 GitHub 仓库同步皮肤：仓库结构约定为 `skins/<id>/skin.json`（也兼容根目录下任意 `*/skin.json`）。
///
/// 只读取 manifest、CSS、预览图与背景资源；`hooks.mjs` 之类可执行代码不会被加载。
struct SkinRepository {
    var token: String?

    struct RepoRef {
        var owner: String
        var repo: String
        var branch: String?
    }

    struct SyncResult {
        var skins: [RemoteSkin]
        var ref: RepoRef
        var branch: String
    }

    func sync(from input: String) async throws -> SyncResult {
        let ref = try Self.parse(input)
        let branch: String
        if let explicit = ref.branch {
            branch = explicit
        } else {
            branch = try await defaultBranch(ref)
        }
        let tree = try await fetchTree(ref, branch: branch)

        let manifests = tree.filter { $0.path.hasSuffix("/skin.json") || $0.path == "skin.json" }
        guard !manifests.isEmpty else { throw SkinError.noSkinsFound }

        let dirs = manifests.compactMap { entry -> String? in
            guard let slash = entry.path.lastIndex(of: "/") else { return nil }
            return String(entry.path[..<slash])
        }

        var results: [RemoteSkin] = []
        try await withThrowingTaskGroup(of: RemoteSkin?.self) { group in
            var iterator = dirs.makeIterator()
            // 最多并发 6 个 manifest 请求，避免 GitHub 限流。
            for _ in 0..<min(10, dirs.count) {
                if let dir = iterator.next() {
                    group.addTask { try await loadSkin(ref: ref, branch: branch, directory: dir, tree: tree) }
                }
            }
            while let result = try await group.next() {
                if let result { results.append(result) }
                if let dir = iterator.next() {
                    group.addTask { try await loadSkin(ref: ref, branch: branch, directory: dir, tree: tree) }
                }
            }
        }

        let sorted = results.sorted {
            if ($0.manifest.order ?? 999) != ($1.manifest.order ?? 999) {
                return ($0.manifest.order ?? 999) < ($1.manifest.order ?? 999)
            }
            return $0.manifest.name.localizedStandardCompare($1.manifest.name) == .orderedAscending
        }
        return SyncResult(skins: sorted, ref: ref, branch: branch)
    }

    func download(_ skin: RemoteSkin, ref: RepoRef, branch: String) async throws -> [String: Data] {
        let allowedExtensions: Set<String> = [
            "json", "css", "jpg", "jpeg", "png", "webp", "gif", "svg", "mp4", "webm",
        ]
        var payload: [String: Data] = [:]
        var total = 0

        for file in skin.files {
            let ext = (file.path as NSString).pathExtension.lowercased()
            guard allowedExtensions.contains(ext) else { continue }
            guard total + file.size <= 60 * 1024 * 1024 else { throw SkinError.installFailed("皮肤超过 60MB 上限") }
            guard let data = try await raw(ref: ref, branch: branch, path: file.path) else { continue }
            total += data.count
            let relative = skin.directory.isEmpty ? file.path : String(file.path.dropFirst(skin.directory.count + 1))
            payload[relative] = data
        }
        guard !payload.isEmpty else {
            throw SkinError.installFailed("没有下载到可用文件")
        }
        return payload
    }

    // MARK: - GitHub API

    private func defaultBranch(_ ref: RepoRef) async throws -> String {
        let url = URL(string: "https://api.github.com/repos/\(ref.owner)/\(ref.repo)")!
        let json = try await getJSON(url)
        guard let branch = json["default_branch"] as? String else {
            throw SkinError.invalidRepository
        }
        return branch
    }

    private func fetchTree(_ ref: RepoRef, branch: String) async throws -> [GitHubFile] {
        var components = URLComponents(string: "https://api.github.com/repos/\(ref.owner)/\(ref.repo)/git/trees/\(branch)")!
        components.queryItems = [URLQueryItem(name: "recursive", value: "1")]
        let json = try await getJSON(components.url!)
        guard let tree = json["tree"] as? [[String: Any]] else {
            throw SkinError.invalidRepository
        }
        return tree.compactMap { entry in
            guard (entry["type"] as? String) == "blob", let path = entry["path"] as? String else { return nil }
            return GitHubFile(path: path, size: entry["size"] as? Int ?? 0)
        }
    }

    private func loadSkin(ref: RepoRef, branch: String, directory: String, tree: [GitHubFile]) async throws -> RemoteSkin? {
        let manifestPath = directory.isEmpty ? "skin.json" : "\(directory)/skin.json"
        guard let data = try await raw(ref: ref, branch: branch, path: manifestPath),
              let manifest = try? JSONDecoder().decode(SkinManifest.self, from: data),
              manifest.skinManifestVersion == 2 else { return nil }
        let files = tree.filter { directory.isEmpty || $0.path.hasPrefix(directory + "/") }
        return RemoteSkin(manifest: manifest, directory: directory, files: files)
    }

    private func raw(ref: RepoRef, branch: String, path: String) async throws -> Data? {
        // 模拟器 / 部分网络对 raw.githubusercontent.com 的 IPv6 路由不通，
        // 优先走 jsDelivr 的 GitHub 镜像（同样按 commit/branch 缓存）。
        for url in SkinRemoteURL.candidates(owner: ref.owner, repo: ref.repo, branch: branch, path: path) {
            var request = URLRequest(url: url)
            request.timeoutInterval = 20
            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                    return data
                }
            } catch {
                continue
            }
        }
        return nil
    }

    private func getJSON(_ url: URL) async throws -> [String: Any] {
        var request = URLRequest(url: url)
        request.timeoutInterval = 60
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("DSH-Pocket/1.0", forHTTPHeaderField: "User-Agent")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { throw SkinError.network("无效响应") }
            if http.statusCode == 403 {
                throw SkinError.network("GitHub API 限流，请在设置里填入 GitHub Token 后重试")
            }
            guard (200..<300).contains(http.statusCode) else {
                throw SkinError.network("HTTP \(http.statusCode)")
            }
            guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw SkinError.network("响应不是 JSON 对象")
            }
            return json
        } catch let error as SkinError {
            throw error
        } catch {
            throw SkinError.network(error.localizedDescription)
        }
    }

    // MARK: - URL parsing

    static func parse(_ input: String) throws -> RepoRef {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasSuffix(".git") { text.removeLast(4) }
        if !text.contains("://") { text = "https://github.com/" + text }

        guard let url = URL(string: text), let host = url.host?.lowercased(),
              host == "github.com" || host == "www.github.com" else {
            throw SkinError.invalidRepository
        }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2 else { throw SkinError.invalidRepository }
        var branch: String?
        if parts.count >= 4, parts[2] == "tree" {
            branch = parts[3...].joined(separator: "/")
        }
        return RepoRef(owner: parts[0], repo: parts[1], branch: branch)
    }
}


enum SkinRemoteURL {
    static func candidates(owner: String, repo: String, branch: String, path: String) -> [URL] {
        let encoded = path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        let cdn = "https://cdn.jsdelivr.net/gh/\(owner)/\(repo)@\(branch)/\(encoded)"
        let raw = "https://raw.githubusercontent.com/\(owner)/\(repo)/\(branch)/\(encoded)"
        return [cdn, raw].compactMap(URL.init(string:))
    }
}

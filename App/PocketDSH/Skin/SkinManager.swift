import Foundation
import Combine
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// 皮肤系统的状态中心：安装列表、远端同步、当前主题、背景图。
@MainActor
final class SkinManager: ObservableObject {
    static let defaultRepository = "https://github.com/zhu1090093659/dsh-skins"

    @Published private(set) var theme: AppTheme = .dsh
    @Published private(set) var installed: [InstalledSkin] = []
    @Published private(set) var remote: [RemoteSkin] = []
    @Published private(set) var activeID: String = "dsh-default"
    @Published private(set) var isSyncing = false
    @Published private(set) var installingID: String?
    @Published private(set) var statusMessage: String?
    @Published private(set) var backgroundIsPreview = false
    @Published private(set) var backgroundPattern: SkinPattern?
    @Published private(set) var backgroundIsArtwork = false
    @Published var errorMessage: String?

    @Published var repositoryURL: String {
        didSet {
            defaults.set(repositoryURL, forKey: "dsh.skin.repo")
            if oldValue != repositoryURL {
                remote = []
                currentRef = nil
                currentBranch = nil
                defaults.removeObject(forKey: "dsh.skin.remoteCache")
            }
        }
    }
    @Published var githubToken: String {
        didSet { defaults.set(githubToken, forKey: "dsh.skin.githubToken") }
    }

    var backgroundURL: URL?
    #if canImport(UIKit)
    private(set) var backgroundImage: UIImage?
    #endif

    private let store: SkinStore
    private let defaults = UserDefaults.standard
    private var currentRef: SkinRepository.RepoRef?
    private var currentBranch: String?

    init() {
        repositoryURL = defaults.string(forKey: "dsh.skin.repo") ?? Self.defaultRepository
        githubToken = defaults.string(forKey: "dsh.skin.githubToken") ?? ""
        store = SkinStore()
        if let data = defaults.data(forKey: "dsh.skin.remoteCache"),
           let cached = try? JSONDecoder().decode([RemoteSkin].self, from: data) {
            remote = cached
        }
        Task { await reload() }
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if let flag = arguments.firstIndex(of: "-apply"), flag + 1 < arguments.count {
            let skinID = arguments[flag + 1]
            Task {
                await self.reload()
                await self.sync()
                if let remote = self.remote.first(where: { $0.id == skinID }) {
                    await self.install(remote)
                }
            }
        }
        #endif
    }

    // MARK: - 本地

    func reload() async {
        installed = (try? await store.list()) ?? []
        if let id = await store.activeID(), let skin = installed.first(where: { $0.id == id }) {
            applyLocal(skin)
        } else {
            applyDefault()
        }
    }

    func applyDefault() {
        theme = .dsh
        backgroundURL = nil
        backgroundIsPreview = false
        backgroundPattern = nil
        backgroundIsArtwork = false
        #if canImport(UIKit)
        backgroundImage = nil
        #endif
        activeID = "dsh-default"
        Task { await store.setActive(nil) }
    }

    func apply(_ skin: InstalledSkin) {
        applyLocal(skin)
        Task { await store.setActive(skin.id) }
    }

    func remove(_ skin: InstalledSkin) {
        Task {
            try? await store.remove(skin.id)
            await reload()
        }
    }

    private func applyLocal(_ skin: InstalledSkin) {
        do {
            let css = try String(contentsOf: skin.cssURL, encoding: .utf8)
            let tokens = SkinCSS.tokens(from: css)
            theme = AppTheme(manifest: skin.manifest, tokens: tokens)
            // 1) manifest 里声明了 backgroundMedia：直接用它；
            // 2) 没有 backgroundMedia 但有 patches.css：原生端不能执行 CSS 选择器，
            //    用预览图做低透明度背景，至少保留皮肤自带的画面/纹理氛围；
            // 3) token 很少的皮肤也走预览图兜底。
            let media = skin.backgroundURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            let preview = skin.previewURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            let pattern = SkinPattern.parse(patches: skin.patchesURL)
            let artwork = SkinArtwork.find(in: skin.directory)
            backgroundPattern = pattern
            backgroundIsArtwork = false
            if let media {
                backgroundURL = media
                backgroundIsPreview = false
                theme.hasBackgroundMedia = true
            } else if let artwork {
                // skin 自带的线稿/插画优先于网格和截图，保留作者真正想放的主体。
                backgroundURL = artwork
                backgroundIsPreview = false
                backgroundIsArtwork = true
                backgroundPattern = nil
                theme.hasBackgroundMedia = true
            } else if pattern != nil {
                // patches.css 里的网格/纹理直接用 Canvas 画，胜过模糊的截图背景。
                backgroundURL = nil
                backgroundIsPreview = false
                theme.hasBackgroundMedia = true
            } else if let preview, skin.patchesURL != nil || tokens.count < 8 {
                backgroundURL = preview
                backgroundIsPreview = true
                theme.hasBackgroundMedia = true
            } else {
                backgroundURL = nil
                backgroundIsPreview = false
            }
            #if canImport(UIKit)
            backgroundImage = backgroundURL.flatMap { UIImage(contentsOfFile: $0.path) }
            #endif
            activeID = skin.id
        } catch {
            errorMessage = "读取皮肤失败：\(error.localizedDescription)"
            applyDefault()
        }
    }

    // MARK: - Git 同步

    func sync() async {
        guard !isSyncing else { return }
        isSyncing = true
        statusMessage = "正在读取仓库…"
        defer {
            isSyncing = false
            statusMessage = nil
        }
        do {
            let repository = SkinRepository(token: githubToken.isEmpty ? nil : githubToken)
            let result = try await repository.sync(from: repositoryURL)
            currentRef = result.ref
            currentBranch = result.branch
            remote = result.skins
            statusMessage = "发现 \(result.skins.count) 款皮肤"
        } catch {
            errorMessage = userFacing(error)
        }
    }

    func install(_ skin: RemoteSkin) async {
        guard installingID == nil, let ref = currentRef, let branch = currentBranch else { return }
        installingID = skin.id
        statusMessage = "正在安装 \(skin.manifest.name)…"
        defer { installingID = nil; statusMessage = nil }
        do {
            let repository = SkinRepository(token: githubToken.isEmpty ? nil : githubToken)
            let files = try await repository.download(skin, ref: ref, branch: branch)
            let installedSkin = try await store.writeSkin(id: skin.manifest.id, files: files)
            installed = (try? await store.list()) ?? installed
            apply(installedSkin)
        } catch {
            errorMessage = userFacing(error)
        }
    }

    func previewURL(for skin: RemoteSkin) -> URL? {
        guard let path = skin.manifest.preview?.dark ?? skin.manifest.preview?.light,
              let ref = currentRef, let branch = currentBranch else { return nil }
        return SkinRemoteURL.candidates(
            owner: ref.owner,
            repo: ref.repo,
            branch: branch,
            path: skin.directory.isEmpty ? path : "\(skin.directory)/\(path)"
        ).first
    }

    func previewURL(for skin: InstalledSkin) -> URL? {
        skin.previewURL
    }

    var activeSkin: InstalledSkin? {
        installed.first { $0.id == activeID }
    }

    private func userFacing(_ error: Error) -> String {
        let ns = error as NSError
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorTimedOut {
            return "请求超时。请检查网络，或在皮肤中心填入 GitHub Token 后重试。"
        }
        if ns.domain == NSURLErrorDomain, ns.code == NSURLErrorNotConnectedToInternet {
            return "当前没有网络连接。"
        }
        if let skinError = error as? SkinError {
            return skinError.localizedDescription
        }
        return error.localizedDescription
    }

    private func encodedPath(_ path: String) -> String {
        path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
    }
}


struct SkinPattern {
    var color: CSSColor
    var spacing: CGFloat
    var majorSpacing: CGFloat?

    static func parse(patches: URL?) -> SkinPattern? {
        guard let patches, let css = try? String(contentsOf: patches, encoding: .utf8) else { return nil }
        let pattern = #"repeating-linear-gradient\(to (right|bottom),\s*(#[0-9a-fA-F]{6,8})\s+0\s+1px,\s*transparent\s+1px\s+([0-9.]+)px\)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(css.startIndex..<css.endIndex, in: css)
        var color: CSSColor?
        var spaces: [CGFloat] = []
        for match in regex.matches(in: css, range: range) {
            guard match.numberOfRanges == 4,
                  let colorRange = Range(match.range(at: 2), in: css),
                  let spaceRange = Range(match.range(at: 3), in: css),
                  let value = Double(css[spaceRange]),
                  value >= 8 else { continue }
            color = CSSColor(css: String(css[colorRange])) ?? color
            spaces.append(CGFloat(value))
        }
        guard let color, let smallest = spaces.min() else { return nil }
        let major = spaces.filter { $0 > smallest * 2 }.max()
        return SkinPattern(color: color, spacing: smallest, majorSpacing: major)
    }
}


/// 从皮肤目录里找作者真正提供的画面素材（线稿、插画、纹理），跳过 preview 截图与图标。
enum SkinArtwork {
    static func find(in directory: URL) -> URL? {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return nil }

        var best: (URL, Int)?
        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  values.isRegularFile == true else { continue }
            let ext = url.pathExtension.lowercased()
            guard ["png", "jpg", "jpeg", "webp"].contains(ext) else { continue }
            let relative = url.path.replacingOccurrences(of: directory.path + "/", with: "").lowercased()
            guard !relative.hasPrefix("preview/"), !relative.hasPrefix("previews/") else { continue }
            let name = url.deletingPathExtension().lastPathComponent.lowercased()
            guard !name.contains("icon"), !name.contains("logo"), !name.contains("favicon") else { continue }

            var score = 0
            if name.contains("line") { score += 8 }
            if name.contains("art") || name.contains("hero") || name.contains("illustration") { score += 6 }
            if name.contains("character") || name.contains("figure") { score += 5 }
            if name.contains("bg") || name.contains("background") || name.contains("texture") || name.contains("pattern") { score += 4 }
            if name.contains("fill") { score -= 3 }
            if ext == "png" || ext == "webp" { score += 2 }
            score += min(5, (values.fileSize ?? 0) / 200_000)
            if score > (best?.1 ?? 0) {
                best = (url, score)
            }
        }
        return best?.0
    }
}

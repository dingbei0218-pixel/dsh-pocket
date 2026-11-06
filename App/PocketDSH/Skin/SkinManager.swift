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
    @Published var errorMessage: String?

    @Published var repositoryURL: String {
        didSet { defaults.set(repositoryURL, forKey: "dsh.skin.repo") }
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
            // token 很少的皮肤主要靠 patches.css 改样式；原生端用预览图保留氛围。
            if tokens.count < 8, let preview = skin.previewURL, FileManager.default.fileExists(atPath: preview.path) {
                backgroundURL = preview
                theme.hasBackgroundMedia = true
            } else {
                backgroundURL = skin.backgroundURL.flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
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
            errorMessage = error.localizedDescription
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
            errorMessage = error.localizedDescription
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

    private func encodedPath(_ path: String) -> String {
        path.split(separator: "/").map {
            String($0).addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
    }
}

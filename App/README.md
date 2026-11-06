# PocketDSH — iPhone / iPad App

SwiftUI 客户端，直接链接本地 Swift 包 `DSHKit`。单一 iOS target，iOS 17+，支持 iPhone 与 iPad。

## 构建

前置：macOS 14+、Xcode 16+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
cd App
xcodegen generate
open PocketDSH.xcodeproj
```

1. 选择 `PocketDSH` scheme；
2. Target → Signing & Capabilities → 选择你的 Team（bundle id 可改）；
3. 选择 iPhone 模拟器或真机，Run。

未安装 XcodeGen 时，也可以在 Xcode 里新建 iOS App target，把 `PocketDSH/` 全部源码拖入，
并在 Package Dependencies 中添加本地包 `..`（产品 `DSHKit`）。

## 安装与分发

- 真机调试：Xcode 选择设备，Run；首次需在 iPhone 上信任开发者证书。
- 导出 ipa：

```bash
xcodebuild -project PocketDSH.xcodeproj \
  -scheme PocketDSH \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/PocketDSH.xcarchive archive
```

然后用 Xcode Organizer 导出 Ad Hoc / Development ipa。签名与设备 UDID 需自行配置。

也可以直接跑：

```bash
scripts/build-app.sh
```

## 首次使用

1. 点右上角齿轮 → **Settings**；
2. 填入 DeepSeek API Key（写入 Keychain）；
3. 选择模型（默认 `deepseek-chat`，可改 `deepseek-reasoner` 或自定义 base URL）；
4. 选择权限预设。

## 工作区与文件

```
<App 容器>/Documents/DSH/Workspace                     # Agent 工作区
<App 容器>/Documents/DSH/sessions/<id>/header.json     # 会话元数据
<App 容器>/Documents/DSH/sessions/<id>/events.jsonl    # 事件日志
```

`UIFileSharingEnabled` + `LSSupportsOpeningDocumentsInPlace` 已开启：
系统「文件」App →「我的 iPhone / iPad」→「DSH Pocket」即可查看/导入代码文件。
所有文件工具都被 `SandboxGuard` 限制在 `Workspace` 内。

## 界面

- 会话列表（新建、删除、切换），iPhone 上为折叠式导航
- 聊天流：用户气泡、助手 Markdown（含表格/代码块）、推理折叠、工具卡（输入/输出/状态）、复制/导出
- 审批卡：危险工具逐次确认（Deny / Allow），从底部弹出
- 顶栏：模型、token、todo 进度、Goal、Settings、Stop、导出菜单
- 会话：搜索、置顶、重命名、删除；审批支持「总是允许」（仅当前 App 会话）
- 输入：语音转文字、从「文件」导入代码到工作区并自动插入 @ 引用
- 设置：API Key、模型、base URL、权限预设、联网开关、上下文窗口、自定义指令
- 皮肤中心：默认对齐 DSH Desktop 暗色主题；可从任意 `skins/<id>/skin.json` 结构的 Git 仓库同步、安装、切换（见 [docs/SKINS.md](../docs/SKINS.md)）

## 皮肤

默认主题使用 DSH Desktop 的官方暗色 token；皮肤中心兼容 DSH Skin Manifest v2：

1. 设置 → 外观 → 皮肤中心；
2. 默认源 `https://github.com/zhu1090093659/dsh-skins`，也可换任意 GitHub 仓库；
3. 同步 → 安装 → 立即生效，无需重启。

皮肤会落到 `Documents/DSH/Skins/<id>/`，可通过「文件」App 直接查看；`hooks.mjs` 与
`patches.css` 不会执行，视频背景降级为预览图。详见 [docs/SKINS.md](../docs/SKINS.md)。

## 平台限制

- iOS 禁止创建子进程，因此**没有 shell 工具**；`ShellTool` 在编译期被排除。
- 后台流式可能被系统挂起；事件逐条落盘，回到前台可继续。
- 未接入分享扩展、Widget、图片输入。

## 故障排查

| 现象 | 处理 |
|---|---|
| `no such module 'DSHKit'` | 确认 `App/project.yml` 中 package path 为 `..`，重新 `xcodegen generate` |
| 401 / invalid credential | Settings 里重新保存 Key；确认 base URL |
| 工具一直 pending | 审批卡被其他 sheet 遮挡；关闭 Settings 再试 |
| 构建报 deployment target | target 调到 iOS 17 以上 |
| 真机无法安装 | 检查 Team、Bundle ID、设备信任与 provisioning profile |

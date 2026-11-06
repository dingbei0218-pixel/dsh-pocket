# PocketDSH — iOS / iPadOS / macOS App

SwiftUI 客户端，直接链接本地 Swift 包 `DSHKit`。同一套源码编译出两个 target：

- `PocketDSH-iOS`：iPhone / iPad（iOS 17+）
- `PocketDSH-macOS`：Mac（macOS 14+）

## 构建

前置：macOS 14+、Xcode 16+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
cd App
xcodegen generate
open PocketDSH.xcodeproj
```

1. 选择 `PocketDSH-iOS` 或 `PocketDSH-macOS` scheme；
2. Target → Signing & Capabilities → 选择你的 Team（bundle id 可改）；
3. Run。

未安装 XcodeGen 时，也可以在 Xcode 里新建 App target，把 `PocketDSH/` 全部源码拖入，
并在 Package Dependencies 中添加本地包 `..`（产品 `DSHKit`）。

## 首次使用

1. 点左下角 **Settings**；
2. 填入 DeepSeek API Key（写入 Keychain）；
3. 选择模型（默认 `deepseek-chat`，可改 `deepseek-reasoner` 或自定义 base URL）；
4. 选择权限预设。

工作区固定在：

```
~/Library/Application Support/DSH/Workspace          # macOS
<App 容器>/Library/Application Support/DSH/Workspace  # iOS
```

会话存储在 `.../DSH/sessions/<id>/{header.json,events.jsonl}`。

## 平台差异

| | iOS | macOS |
|---|---|---|
| shell 工具 | 不注册（系统禁止子进程） | 注册，标记 dangerous，默认需审批 |
| 文件访问 | App 容器内 | 同一路径；关闭 App Sandbox 以允许 shell |
| 多窗口 | 单窗口 | 支持多窗口 / 隐藏标题栏 |
| Keychain | ✅ | ✅ |
| 后台流式 | 可能被挂起，事件已落盘 | 正常 |

macOS target 在 `project.yml` 中设置 `ENABLE_APP_SANDBOX: NO`，因为 App Sandbox 会禁止
`/bin/zsh` 子进程。若要上架 Mac App Store，需要移除 shell 工具并重新开启沙箱。

## 界面

- 左侧会话列表（新建、删除、切换）
- 聊天流：用户气泡、助手 Markdown、推理折叠、工具卡（输入/输出/状态）
- 审批浮层：危险工具逐次确认（Deny / Allow）
- 顶栏：模型、token、todo 进度、Stop
- 设置：API Key、模型、base URL、权限预设、工具开关、上下文窗口、自定义指令

## 故障排查

| 现象 | 处理 |
|---|---|
| `no such module 'DSHKit'` | 确认 `App/project.yml` 中 package path 为 `..`，重新 `xcodegen generate` |
| 401 / invalid credential | Settings 里重新保存 Key；确认 base URL |
| 工具一直 pending | 审批浮层被其他 sheet 遮挡；关闭 Settings 再试 |
| macOS shell 无输出 | 设置里开启 Shell；确认未启用 App Sandbox |
| 构建报 deployment target | 把 target 调到 iOS 17 / macOS 14 以上 |

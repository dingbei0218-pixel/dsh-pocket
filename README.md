# DSH Pocket · iOS 版

> 把 [JopenChen/dsh-go](https://github.com/JopenChen/dsh-go) 的 DeepSeek Harness Agent 内核，用 Swift 6 重写为 **iPhone / iPad 原生 App**。
>
> 不是套壳、不是 WebView：事件溯源、Turn/Step 双循环、DeepSeek SSE、工具流水线、审批、Goal/Todo、JSONL 持久化全部在设备本地运行。

<p align="center">
  <b>DSHKit</b> · 纯 Swift 内核 &nbsp;|&nbsp; <b>PocketDSH</b> · iOS 17+ SwiftUI App
</p>

---

## 当前状态

| 部件 | 状态 | 验证 |
|---|---|---|
| `DSHKit` 核心包 | ✅ 完成 | `swift build` 通过（Swift 6.4.2） |
| 单元测试 | ✅ 40 个全通过 | `swift test`，0 failures |
| `PocketDSH` iOS App | ✅ 源码 + XcodeGen 工程 | 语法解析通过；需在 macOS + Xcode 16 上编译 |
| `.ipa` 安装包 | ⏳ 需在你的 Mac 上签名构建 | 见 [App/README.md](App/README.md) |

> 本仓库的核心包在 Windows 上完成编译与测试；SwiftUI 只能在 Apple 平台编译，
> 因此 App 层交付**完整 iOS 源码 + XcodeGen 工程描述**，在 Mac 上一条命令生成 `.xcodeproj`。

## 界面预览

![PocketDSH iPhone UI](docs/preview-ios.png)

> HTML 设计稿（`docs/preview-ios.html`），用于在没有 Mac 的环境里预览 iPhone 布局；
> 真机界面以 `App/PocketDSH/` 源码为准。

---

## 这是什么

`dsh-go` 是一份纯 Go、进程内的 DeepSeek Harness 参考实现，逐词对译了官方 DSH 的能力接缝：事件溯源、Turn/Step、Goal、工具治理、错误分类。

本项目做三件事：

1. **逆向**：梳理 56 种事件、状态机、JSONL 布局、SSE 协议、工具流水线，写成 [逆向报告](docs/REVERSE_ENGINEERING.md) 与 [事件表](docs/EVENT_SCHEMA.md)；
2. **重写**：用 Swift actor 实现 `DSHKit`，事件 JSON 与 dsh-go 同构，可读写同一份 `sessions/<id>/{header.json,events.jsonl}`；
3. **做成 iOS App**：补上参考实现省略的工具 schema、tool_calls 聚合、tool 结果回填，并适配 iOS 沙箱、Files、Keychain、后台挂起。

### 与 dsh-go 的关系

| | dsh-go | DSH Pocket iOS |
|---|---|---|
| 定位 | Go 参考实现 / 学习素材 | iPhone / iPad 可运行产品 |
| 事件词汇表 | 56 种 | 56 种，字符串与字段一致 |
| 会话文件 | `header.json` + `events.jsonl` | 同布局、同 JSON 形状 |
| 工具调用 | 四级流水线 | 同语义 + 审批闸门 + 输出截断/spill |
| 模型流 | DeepSeek SSE | 同协议，修复 tool_calls 增量聚合 |
| 平台能力 | shell / 子进程 / jobs | iOS 不提供 shell（系统禁止） |

详见 [兼容性与差异](docs/PARITY.md)。

---

## 目录

```
apple-dsh/
├── Package.swift                 # SwiftPM：DSHKit（+ 开发用 dsh CLI、测试）
├── Sources/
│   ├── DSHKit/                   # 纯 Swift 内核（无 SwiftUI 依赖）
│   │   ├── Session/              # 事件、日志、不变量、fold、JSONL 持久化
│   │   ├── LLM/                  # DeepSeek SSE、错误分类、usage
│   │   ├── Tools/                # 工具协议、沙箱、内置工具
│   │   ├── Agent/                # Turn/Step 循环、审批、上下文组装
│   │   ├── Prompt/               # system prompt
│   │   └── Config/               # 配置与凭证接缝
│   └── dsh/                      # 开发期验证 CLI（不随 iOS App 发布）
├── App/
│   ├── project.yml               # XcodeGen：单一 iOS target
│   └── PocketDSH/                # iOS SwiftUI 源码
├── Tests/DSHKitTests/            # 40 个 XCTest
├── docs/                         # 逆向、架构、兼容性、事件表、测试
└── scripts/                      # mock DeepSeek 服务端与验证脚本
```

---

## 快速开始（iOS）

前置：macOS 14+、Xcode 16+、[XcodeGen](https://github.com/yonaskolb/XcodeGen)。

```bash
brew install xcodegen
cd App
xcodegen generate
open PocketDSH.xcodeproj
```

1. 选择 `PocketDSH` scheme；
2. Target → Signing & Capabilities → 选择你的 Team（bundle id 可改）；
3. 选 iPhone 模拟器或真机，Run。

首次启动：

1. 点右上角齿轮 → Settings；
2. 填入 DeepSeek API Key（存 Keychain）；
3. 选择模型（默认 `deepseek-chat`，可改 `deepseek-reasoner` 或自定义 base URL）；
4. 选择权限预设（safe / review / default / danger）。

### 工作区与文件

```
<App 容器>/Documents/DSH/Workspace     ← 文件读写都限制在这里
<App 容器>/Documents/DSH/sessions/<id>/{header.json,events.jsonl}
```

`UIFileSharingEnabled` 已开启：在系统「文件」App →「我的 iPhone / iPad」→「DSH Pocket」中
可以直接查看工作区、导入代码文件。Agent 的 `read_file / write_file / edit_file / glob / grep`
都被 `SandboxGuard` 限制在这个目录内。

### 安装到真机 / 导出 ipa

Xcode 选择你的开发团队与真机，Run 即可安装。需要分发时：

```bash
xcodebuild -project App/PocketDSH.xcodeproj \
  -scheme PocketDSH \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/PocketDSH.xcarchive archive
```

再用 Xcode Organizer 导出 Ad Hoc / Development ipa。签名、证书与设备 UDID 需自行配置。

---

## 开发期验证（可选，不属于 iOS App）

```bash
cd apple-dsh
swift test
```

无 API Key 的端到端验证（mock DeepSeek SSE → 工具调用 → 结果回填）：

```bash
node scripts/mock-deepseek.mjs 18081 &
DEEPSEEK_API_KEY=test swift run dsh run "read hello.txt" \
  -C /tmp/dsh-smoke --base-url http://127.0.0.1:18081 --preset danger \
  --root /tmp/dsh-sessions
```

完整记录见 [docs/TESTING.md](docs/TESTING.md)。`dsh` 只是开发验证工具，不参与 iOS App 构建。

---

## iOS 设计要点

- **没有 shell**：iOS 禁止 `fork/exec`，`ShellTool` 在编译期被 `#if os(macOS)` 排除；联网用 `web_fetch`，文件用沙箱工具。
- **工作区可审计**：所有路径经过标准化 + 符号链接解析 + 前缀校验，`../` 逃逸会被拒绝。
- **审批是一等能力**：写盘、联网等危险工具按预设决定 allow / ask / deny；无 UI 处理器时 fail-closed。
- **Keychain**：API Key 不落 UserDefaults；App 卸载即清除。
- **后台挂起**：事件逐条落盘；恢复时 `repairOrphanTurn` 自动补齐未闭合的 turn/step/tool。
- **纯本地**：除 DeepSeek API 与你显式让模型抓取的网页外，不上传任何数据。

---

## 已知边界

- 未实现 MCP、子代理、Workflow、Jobs、Skills 六层 Provider、SQLite 后端、OTel；矩阵见 [PARITY.md](docs/PARITY.md)。
- 自动 compaction 只做请求级裁剪；`surface/replace` 事件与 fold 已实现但未自动触发。
- 未做图片输入、语音输入、分享扩展、Widget。
- 长任务切后台可能被系统挂起，回前台继续；事件不丢。

---

## 许可证与致谢

- 本移植遵循 MIT。原项目：`dsh-go` © 2026 JopenChen，MIT License。
- 语义参考：DeepSeek Harness（官方 TS 实现）。
- 与 DeepSeek 官方无隶属关系。

见 [LICENSE](LICENSE) 与 [NOTICE](NOTICE)。

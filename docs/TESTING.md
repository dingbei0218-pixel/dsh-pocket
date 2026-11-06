# 测试与验证记录

## 1. 单元测试

```bash
swift test
```

当前结果（Swift 6.4.2，Windows x64 宿主）：

```
Executed 40 tests, with 0 failures (0 unexpected) in 0.260 seconds
```

覆盖：

| 文件 | 用例数 | 覆盖点 |
|---|---:|---|
| `EventRoundTripTests` | 7 | 信封形状、56 类型编码、未知类型、纳秒时间、header、todo |
| `SessionLogTests` | 7 | turn/step 生命周期、乱序拒绝、tool 配对、崩溃修复、surface replace |
| `FoldTests` | 7 | 消息/工具投影、goal revision、todo、usage、标题、审批、preset |
| `SessionStoreTests` | 4 | 创建/追加/加载/列表、fork + end-seed、半截行容忍、缺失会话 |
| `AgentTests` | 6 | 工具往返 + 第二轮 tool 消息、空响应失败、未知工具 |
| `UtilitiesTests` | 9 | JSON、glob、错误分类、HTML、SSRF、沙箱、读写工具 |

## 2. 端到端（无真实 API Key）

`scripts/mock-deepseek.mjs` 模拟 DeepSeek：

1. 第一次请求 → 返回 `read_file` 的流式 tool_call；
2. 客户端执行工具后第二次请求（含 `role=tool`）→ 返回文本流 + usage。

```bash
node scripts/mock-deepseek.mjs 18081 &
mkdir -p /tmp/dsh-smoke && echo "hello from mock" > /tmp/dsh-smoke/hello.txt
export DEEPSEEK_API_KEY=test
swift run dsh run "read hello.txt and tell me what it says" \
  -C /tmp/dsh-smoke --base-url http://127.0.0.1:18081 \
  --preset danger --root /tmp/dsh-sessions
```

实测输出：

```
⚙ read_file {"path":"hello.txt"}
  ↳      1	hello from mock


The file contains: hello from mock


[117 tokens · sess_dc03645]
```

服务端日志确认两次请求、第二次 `toolResult=true`：

```
[mock] request model=deepseek-chat messages=1 tools=8 toolResult=false
[mock] request model=deepseek-chat messages=3 tools=8 toolResult=true
```

落盘格式：

```json
{"data":{"turn":0},"seq":1,"time":"2026-11-06T14:38:41.696Z","type":"turn/start"}
{"data":{"content":"read hello.txt and tell me what it says","source":"run"},"seq":2,...}
{"data":{"content":"","toolCallIds":["call_mock_1"]},"seq":8,...}
```

`dsh sessions` / `dsh replay <id>` 可从同一份 JSONL 重建。

## 3. App 层验证边界

- SwiftUI 只能在 Apple 平台编译；本机（Windows）对 8 个 App 源文件执行了 `swiftc -parse`，全部通过。
- `DSHKit` 与 CLI 已完成真实编译与运行验证；App 使用同一套公开 API。
- 在 macOS 上执行：

```bash
cd App && xcodegen generate && xcodebuild -scheme PocketDSH -destination 'generic/platform=iOS Simulator' build
```

## 4. Windows 开发环境（可选，供复现）

本仓库的核心验证在 Windows 上完成，工具链为 Swift 6.4.2（NoAsserts）。官方 Burn 安装器在
本机受临时目录限制无法启动，因此从安装包 payload 中提取 MSI 逐个安装，并做了以下宿主侧配置：

- MSVC 14.44 + Windows SDK 10.0.26100；
- 通过 junction 提供无空格 include 路径，向 Swift 传递：
  `-Xcc -D_CRT_HAS_C11=0 -Xcc -D_WINSOCKAPI_`；
- `swift build` / `swift test` 使用同一组 `-Xcc` 参数。

这些是宿主特例，**macOS 上不需要**；正常 `swift test` 即可。

## 5. 回归建议

- 修改事件字段时，先跑 `EventRoundTripTests`；
- 修改不变量/修复逻辑时，跑 `SessionLogTests`；
- 修改 Agent 请求组装时，跑 `AgentTests` 并检查第二轮 `messages` 的 role 序列；
- 修改 SSE 解析时，跑一次 mock 端到端。



# 兼容性与能力矩阵

图例：✅ 完成 · 🟡 部分/有意简化 · ⛔ 未实现 · ➖ 平台不适用

## 1. 会话与事件

| 能力 | dsh-go | DSHKit | 说明 |
|---|---|---|---|
| 56 种事件词汇表 | ✅ | ✅ | 字符串、字段名一致；未知类型保留 |
| 事件信封 `{seq,time,type,data}` | ✅ | ✅ | JSON 形状一致 |
| `header.json` / `events.jsonl` 布局 | ✅ | ✅ | 可直接共享目录 |
| append-only + seq 连续 | ✅ | ✅ | actor 串行 |
| turn/step/tool 不变量 | ✅ | ✅ | 8 条中的时序子集 |
| 崩溃修复 | ✅ | ✅ | tool → step → turn |
| fold / projection | ✅ | ✅ | 另产出 ChatItem |
| surface/replace 读时替换 | ✅ | ✅ | 自动压缩未接线 |
| 增量投影（H04） | ✅ | ⛔ | 当前 O(n) fold；接口已隔离，可替换 |
| SQLite 后端 | ✅ | ⛔ | 仅 JSONL |

## 2. Agent

| 能力 | dsh-go | DSHKit | 说明 |
|---|---|---|---|
| Turn/Step 双循环 | ✅ | ✅ | |
| 工具 schema 注入 | ⛔（返回 nil） | ✅ | 修复 |
| assistant tool_calls 回填 | ⛔ | ✅ | 修复 |
| tool 结果回填 | ⛔ | ✅ | 修复 |
| 流式 tool_calls 聚合 | ⛔ | ✅ | 按 index 聚合 |
| 取消（user/parent/...） | ✅ | 🟡 | `Task.cancel` + aborted；未分 5 类原因 |
| 请求重试（不重复输出） | 🟡 | ✅ | 仅无输出时重试 |
| Goal 四态 + 续轮 | ✅ | 🟡 | 投影/UI 完成；自动续轮默认关闭 |
| Todo 整体替换 | ✅ | ✅ | |
| 自动标题 | ⛔ | ✅ | 首轮写 `session/title` |
| 上下文压缩 | 🟡 | 🟡 | 请求级裁剪；surface replace 可用 |
| 子代理 / 并行 | ✅ | ⛔ | |
| Workflow 引擎 | ✅ | ⛔ | |

## 3. LLM

| 能力 | dsh-go | DSHKit | 说明 |
|---|---|---|---|
| DeepSeek SSE | ✅ | ✅ | |
| reasoning_content | ✅ | ✅ | 独立事件 + UI 折叠 |
| usage / cache token | ✅ | ✅ | `llm/done` 累加 |
| 稳定错误分类 | ✅ | ✅ | 增加 invalid-request/network/cancelled |
| 连接池调优 | ✅ | ➖ | URLSession 自管 |
| 多 Provider | ⛔ | 🟡 | 任意 OpenAI-compatible base URL |
| 图片输入 | ✅（类型） | ⛔ | |

## 4. 工具

| 工具 | dsh-go | DSHKit | 说明 |
|---|---|---|---|
| read_file / write_file / edit_file / list_dir | 示例 | ✅ | 带工作区沙箱 |
| glob / grep | ⛔ | ✅ | 纯 Swift 实现 |
| shell | ✅ | ➖ | iOS 禁止子进程，编译期移除 |
| web_fetch | ⛔ | ✅ | SSRF 私网拦截、HTML 转文本 |
| todo_write | ✅ | ✅ | |
| goal_* 6 个工具 | ✅ | ⛔ | UI 管理 goal；模型工具后续补 |
| MCP 客户端桥 | ✅ | ⛔ | |
| spill / 截断 | ✅ | ✅ | 60k 字符后写 spill 文件 |
| 四级流水线 pre/post/result 中间件 | ✅ | 🟡 | 审批 + 截断等效；无通用中间件链 |

## 5. 安全

| 能力 | dsh-go | DSHKit | 说明 |
|---|---|---|---|
| read-only / workspace-write / full | ✅ | ✅ | |
| 路径逃逸防护 | ✅ | ✅ | 标准化 + 符号链接 + 前缀 |
| 审批三态 allow/deny/ask | ✅ | ✅ | fail-closed |
| Keychain | ➖ | ✅ | App 层 |
| 私网 SSRF 拦截 | ⛔ | ✅ | 基础实现 |

## 6. Apple 平台

| 能力 | 状态 |
|---|---|
| iOS 17 / iPadOS 17 | ✅ 源码 |
| 多窗口 / NavigationSplitView | ✅ |
| Keychain | ✅ |
| 深色主题 / 动态布局 | ✅ |
| 后台继续流式 | 🟡 系统可能挂起；事件已落盘 |
| App Store 沙箱 | ✅ iOS 容器沙箱 + 工作区二级沙箱 |

## 7. 与官方 DSH 的边界

本项目对齐的是 **dsh-go 的 Go 语义**，不是官方 TS 仓库的每一个内部协议：

- 事件词汇表与官方 `packages/core/session` 同名，但官方新增字段/事件可能未覆盖；
- 官方 `request/header` 的代际策略、Provider 路由、skills 注入顺序未完全复刻；
- 会话文件可被 dsh-go 读取（格式版本 1），但**不保证**官方 DSH 直接加载（未在官方运行时验证）。



# 逆向报告：从 dsh-go 到 Swift 原生内核

> 对象：[`JopenChen/dsh-go`](https://github.com/JopenChen/dsh-go)（MIT）
> 方法：通读 `pkg/` 全部 Go 源码与 `tests/`，抽取事件契约、状态机、协议细节，再用 Swift actor 重写。
> 结论先行：**dsh-go 的「事件词汇表 + JSONL 布局 + Turn/Step 状态机 + 工具流水线」可以直接平移到 Apple 平台；但它的 Agent 循环有几处演示级省略，直接照抄会在真实模型上跑不通。**

---

## 1. 代码规模与分层

| 指标 | 数值 |
|---|---|
| Go 文件 | 283 |
| Go 源码 | ≈ 1.30 MB |
| `pkg/` 能力包 | 48 个目录 |
| 事件类型 | 56 种（`session.AllEventTypes`） |
| 测试 | 129 个 `_test.go` |

核心分层（与官方 DSH 的 Capability Seam 对应）：

```
Session (event sourcing) ──► fold / projection ──► prompt assemble ──► Agent Turn/Step
                                                                          │
                        Tool waterfall (pre → execute → post → result) ◄──┘
```

每个能力都是「服务定义 + Provider」：换 Provider 即换行为。这一点被 Swift 端原样保留
（`LLMProvider`、`APIKeyStore`、`ApprovalHandler`、`ToolRegistry`）。

---

## 2. 事件溯源会话：最容易原样移植的部分

### 2.1 存储布局

```
<sessions-root>/<session-id>/header.json
<sessions-root>/<session-id>/events.jsonl      # 一行一个 SessionEvent
```

`header.json` 字段（camelCase，`omitempty`）：

```json
{
  "version": 1,
  "id": "sess_...",
  "createdAt": "2026-11-06T13:49:19.123Z",
  "cwd": "/path/to/workspace",
  "parentSession": "sess_parent",
  "seedLength": 42,
  "origin": "created|fork|resume",
  "delegationDepth": 0,
  "agentPreset": "default"
}
```

### 2.2 事件信封

```json
{
  "seq": 8,
  "time": "2026-11-06T14:38:41.718Z",
  "type": "assistant/message",
  "data": { "content": "", "toolCallIds": ["call_mock_1"] },
  "surfaceOp": { "op": "replace", "start": 2, "end": 7, "data": { ... } },
  "sourceEventSeqs": [2, 3, 4]
}
```

- `seq` 从 1 连续递增；`time` 单调不减（写入时取 `max(now, lastTime)`）。
- `type` 决定 `data` 的具体结构；`surfaceOp` 只用于 compaction；`sourceEventSeqs` 记录派生来源。
- 未知 `type` 在 Go 端 fail-closed（`CorruptEventError`）。Swift 端选择**保留并透传**，以便向前兼容更高格式版本；`EventType.isKnown` 可供调用方收紧。

### 2.3 八条 day-1 不变量（Swift 已实现其中时序部分）

`append` 时逐条校验，失败即回滚 `seq`：

1. `turn/start` 不能在 turn 已打开时出现；`turn` 必须等于 `nextTurn`（从 0 开始）。
2. `turn/end` 必须有打开的 turn，且不能有打开的 step；`turn` 必须匹配。
3. `turn/stopping` 必须有打开的 turn。
4. `step/start` 必须在打开的 turn 内，且不能重复打开；`step` 必须等于 `nextStep`（每 turn 从 1 重置）。
5. `step/end` 必须匹配当前打开的 step。
6. `tool/call` 必须在打开的 step 内，`callId` 不得重复。
7. `tool/result` / `tool/error` 必须对应一个已登记且未配对的 `callId`。
8. 日志结束时不允许有未闭合的 turn / step / tool call（`Check()` 负责整条日志校验）。

> Swift 端把这套状态机放在 `SessionLog` actor 里，UI 与 Agent 都无法绕过。

### 2.4 fold 与 surface replace

`fold` 是纯函数：`[SessionEvent] -> SessionProjection`。

- `EffectiveEvents` 先应用 `surfaceOp.replace`：把 `[start,end]` 区间从读取视图中隐藏，替换事件自身保留。
- 源事件永远不修改；compaction 只追加一条 `surface/replace`。
- 投影包括：messages、goal（latest revision wins）、todo（last write wins）、title、usage、approval、sandbox/preset、agent status。

Swift 的 `Fold.project` 额外产出 `[ChatItem]`（已把 chunk 聚合、tool call/result 配对），供 SwiftUI 直接渲染。

---

## 3. Turn / Step 双循环

dsh-go 的 `agent.runTurn` 结构：

```
turn/start
user/message
loop:
  step/start
  agent/request
  llm/stream → assistant/chunk* → (assistant/reasoning*)
  if tool_calls:
     tool/call → pipeline → tool/result
  step/end
  if no tool calls: break
turn/stopping
turn/end(completed)
```

错误路径：`agent/error` + `turn/end(interrupted)`；取消原因分 5 类（user/parent/hook/disposed/legacy）。

Swift 端保留同一事件序列，并做了三处必要修正。

### 3.1 参考实现的四个「演示级省略」

| 位置 | 问题 | 后果 |
|---|---|---|
| `pkg/agent/agent.go:451` `toolSchemas()` | 永远返回 `nil` | 模型根本看不到工具，永远不会发起工具调用 |
| `pkg/agent/agent.go:365-373` | 历史只映射成 user/assistant 纯文本 | 即使有工具调用，assistant `tool_calls` 与 `tool` 结果也不会回填，第二轮请求是残缺的 |
| `pkg/llm/provider_deepseek/deepseek.go:503-509` | 每个 `tool_calls` 分片被当成完整调用 | DeepSeek 的 function arguments 是增量字符串，会产生 N 个残缺工具调用 |
| `pkg/agent/agent.go:446` | `modelName()` 硬编码 `deepseek-chat` | 无法切模型 |

Swift 端对应修复：

- `ToolRegistry.schemas` 注入 `ChatRequest.tools`；
- `Agent.buildMessages` 预扫描 `tool/call`，把 `assistant/message.toolCallIds` 还原为 `LLMToolCall(id,name,arguments)`，并追加 `role=tool` 结果消息；
- `DeepSeekProvider` 只发 `(index,id,name,argumentsFragment)`，由 `Agent` 按 `index` 聚合后再执行；
- `AgentConfig.model` 可配置，支持 `deepseek-reasoner` 与 OpenAI-compatible base URL。

### 3.2 参考实现里值得保留的设计

- **单 Turn 串行**：turn 队列容量 2（1 运行 + 1 排队），保证事件顺序简单可推理。
- **取消原因分类**：Swift 用 `Task.cancel()` + `LLMFailure.cancelled`，并把 `turn/end(aborted)` 落盘。
- **重试只在「尚未产生输出」时进行**：否则会重复文本。Swift 端显式检查 `receivedAnything`。
- **Goal RoundDriver 监听 turn-stopping**：目标 active 时自动续轮，直到 `maxRounds`。Swift 端保留了 goal 投影与手动续轮，自动轮询默认不开启（避免 App 里无限循环）。

---

## 4. DeepSeek SSE 协议

请求：

```http
POST {baseURL}/chat/completions
Authorization: Bearer <key>
Accept: text/event-stream
Content-Type: application/json
```

```json
{
  "model": "deepseek-chat",
  "messages": [
    {"role":"system","content":"..."},
    {"role":"user","content":"..."},
    {"role":"assistant","content":"","tool_calls":[{"id":"call_1","type":"function","function":{"name":"read_file","arguments":"{\"path\":\"a.txt\"}"}}]},
    {"role":"tool","tool_call_id":"call_1","content":"..."}
  ],
  "tools": [{"type":"function","function":{"name":"read_file","description":"...","parameters":{...}}}],
  "stream": true,
  "stream_options": {"include_usage": true}
}
```

响应逐行 `data: {...}`：

- `choices[0].delta.content` → 文本增量
- `choices[0].delta.reasoning_content` → 推理增量
- `choices[0].delta.tool_calls[]` → `{index,id,function:{name,arguments}}` 增量
- 最后一条带 `usage.prompt_tokens/completion_tokens`（DeepSeek 还带 `prompt_cache_hit_tokens`）
- `data: [DONE]`

Swift 实现没有用 `URLSession.bytes`（corelibs 不保证可用），而是 `URLSessionDataDelegate` 逐行喂给 `AsyncThrowingStream`，并用 `onTermination` 取消底层 task；在 iOS/macOS/Windows 行为一致。

### 错误分类（与官方 `error.ts` 对齐）

稳定分类：`overload / rate-limit / response-refusal / context-overflow / quota / empty-response / invalid-credential / invalid-request / network / cancelled`。

- 401/403 → invalid-credential（不重试）
- 429 → rate-limit（退避重试）
- 5xx → overload（退避重试）
- body 含 context length/window → context-overflow（压缩后重试）
- 400/422 其他 → invalid-request
- 402 / insufficient balance → quota（不重试）

Swift 端按 status + body 结构信号分类，不把模型返回的 message 直接当路由依据。

---

## 5. 工具四级流水线

Go 的 `tools.Pipeline`：`pre → execute → post → result`，每级是 `waterfall.Chain[ExecContext]`。

- `pre` 可 deny / 改参 / 注入上下文；
- `execute` 最内层才真正调用工具，可把 signal 改为 cancel；
- `post` 可 block / 截断 / 附 meta；
- `result` 做最终包装。

Swift 端没有照搬泛型 chain，而是把「审批」放在 Agent 层、把「执行 + 截断 + spill」放在 `ToolRegistry`：

```
approval gate → tool.execute(context, input) → truncate / spill → tool/result
```

理由：Apple 端审批必须桥接到 UI（异步 continuation），放在 Agent 层能保证 `approval/asked`、`approval/decided` 与 `tool/call`、`tool/result` 的事件顺序；工具实现只关心业务。

沙箱三态与 dsh-go 一致：`read-only` / `workspace-write` / `danger-full-access`；`SandboxGuard.resolve` 做标准化 + 符号链接解析 + 前缀校验，防止 `../` 逃逸。

---

## 6. Apple 平台约束如何影响设计

| 约束 | 决策 |
|---|---|
| iOS 禁止 `fork/exec` | 不注册 `shell`；`#if os(macOS)` 编译期裁剪 |
| App 沙箱 | 工作区固定在 `Application Support/DSH/Workspace`；macOS 开发版关闭 App Sandbox 才能跑 shell |
| 后台挂起 | 事件逐条落盘；恢复时 `repairOrphanTurn` 自动补齐未闭合的 turn/step/tool |
| 无终端 UI | 审批用 SwiftUI overlay + `CheckedContinuation` 桥接；无处理器时 fail-closed |
| Keychain | `APIKeyStore` 协议 + `KeychainAPIKeyStore`；DSHKit 本身不依赖 Security |
| 状态恢复 | `SessionProjection` 为唯一读模型；UI 订阅 `SessionLog.updates()` 增量刷新 |

---

## 7. 兼容性结论

**可以互通的部分**

- 事件类型字符串、字段名、`seq/time/type/data` 信封；
- `header.json` 字段；
- 目录布局；
- `turn/step/tool` 不变量；
- `surface/replace` 的读时替换语义。

**有意不同**

- 时间精度：Swift `Date` 写 3 位小数（Go RFC3339Nano 可解析 1–9 位，读取时兼容）。
- Swift 保留未知事件类型（向前兼容），Go 默认 fail-closed。
- Swift 的 `assistant/chunk` 按 delta 追加（与 Go 一致），但 UI 聚合由投影完成。
- Swift 在工具结果回填、schema 注入、tool_calls 聚合上**优于**参考实现（见 3.1）。

**未对齐**

- 官方 TS 的 `request/header` 代际、compaction 触发策略、skills 六层 Provider、MCP 协商细节未逐一复刻；事件类型保留，语义子集见 [PARITY.md](PARITY.md)。

---

## 8. 逆向过程中确认的「坑」

1. `stepSeq` 是兼容旧字段，实际使用 `step`；Swift 只写 `step`。
2. `tool/result` 与 `tool/error` 共用配对状态；Swift 两者都关闭配对。
3. `surface/replace` 事件本身**不隐藏自己**，只隐藏 `[start,end]`，且要求 `end < 新 seq`。
4. 崩溃修复要按「tool → step → turn」顺序补齐，否则会触发不变量。
5. DeepSeek 的 `stream_options` 必须是对象 `{"include_usage":true}`，传布尔会 400。
6. `reasoning_content` 与 `content` 可能同帧到达；UI 要分开累积。
7. 工具参数是 JSON 字符串，流式期间可能被切成任意片段，必须按 index 聚合后一次性解析。

---

## 9. 参考坐标

- `pkg/session/session.go`（事件联合、SessionLog、不变量）
- `pkg/session/fold.go` / `incremental.go`（投影）
- `pkg/agent/agent.go`（Turn/Step）
- `pkg/llm/llm.go` / `provider_deepseek/deepseek.go`（协议与错误）
- `pkg/tools/pipeline.go`（四级流水线）
- `pkg/persistence/jsonl.go`（布局、崩溃修复）
- `pkg/goal/goal.go`（四态与续轮）
- `pkg/session/header.go`（格式版本）

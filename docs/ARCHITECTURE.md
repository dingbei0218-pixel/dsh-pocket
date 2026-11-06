# 架构

## 1. 总览

```
┌─────────────────────────────────────────────────────────────┐
│ SwiftUI (MainActor)                                         │
│  RootView / ChatScreen / Settings / ApprovalOverlay         │
│        ▲ SessionProjection          │ user actions         │
│        │                            ▼                      │
│  AppModel (@MainActor, ObservableObject)                    │
└───────────────┬─────────────────────────────────────────────┘
                │ async calls
┌───────────────▼─────────────────────────────────────────────┐
│ Agent (actor)                                               │
│  turn/step loop · approval gate · context assembly · title  │
│        │                 │                    │             │
│        ▼                 ▼                    ▼             │
│  SessionLog(actor)   LLMProvider          ToolRegistry      │
│  invariants+fold     DeepSeek SSE         File/Search/Web/  │
│        │                                  Shell/Todo        │
│        ▼                                                    │
│  SessionStore(actor) → header.json + events.jsonl           │
└─────────────────────────────────────────────────────────────┘
```

`DSHKit` 不依赖 SwiftUI / Security，可在 macOS、iOS、Windows（测试用）编译。
App 层只依赖 `DSHKit` 的公开 API。

## 2. 并发模型

| 类型 | 隔离 | 职责 |
|---|---|---|
| `SessionLog` | actor | 唯一写路径 `appendEvent`；维护 seq/时间/开放 turn/step；广播 `AsyncStream<SessionEvent>` |
| `SessionStore` | actor | 目录创建、header 原子写、JSONL 追加（每事件 `synchronize`，chunk 可关同步）、加载/修复、列表 |
| `Agent` | actor | Turn/Step、请求组装、流式聚合、工具执行、审批、标题 |
| `AppModel` | `@MainActor` | 会话列表、当前投影、发送/停止、设置与 Keychain |
| `ApprovalBroker` | `@MainActor` | 把 Agent 的 `@Sendable` 审批闭包桥接为 SwiftUI 弹层（`CheckedContinuation`） |

### 取消链

```
UI Stop → AppModel.stop → Agent.cancel → currentTask.cancel
        → provider.stream 的 onTermination → URLSession task.cancel
        → Agent catch CancellationError → turn/end(aborted)
```

`AsyncThrowingStream` 在终止时调用 URLSession 的 cancel，避免 SSE 读挂死。

## 3. 一次 Turn 的时序

```
Agent.run(text)
 ├─ turn/start(turn=n)
 ├─ user/message(content, source=run)
 ├─ step/start(turn=n, step=1)
 │   ├─ agent/request, llm/request
 │   ├─ [首次] request/header, request/context
 │   ├─ provider.stream(...)
 │   │    ├─ assistant/chunk*      (text)
 │   │    ├─ assistant/reasoning*  (reasoning_content)
 │   │    └─ 聚合 tool_calls(index)
 │   ├─ assistant/message(content, toolCallIds)
 │   ├─ llm/done(usage)
 │   ├─ for each call:
 │   │    ├─ [需要时] approval/asked → UI → approval/decided
 │   │    ├─ tool/call
 │   │    ├─ tool.execute → truncate/spill
 │   │    └─ tool/result
 │   └─ step/end
 ├─ 若本步有工具调用 → step+1，回到 step/start
 ├─ turn/stopping
 ├─ turn/end(completed)
 └─ session/title（首轮）
```

错误：`agent/error` + `turn/end(error)`；取消：`turn/end(aborted)`。

## 4. 上下文组装

`Agent.buildMessages` 从**有效事件**（应用 surface replace 后）构造：

- `user/message` → `role=user`
- `assistant/message` → `role=assistant`，并把 `toolCallIds` 映射为 `LLMToolCall`
- `tool/result`、`tool/error` → `role=tool`，带 `tool_call_id`
- 跳过空 assistant 消息

system prompt 由 `SystemPromptBuilder` 组装：身份、平台、工作区、沙箱模式、工具清单、工作规则、goal、用户自定义指令。

请求级裁剪：当字符估算超过 `contextWindow * 0.8 * 3.2` 时，从尾部保留完整消息，去除开头的孤立 `tool` 消息，并插入一条「历史被裁剪」提示。**不修改事件日志。**

## 5. 工具与审批

```swift
public struct Tool {
    name, description, parameters: JSONValue
    isDangerous, isReadOnly
    execute: @Sendable (ToolContext, JSONValue) async throws -> ToolResult
}
```

`ToolContext` 携带 `sessionID / workspace / callID / SandboxGuard / emit(EventData)`。
工具可以主动追加事件（例如 `todo_write`、`fs` 观察）。

审批策略：

| preset | sandbox | approval |
|---|---|---|
| safe | read-only | ask-dangerous |
| review | read-only | ask-dangerous-tool-edit |
| default | workspace-write | ask-dangerous |
| danger | danger-full-access | allow-all |

`ApprovalGate.requiresApproval` 只看工具声明与策略；无 handler 时 deny（fail-closed）。
`approval/asked` 与 `approval/decided` 双向落盘，方便审计与重放。

## 6. 持久化与恢复

- `createSession`：写 `header.json`（atomic）、创建空 `events.jsonl`。
- `append`：`FileHandle.seekToEnd` + `write` + `synchronize`（chunk 事件可 `sync:false`）。
- `load`：逐行解码；允许最后一行半截（崩溃残留），中间行损坏则 fail-closed。
- `restore(repair:true)`：按 `tool → step → turn` 补齐中断事件，再重放校验。
- `fork`：复制事件（重排 seq）+ 追加 `session/end-seed{parentSession}`，更新 `seedLength`。

## 7. Compaction

`SessionLog.appendSurfaceReplace(start:end:summary:)` 追加一条带 `surfaceOp.replace` 的事件；
`Fold.effectiveEvents` 在读时隐藏区间。当前版本提供 API 与投影能力，**自动摘要触发未接线**，
Agent 采用请求级裁剪作为默认策略（见第 4 节）。这避免在移动端因后台挂起产生半完成的摘要。

## 8. 测试策略

- 纯函数：JSON 编解码、fold、glob、HTML 清洗、错误分类。
- actor：不变量、修复、surface replace、持久化、fork。
- 集成：MockProvider 驱动完整 Turn/Step，断言事件序列与第二轮请求的 tool 消息。
- 端到端：本地 Node SSE mock + CLI，验证真实 URLSession/SSE/工具/落盘链路（见 TESTING.md）。

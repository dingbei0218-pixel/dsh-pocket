# 事件表（56 种）

所有事件外层统一为：

```json
{"seq":1,"time":"2026-11-06T14:38:41.696Z","type":"turn/start","data":{"turn":0}}
```

`data` 字段如下（`?` 表示省略即无）。"写入方"指当前 Swift 实现中谁会产出该事件。

## A. Turn / Step

| type | data | 写入方 | 说明 |
|---|---|---|---|
| `turn/start` | `turn` | Agent | turn 从 0 开始 |
| `turn/end` | `turn`,`reason` | Agent | `completed/finished/interrupted/aborted/blocked/error/max-tokens` |
| `turn/stopping` | `reason?` | Agent | 进入停止流程 |
| `step/start` | `turn`,`step`,`stepSeq?` | Agent | step 每 turn 从 1 开始 |
| `step/end` | `turn`,`step`,`stepSeq?` | Agent | |
| `agent/error` | `message`,`pkg?` | Agent | 内部错误 |
| `agent/pre-step` | `blocked?` | Agent | 预留 |
| `agent/request` | `provider`,`model?` | Agent | 请求快照 |
| `agent/status` | `status` | Agent | idle/running |
| `agent/inbox/spliced` | `target`,`start`,`removedCount?`,`inserted`,`outcome?` | — | 收件箱规范化 |

## B. 消息

| type | data | 写入方 | 说明 |
|---|---|---|---|
| `user/message` | `content`,`source?`,`refs?` | Agent | source = run/followup/reference/injected/goal |
| `assistant/message` | `content`,`toolCallIds?` | Agent | 最终助手消息（含工具调用 ID） |
| `assistant/chunk` | `text?` | Agent | 流式正文增量 |
| `assistant/reasoning` | `text?` | Agent | 推理增量 |
| `injection/context` | `name`,`content`,`hash?` | — | 动态上下文 |
| `session/title` | `title` | Agent | 首轮自动标题 |

## C. 工具

| type | data | 写入方 | 说明 |
|---|---|---|---|
| `tool/call` | `callId`,`tool`,`input?` | Agent | input 为 JSON 对象 |
| `tool/result` | `callId`,`isError?`,`output?`,`truncated?`,`spillPath?` | Agent | 与 call 配对 |
| `tool/error` | `callId`,`error` | Agent | 与 result 共用配对状态 |
| `tool/observed` | `callId`,`kind` | 工具 | 例如 `fs/write` |
| `tool/presentation` | `callId`,`card` | — | 展示卡片 |

## D. 规划

| type | data | 写入方 | 说明 |
|---|---|---|---|
| `plan/mode` | `mode` | — | `on` / `off` |
| `plan/approval` | `approved` | — | |
| `goal/change` | `goalId`,`phase`,`description?`,`maxRounds?`,`revision`,`blockedReason?` | App/Agent | latest revision wins |
| `goal/round` | `round` | — | 续轮计数 |
| `todo/write` | `items?`,`entries?` | `todo_write` | `entries` 为三态对象数组 |
| `session/end-seed` | `parentSession?` | Store.fork | resume/fork 的种子边界 |
| `project/plan-update` | `content?` | — | |

## E. 请求与审批

| type | data | 写入方 | 说明 |
|---|---|---|---|
| `request/header` | `configEpoch`,`systemHash?`,`toolCount?` | Agent | 首轮 |
| `request/context` | `provider`,`model`,`contextWindow?`,`reason?` | Agent | reason = initial/resume/change/series |
| `approval/asked` | `requestId`,`tool?`,`summary?` | Agent | 等待 UI |
| `approval/decided` | `requestId`,`allowed` | Agent | |
| `permission/preset-change` | `preset` | App/CLI | safe/review/default/danger |
| `agent/preset-change` | `preset` | — | |
| `command/run` | `command`,`args?` | — | slash 命令 |
| `command/done` | `command` | — | |

## F. 文件系统

| type | data | 说明 |
|---|---|---|
| `fs/write-intent` | `path`,`version?`,`observed?` | 写前意图 |
| `fs/edit-intent` | `path`,`version?` | |
| `fs/observed` | `path` | 先读后写政策 |
| `fs/version-bump` | `path`,`version` | |
| `fs/read` | `path` | |
| `fs/dir-list` | `path` | |

## G. 技能

| type | data | 说明 |
|---|---|---|
| `skills/change` | `added?`,`removed?`,`changed?` | |
| `skills/catalog` | `catalog`,`hash` | |
| `skill/inject` | `skillName`,`content?` | 技能内容注入 |

## H. LLM

| type | data | 写入方 | 说明 |
|---|---|---|---|
| `llm/request` | `provider`,`model` | Agent | |
| `llm/stream` | `text?` | — | 与 assistant/chunk 并行存在 |
| `llm/retry` | `attempt`,`backoffMs`,`error` | Agent | 仅无输出时 |
| `llm/error` | `kind`,`error` | Agent | 稳定分类 |
| `llm/done` | `promptTokens`,`completionTokens` | Agent | usage 累加 |

## I. 表面替换与杂项

| type | data | 写入方 | 说明 |
|---|---|---|---|
| `surface/replace` | `start`,`end`,`data?` | SessionLog | compaction；事件自身带 `surfaceOp` |
| `attachment/added` | `attachmentId`,`name?` | — | |
| `session/projection-updated` | `projectionId`,`hash?` | — | |
| `workspace/change` | `workspaceId`,`root?` | — | |
| `user/question` | `question`,`answer?` | — | |
| `sandbox/mode` | `mode`,`source?` | App/Agent | 最后一条生效 |

---

### 读取约定

- `turn` 无符号整数，从 0 开始；`step` 从 1 开始。
- `callId`、`requestId`、`goalId` 为字符串。
- `input` 是 JSON 对象；`assistant/message.toolCallIds` 与 `tool/call.callId` 对应。
- 所有 `time` 为 RFC3339 UTC（Swift 写 3 位小数）。
- 未知 `type` 会被 Swift 保留，不参与 fold；需要严格模式时检查 `EventType.isKnown`。

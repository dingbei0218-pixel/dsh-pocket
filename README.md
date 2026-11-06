# DSH Pocket · iOS

> A native iPhone / iPad app that brings the [dsh-go](https://github.com/JopenChen/dsh-go) DeepSeek Harness agent core to Apple platforms in Swift 6.
>
> Not a wrapper, not a WebView: event sourcing, the Turn/Step loop, DeepSeek SSE, tool pipeline, approvals, Goal/Todo and JSONL persistence all run on-device.

<p align="center">
  <b>DSHKit</b> · pure Swift core &nbsp;|&nbsp; <b>PocketDSH</b> · iOS 17+ SwiftUI app
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> · English
</p>

---

## Status

| Component | State | Verification |
|---|---|---|
| `DSHKit` core | ✅ Done | `swift build` passes (Swift 6.4.2) |
| Unit tests | ✅ 40 / 40 | `swift test`, 0 failures |
| `PocketDSH` iOS app | ✅ Builds and runs | Xcode 27.2 / iPhone 18 Pro · iOS 27.2 |
| UI / skin system | ✅ DSH Desktop default + v2 skins | 65 repo skins synced, 18 local skins parsed |
| Signed `.ipa` | ⏳ Requires a developer account | See [App/README.md](App/README.md) |

> The core tests pass on macOS, and the app has been built and launched in the iPhone 18 Pro simulator (iOS 27.2) with Xcode 27.2.

## Screenshots

![PocketDSH iPhone UI](docs/preview-ios.png)

> Captured from the simulator (iPhone 18 Pro / iOS 27.2).

<p>
  <img src="docs/preview-skin-center.png" width="31%" alt="Skin Center" />
  <img src="docs/preview-skin.png" width="31%" alt="Applied skin" />
</p>

### UI and skins

The default look mirrors the **DSH Desktop dark theme**: the same `--dsw-alias-*` tokens and the same sidebar / composer hierarchy.
The Skin Center supports DSH Skin Manifest v2 and can sync `skins/<id>/skin.json` from a Git repository:

- Default source: `https://github.com/zhu1090093659/dsh-skins`
- Settings → Appearance → Skin Center → Sync → Install → applies immediately
- You can also drop a skin folder into `DSH/Skins/` via the Files app
- `patches.css` and `hooks.mjs` are never executed; video backgrounds fall back to the preview image

See [docs/SKINS.md](docs/SKINS.md) for the format.

---

## What this is

`dsh-go` is a pure-Go, in-process reference implementation of the DeepSeek Harness agent: event sourcing, Turn/Step, Goal, tool governance and stable error classification.

This project does three things:

1. **Reverse-engineer** — maps 56 event types, the state machines, the JSONL layout, the SSE protocol and the tool pipeline into [a reverse-engineering report](docs/REVERSE_ENGINEERING.md) and [an event schema](docs/EVENT_SCHEMA.md).
2. **Rewrite** — implements `DSHKit` with Swift actors. Its event JSON is compatible with dsh-go and can read/write the same `sessions/<id>/{header.json,events.jsonl}` layout.
3. **Ship an iOS app** — fills in the pieces the reference implementation leaves out (tool schemas, tool-call aggregation, tool-result replay) and adapts them to the iOS sandbox, Files, Keychain and background suspension.

### How it relates to dsh-go

| | dsh-go | DSH Pocket iOS |
|---|---|---|
| Purpose | Go reference / learning material | A runnable iPhone / iPad product |
| Event vocabulary | 56 types | 56 types, same strings and fields |
| Session files | `header.json` + `events.jsonl` | Same layout and JSON shape |
| Tool execution | Four-stage pipeline | Same semantics + approval gate + truncation/spill |
| Model stream | DeepSeek SSE | Same protocol, with fixed incremental tool-call aggregation |
| Platform tools | shell / subprocess / jobs | No shell on iOS (the OS forbids it) |

See [parity and differences](docs/PARITY.md).

---

## Layout

```
apple-dsh/
├── Package.swift                 # SwiftPM: DSHKit (+ dev CLI and tests)
├── Sources/
│   ├── DSHKit/                   # Pure Swift core (no SwiftUI)
│   │   ├── Session/              # Events, log, invariants, fold, JSONL store
│   │   ├── LLM/                  # DeepSeek SSE, error taxonomy, usage
│   │   ├── Tools/                # Tool protocol, sandbox, built-in tools
│   │   ├── Agent/                # Turn/Step loop, approvals, context assembly
│   │   ├── Prompt/               # System prompt
│   │   └── Config/               # Config and credential seams
│   └── dsh/                      # Dev-only CLI (not shipped in the app)
├── App/
│   ├── project.yml               # XcodeGen: single iOS target
│   └── PocketDSH/                # SwiftUI sources
│       ├── Skin/                 # Theme tokens, skin parser/store/manager
│       ├── SkinCenterView.swift  # Skin Center
│       └── SpeechRecognizer.swift
├── Tests/DSHKitTests/            # 40 XCTest cases
├── docs/                         # Reverse engineering, architecture, parity, install
└── scripts/                      # Mock DeepSeek server and build helpers
```

---

## Quick start (iOS)

Requirements: macOS 14+, Xcode 16+ and [XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
cd App
xcodegen generate
open PocketDSH.xcodeproj
```

1. Select the `PocketDSH` scheme.
2. Target → Signing & Capabilities → choose your Team (change the bundle id if needed).
3. Pick an iPhone simulator or a device and Run.

On first launch:

1. Tap the gear icon → Settings.
2. Enter your DeepSeek API key (stored in the Keychain).
3. Pick a model (`deepseek-chat` by default; `deepseek-reasoner` or a custom base URL also work).
4. Pick a permission preset (`safe` / `review` / `default` / `danger`).

### Workspace and files

```
<App container>/Documents/DSH/Workspace     ← all file tools are confined here
<App container>/Documents/DSH/sessions/<id>/{header.json,events.jsonl}
```

`UIFileSharingEnabled` is on: Files → On My iPhone / iPad → DSH Pocket exposes the workspace for inspection and file drops.
The agent's `read_file / write_file / edit_file / glob / grep` tools are all constrained by `SandboxGuard` to this directory.

### Install on a device / export an ipa

Select your team and a connected iPhone in Xcode and Run. To distribute:

```bash
xcodebuild -project App/PocketDSH.xcodeproj \
  -scheme PocketDSH \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath build/PocketDSH.xcarchive archive
```

Then export an Ad Hoc / Development ipa from Xcode Organizer. Signing certificates and device UDIDs are up to you.

---

## Development checks (not part of the iOS app)

```bash
cd apple-dsh
swift test
```

End-to-end without an API key (mock DeepSeek SSE → tool call → result replay):

```bash
node scripts/mock-deepseek.mjs 18081 &
DEEPSEEK_API_KEY=test swift run dsh run "read hello.txt" \
  -C /tmp/dsh-smoke --base-url http://127.0.0.1:18081 --preset danger \
  --root /tmp/dsh-sessions
```

See [docs/TESTING.md](docs/TESTING.md). `dsh` is a development harness and is not part of the iOS app.

---

## iOS design notes

- **No shell** — iOS forbids `fork/exec`; `ShellTool` is compiled out with `#if os(macOS)`. Use `web_fetch` for the network and sandboxed file tools for the workspace.
- **Auditable workspace** — every path is standardized, symlink-resolved and prefix-checked; `../` escapes are rejected.
- **Approvals are first-class** — dangerous tools (writes, network, shell) resolve to allow / ask / deny per preset, and fail closed when no UI handler is available.
- **Interaction details** — session pinning, search and rename; “Always allow” approvals; full-text copy and Markdown export; haptics; compact-mode back navigation.
- **Mobile extras** — voice input via Speech, file import into the workspace, Markdown table rendering, horizontally scrollable code blocks with copy.
- **Keychain** — the API key never touches UserDefaults and is removed when the app is deleted.
- **Background suspension** — every event is persisted; on resume `repairOrphanTurn` closes any dangling turn/step/tool.
- **Local-first** — nothing is uploaded except DeepSeek API calls, skin Git sources, and pages you explicitly ask the model to fetch.
- **Skins are data, not code** — only CSS tokens and static assets are read; `hooks.mjs` and `patches.css` are never executed.

---

## Known limits

- Not implemented: MCP, subagents, Workflow, Jobs, the six-layer Skills provider, the SQLite backend and OTel. The matrix lives in [PARITY.md](docs/PARITY.md).
- Auto-compaction only trims the request; `surface/replace` events and fold are implemented but not triggered automatically.
- No image input, share extension or widgets yet.
- Video skin backgrounds fall back to a static preview; selector-level `patches.css` changes are skipped.
- Long-running turns may be suspended in the background; they resume when the app returns to the foreground without losing events.

---

## Install and signing

This repository **does not ship a signed ipa**. Every installer signs locally with their own Apple ID:

- Xcode + a free Apple ID: installs on your own iPhone, certificate expires after 7 days, just Run again;
- Unsigned ipa + AltStore / Sideloadly: sign locally, also 7 days;
- TestFlight / App Store: requires a paid Apple Developer Program membership.

```bash
./scripts/build-unsigned-ipa.sh   # produces build/PocketDSH-unsigned.ipa
```

See [docs/INSTALL.md](docs/INSTALL.md) for the step-by-step guide.

## Privacy

No telemetry, no account system, no cloud sessions. The API key lives only in the local Keychain; sessions and workspaces stay inside the app sandbox.
The only network requests are DeepSeek API calls, skin Git sources, and pages you explicitly ask the model to fetch.
The repository contents contain no certificates, API keys or personal contact details.

## License and credits

- This port is MIT-licensed. Original project: `dsh-go` © 2026 JopenChen, MIT.
- Semantics reference: DeepSeek Harness (the official TypeScript implementation).
- Not affiliated with DeepSeek.

See [LICENSE](LICENSE) and [NOTICE](NOTICE).

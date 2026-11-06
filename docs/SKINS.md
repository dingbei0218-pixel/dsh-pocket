# 皮肤系统

PocketDSH 的界面令牌默认对齐 **DSH Desktop** 的暗色主题（`--dsw-alias-*`），
并且可以直接加载 DSH Skin Manifest v2 的皮肤目录。

## 默认外观

默认主题 `DSH 默认` 使用官方暗色 token：

| 用途 | token | 值 |
|---|---|---|
| 画布 | `--dsw-alias-bg-base` | `#151517` |
| 侧栏 | `--dsw-alias-bg-layer-1` | `#232323` |
| 卡片 / 悬浮面板 | `--dsw-alias-bg-layer-2/3` | `#232324` / `#2c2c2e` |
| 主文字 | `--dsw-alias-label-primary` | `#ebeef2` |
| 次文字 | `--dsw-alias-label-secondary` | `#adb2b8` |
| 弱文字 | `--dsw-alias-label-tertiary` | `#81858c` |
| 强调 | `--dsw-alias-brand-primary` | `#4d93f8` |
| 危险 / 成功 / 警告 | `state-danger/success/warn` | `#ff6e8a` / `#4fe0b0` / `#ffd27a` |

布局也按桌面版收敛：左侧会话栏 + 顶部标题/状态 + 无气泡的助手正文 + 悬浮输入卡。

## 皮肤目录格式

一个皮肤是一个目录，至少包含：

```
<id>/
├── skin.json          # DSH Skin Manifest v2
├── skin.css           # --dsw-alias-* token（暗色块优先）
├── preview/
│   ├── dark.jpg
│   └── light.jpg
└── assets/            # 可选背景图/视频/字体
```

`skin.json` 关键字段：

```json
{
  "skinManifestVersion": 2,
  "id": "cyber-night",
  "name": "赛博夜城",
  "nameEn": "Cyber Night",
  "version": "0.2.0",
  "author": "logan0116",
  "accent": "#00e5ff",
  "preview": { "light": "preview/light.jpg", "dark": "preview/dark.jpg" },
  "contributes": {
    "stylesheet": "skin.css",
    "backgroundMedia": {
      "dark": { "type": "image", "src": "assets/bg.webp", "scrim": "linear-gradient(...)" }
    }
  }
}
```

App 只消费：`id / name / author / version / accent / preview / contributes.stylesheet /
contributes.backgroundMedia`。`hooks.mjs`、`patches.css` 不会被执行，也不会加载任何脚本。

## 从 Git 同步

设置 → 外观 → 皮肤中心 → 填入仓库地址 → 同步。

仓库结构约定：

```
repo/
└── skins/
    ├── cyber-night/skin.json
    ├── whale-fantasy/skin.json
    └── ...
```

默认源：`https://github.com/zhu1090093659/dsh-skins`（`skins/<id>/` 结构）。

同步流程：

1. `GET /repos/{owner}/{repo}` 拿默认分支；
2. `GET /git/trees/{branch}?recursive=1` 拿文件树；
3. 对每个 `*/skin.json` 拉 manifest，列出可安装皮肤；
4. 点「安装」时只下载该目录下的 `json/css/图片/视频`，总大小上限 60MB；
5. 落到 `Documents/DSH/Skins/<id>/`，立即应用。

GitHub 未登录 API 限额 60 次/小时；在皮肤中心填入 GitHub Token 可提高限额。
Token 只存在本地 UserDefaults，不上传。

## 本地安装

App 开启了 Files 共享。把皮肤目录拖进
「文件」App →「我的 iPhone / iPad」→「DSH Pocket」→ `DSH/Skins/<id>/`，
回到皮肤中心刷新即可看到。

## 兼容性与降级

| 皮肤能力 | iOS 端 |
|---|---|
| `--dsw-alias-*` 颜色 token | ✅ 完整读取，深色块优先 |
| `rgba()/calc()` alpha | ✅ 静态化（calc 取 0.55） |
| 背景 `image` | ✅ 全屏铺底 + 渐变压暗 |
| 背景 `video` | ⚠️ 取 `preview.dark` 作静态背景（省电） |
| `patches.css` 选择器 | ⚠️ 不执行；token 少的皮肤用预览图保留氛围 |
| `hooks.mjs` / 任意 JS | ❌ 不加载 |
| 浅色主题 | ❌ App 固定深色 |

## 安全

- 只接受 `skinManifestVersion == 2` 且 `id` 符合 `[a-z0-9-]` 的目录；
- 下载只允许 `json/css/jpg/jpeg/png/webp/gif/svg/mp4/webm`；
- 写入前过滤 `..` 与绝对路径，防止目录逃逸；
- 不执行皮肤中的任何代码。

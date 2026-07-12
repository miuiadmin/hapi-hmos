# HAPI HarmonyOS

> [Hapi](https://github.com/tiann/hapi) 的鸿蒙（HarmonyOS）原生客户端。用 **ArkTS + ArkUI** 重写官方的 React Web/PWA 前端，连接同一个 Hapi Hub，让你在鸿蒙设备上随时远程控制本地运行的 AI 编码 agent（Claude Code / Codex / Gemini）。

上游项目：**[tiann/hapi](https://github.com/tiann/hapi)** ｜ 命名：`hapi-hmos` = Hapi + **H**armony**OS**

---

## 项目简介

[官方 Hapi](https://github.com/tiann/hapi) 是一个**本地优先**的 AI 编码 agent 平台：在本地机器上运行 agent，通过 Web/PWA/Telegram 远程控制。它的核心架构是三段式：

```
CLI（包装 agent）  ←Socket.IO→  Hub（HTTP API + SSE + Telegram）  ←SSE/REST→  Web（React PWA）
```

官方只提供了 **Web/React PWA** 客户端。本仓库 `hapi-hmos` 的目标是把这个客户端**移植成鸿蒙原生 App**：

- **协议不变**：复用同一个 Hub 后端，只替换前端
- **原生体验**：用 ArkTS + ArkUI 重写，调用鸿蒙系统能力（推送、后台任务、生物识别等）
- **对齐上游**：长期跟踪官方 Web 端的功能集

## 上游项目（官方 Hapi）

本仓库的 `参考源码/hapi/` 是官方仓库的一份 clone，作为**只读参考**用于移植对照。

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/tiann/hapi |
| Git URL | `https://github.com/tiann/hapi.git` |
| npm 包 | [`@twsxtd/hapi`](https://www.npmjs.com/package/@twsxtd/hapi) |
| 参考版本 | `0.18.4` |
| 本地参考 commit | `ec3722a` |
| License | **AGPL-3.0-only** |
| 作者 | Kirill Dubovitskiy & weishu |
| 本地路径 | `参考源码/hapi/` |

### 同步官方更新

`参考源码/hapi` 是一个独立的 git clone（不是 submodule）。更新方式：

```bash
cd 参考源码/hapi
git fetch origin
git log --oneline -10 origin/main      # 先看上游新增
git checkout main && git pull           # 或切到指定 tag/commit
git rev-parse HEAD                      # 取新 commit，回填到本表
```

> **为什么不用 submodule**：参考源码体积较大且仅供对照阅读，普通目录更简单；精确锁定版本靠记录 commit 即可。

## 技术栈

| 层 | 技术 |
|---|---|
| 语言 | ArkTS（TypeScript 超集，强类型、禁动态特性） |
| UI 框架 | ArkUI（声明式 `@Component`） |
| 应用模型 | Stage 模型（`UIAbility`） |
| 网络 | `@ohos.net.http` + SSE（EventSource 等价） |
| 持久化 | `@ohos.data.preferences` / 关系型数据库 |
| 构建 / IDE | DevEco Studio、hvigor |
| 目标系统 | HarmonyOS NEXT（API 12+） |

## 架构

```
┌───────────────────────┐   HTTP REST + SSE    ┌─────────────────┐
│   hapi-hmos (ArkTS)   │ ←──────────────────→ │    Hapi Hub      │
│  EntryAbility / Pages │   (CLI_API_TOKEN)    │  (:3006 默认)    │
└───────────────────────┘                      └─────────────────┘
   原生端只对接 Hub，                                       ↑
   不直连 CLI/agent                                  Socket.IO
                                                          │
                                                   ┌─────────────┐
                                                   │  CLI(agent) │
                                                   └─────────────┘
```

数据流（与官方 Web 端一致）：

1. App 启动后用 `CLI_API_TOKEN` 向 Hub 登录
2. 订阅 SSE `/api/events` 接收实时会话 / 消息更新
3. 用户操作 → REST API → Hub → RPC → CLI → agent
4. agent 事件 → CLI → Hub（SQLite 落库 + SSE 广播）→ App

## 快速开始

### 环境要求

- DevEco Studio（最新稳定版）
- HarmonyOS SDK（API 12+）
- 一台运行中的 Hapi Hub（用于联调）

### 启动 Hub（联调用）

```bash
npx @twsxtd/hapi hub --relay     # 启动带 E2E 加密中继的 Hub
# 终端会打印 URL / 二维码 + CLI_API_TOKEN
```

Hub 默认监听 `127.0.0.1:3006`；鸿蒙设备远程访问需配置公网地址或反代，详见官方 `参考源码/hapi/docs/guide/installation.md`。

### 打开鸿蒙工程

1. DevEco Studio → **Open** → 选择本仓库根目录
2. 同步 SDK，等待 hvigor 构建完成
3. 在 App 配置里填入 Hub 地址与 `CLI_API_TOKEN`
4. 连接真机 / 模拟器，运行 `entry`

## 项目结构

```
hapi-hmos/
├── README.md                # 本文档
├── CLAUDE.md                # AI 编码助手工作指南
├── docs/
│   ├── 官方仓库对照.md       # 移植对照表、Hub API 速查、同步方法
│   └── 参考项目.md           # berry3 鸿蒙参考 demo + 文档检索 skill 说明
├── .claude/skills/          # 已复制的鸿蒙文档检索 skill（arkts / arkui retriever）
├── AppScope/                # 应用全局配置（app.json5、图标）
├── entry/                   # 主模块（主 UI、网络、能力）
│   └── src/main/
│       ├── ets/             # ArkTS 源码
│       │   ├── entryability/
│       │   ├── pages/       # 会话列表、聊天、终端、文件等页面
│       │   ├── components/
│       │   ├── api/         # Hub HTTP / SSE 客户端
│       │   └── models/      # 与 shared/src 对齐的类型
│       ├── resources/       # 字符串、颜色、媒体资源
│       └── module.json5     # 模块配置 + 权限声明
├── build-profile.json5
├── oh-package.json5
└── 参考源码/
    └── hapi/                # 官方仓库 clone（只读参考）
```

> Stage 模型工程骨架已生成（`AppScope/` + `entry/`，参照 berry3 最小范式）。**图标占位提醒**：`background.png` / `foreground.png` / `startIcon.png` 暂用 berry3 的图标，上线前需替换为 Hapi 官方图标。
> **打开方式**：DevEco Studio → Open → 选仓库根目录，等待 SDK 同步与 hvigor 构建（`local.properties` 由 DevEco 自动生成；首次需在 Project Structure 里配置签名）。

## 文档导航

- [CLAUDE.md](CLAUDE.md) — AI 助手工作指南、移植约定
- [docs/参考项目.md](docs/参考项目.md) — berry3 鸿蒙参考 demo（样式 / 写法都参考它）+ 文档检索 skill
- [docs/官方仓库对照.md](docs/官方仓库对照.md) — 上游模块对照 + Hub API 速查 + 同步方法

## License 与合规

官方 Hapi 采用 **AGPL-3.0-only**。本项目作为其客户端的衍生移植，同样以 **AGPL-3.0** 发布。

> ⚠️ AGPL 要求：通过网络提供服务的衍生作品必须公开源码。二次开发并对外提供服务时，需遵守 AGPL 开源义务。

## 致谢

- 上游项目：[tiann/hapi](https://github.com/tiann/hapi)（作者 Kirill Dubovitskiy & weishu）
- Hapi 是 [Happy](https://github.com/slopus/happy) 的本地优先分支，"HAPI" 即 "哈皮"

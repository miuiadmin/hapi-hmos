<div align="center">

# HAPI HarmonyOS

**[Hapi](https://github.com/tiann/hapi) 的鸿蒙（HarmonyOS）原生客户端**

用 **ArkTS + ArkUI** 重写官方 React Web/PWA 前端，对接同一个 Hub 后端，
让你在鸿蒙设备上随时远程控制本地运行的 AI 编码 agent（Claude Code / Codex / Gemini）。

**简体中文** · [English](./README.en.md)

[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-1C1C1C?style=for-the-badge&logo=gnu&logoColor=white)](./LICENSE)
![Platform](https://img.shields.io/badge/platform-HarmonyOS-1C1C1C?style=for-the-badge&logo=huawei&logoColor=white)
![Language](https://img.shields.io/badge/lang-ArkTS-1C1C1C?style=for-the-badge)

![API](https://img.shields.io/badge/API-23%20%7C%20HarmonyOS%206.1-1C1C1C?style=for-the-badge)
![Upstream](https://img.shields.io/badge/upstream-tiann%2Fhapi-1C1C1C?style=for-the-badge)

![GitHub stars](https://img.shields.io/github/stars/miuiadmin/hapi-hmos?style=for-the-badge&color=1C1C1C)
![GitHub last commit](https://img.shields.io/github/last-commit/miuiadmin/hapi-hmos?style=for-the-badge&color=1C1C1C)
![GitHub commit activity](https://img.shields.io/github/commit-activity/m/miuiadmin/hapi-hmos?style=for-the-badge&color=1C1C1C)

![GitHub repo size](https://img.shields.io/github/repo-size/miuiadmin/hapi-hmos?style=for-the-badge&color=1C1C1C)
![GitHub issues](https://img.shields.io/github/issues/miuiadmin/hapi-hmos?style=for-the-badge&color=1C1C1C)
![GitHub contributors](https://img.shields.io/github/contributors/miuiadmin/hapi-hmos?style=for-the-badge&color=1C1C1C)

`hapi-hmos` = Hapi + **H**armony**OS**

</div>

---

## 截图

> 📱 截图待补充：登录 / 会话列表 / 对话 / 工具卡 / 思考过程 / 深色模式。
>
> <!-- 补图后用表格并排展示，例如：
> <table>
>   <tr><td align="center">会话列表</td><td align="center">对话 + 工具卡</td><td align="center">深色模式</td></tr>
>   <tr>
>     <td><img src="docs/screenshots/sessions.png" width="240"></td>
>     <td><img src="docs/screenshots/chat.png" width="240"></td>
>     <td><img src="docs/screenshots/dark.png" width="240"></td>
>   </tr>
> </table>
> -->

---

## 特性

> 协议与官方 Web 端完全一致，只替换前端为鸿蒙原生实现。

### 💬 对话体验
- **消息流**：用户 / agent / **思考过程（reasoning，可折叠）** / 工具调用，分色气泡
- **Markdown 渲染**：代码高亮 + 复制 + 全屏预览、图片应用内全屏、链接外链打开
- **工具卡全生命周期**：进行中（elapsed 计时）/ 已完成 / 出错 / 待审批，含权限审批与答题（AskUserQuestion）/ Checklist footer
- **会话内消息搜索**：过滤模式，可搜正文 + 工具名/参数/结果
- **消息长按菜单**：复制 / 失败重发 / 分享
- **消息时间戳** + 跨日日期分隔（今天 / 昨天 / 日期）
- **导出 / 分享**整个对话为纯文本转录

### 📋 会话管理
- 会话列表：**搜索过滤**、下拉刷新、长按菜单（**重命名 / 归档 / 删除**）
- 会话生命周期操作（对齐 Hub REST：PATCH 重命名、archive、DELETE）
- 实时状态：活跃 / 生成中（thinking）指示

### ⚡ 实时与可靠性
- **SSE 实时推送**：会话与消息增量（`/api/events`，EventSource 等价实现）
- **JWT 自动刷新**：REST + SSE 鉴权自愈，token 过期自动续期
- **消息分页**：滚到顶加载更旧历史
- **停止生成（abort）**：生成中可一键中断

### 🎨 主题
- JS 调色板 + 亮 / 暗双套配色
- **浅色 / 深色 / 跟随系统**三选开关 + 本地持久化

### 🧪 工程质量
- **纯逻辑单测**（`entry/src/test` LocalUnit）：Reducer、ChatSearch、Message、SyncEvent、AgentState、HubClient/SSE 工具等
- V2 状态管理（`@ComponentV2` / `@Local` / `@Param` / `@Event` / `@Builder`）
- 渲染管线纯函数化：`ChatMessage[] + AgentState → Reducer → ChatBlock[]`（易测、可对照上游）

### 🔄 应用内更新（OTA）
- **应用内自更新**：启动检查 + 进 app 主动弹更新（2h 节流），下载 → md5/size 校验 → 安装一键完成
- 下载站纯静态托管（`berry.flyme.chat:8443/hapi/`），多 host 容错 + url 锚定安全（防更新清单被篡改指向恶意域）
- 跨项目共用：移植自 Berry `SelfUpdateManager`，`下载服务器/OTA接入文档.md` 与 Berry 仓逐字节一致；详见 [`下载服务器/OTA接入文档.md`](下载服务器/OTA接入文档.md)

---

## 项目简介

[官方 Hapi](https://github.com/tiann/hapi) 是一个**本地优先**的 AI 编码 agent 平台：在本地机器上运行 agent，通过 Web/PWA/Telegram 远程控制。核心架构是三段式：

```
CLI（包装 agent）  ←Socket.IO→  Hub（HTTP API + SSE + Telegram）  ←SSE/REST→  Web（React PWA）
```

官方只提供了 **Web/React PWA** 客户端。本仓库 `hapi-hmos` 把它**移植成鸿蒙原生 App**：

- **协议不变**：复用同一个 Hub 后端，只替换前端
- **原生体验**：ArkTS + ArkUI 重写，调用鸿蒙系统能力
- **对齐上游**：长期跟踪官方 Web 端的功能集

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

## 技术栈

| 层 | 技术 |
|---|---|
| 语言 | ArkTS（TypeScript 超集，强类型、禁动态特性） |
| UI 框架 | ArkUI 声明式，**V2 状态管理**（`@ComponentV2` / `@Local` / `@Param` / `@Event` / `@Builder`） |
| 应用模型 | Stage 模型（`UIAbility` + `EntryAbility`） |
| 网络 | `@ohos.net.http` + SSE（EventSource 等价，自写帧解析） |
| 持久化 | `@ohos.data.preferences` |
| 分享 | `@kit.ShareKit` |
| Markdown | `@cangjie-tpc/markdown_hybrid` |
| 构建 / IDE | DevEco Studio、hvigor |
| 目标系统 | HarmonyOS 6.1.0（API 23） |

## 快速开始

### 环境要求

- DevEco Studio（最新稳定版）
- HarmonyOS SDK（API 23 / HarmonyOS 6.1+）
- 一台运行中的 Hapi Hub（用于联调）

### 启动 Hub（联调用）

```bash
npx @twsxtd/hapi hub --relay     # 启动带 E2E 加密中继的 Hub
# 终端会打印 URL / 二维码 + CLI_API_TOKEN
```

Hub 默认监听 `127.0.0.1:3006`；鸿蒙设备远程访问需配置公网地址或反代，
详见官方 `参考源码/hapi/docs/guide/installation.md`。

### 打开鸿蒙工程

1. DevEco Studio → **Open** → 选择本仓库根目录
2. 同步 SDK，等待 hvigor 构建完成
3. 在 App 配置里填入 Hub 地址与 `CLI_API_TOKEN`
   - 或用**配置导入**（推荐）：在任意可点链接处（服务器网页 / 备忘录）放一条
     `hapi://connect?server=<URL 编码的地址>&token=<CLI_API_TOKEN>`，点一下即自动拉起 App、
     验证 token 并持久化保存（与手动登录走同一条链路；token 不入源码、不入 HAP，重启/换机点一次即恢复）。
     例：`hapi://connect?server=https%3A%2F%2Fhub.example.com%2F&token=xxxx`
4. 连接真机 / 模拟器，运行 `entry`

> 模拟器联调：Hub 在宿主机 `127.0.0.1:3006`，模拟器内用 `http://10.0.2.2:3006` 访问；
> 真机改用宿主机 LAN IP。

## 项目结构

```
hapi-hmos/
├── entry/src/main/ets/
│   ├── entryability/        # EntryAbility（Stage 模型入口）
│   ├── pages/               # LoginPage / Index（会话列表）/ ChatPage / SettingsPage
│   ├── components/          # ToolCard、MarkdownText、ReasoningBubble、DiffView、
│   │                        # SessionActionMenu、CodeBlock、AskUserQuestion …
│   ├── chat/                # 渲染管线纯逻辑：Reducer / ChatBlock / ChatSearch /
│   │                        # AgentState / NormalizedContent / Diff / Checklist …
│   ├── api/                 # HubClient（REST）+ SSEClient（含帧解析工具）
│   ├── models/              # 与上游 shared/src 对齐：Types / Message / SyncEvent / Auth / HubConfig
│   ├── theme/               # Palette / ThemeService / ThemeState（JS 调色板 + 亮暗双套）
│   ├── services/            # Connection / Preferences / Share
│   └── utils/               # DateFormatUtils 等
├── AppScope/                # 应用全局配置（app.json5、图标）
├── entry/src/test/          # 纯逻辑单测（LocalUnit）
├── docs/                    # 移植对照、参考项目说明
├── .claude/skills/          # 鸿蒙文档检索 skill（ArkTS / ArkUI retriever）
└── 参考源码/                # 本地只读对照（不入库，见下）
```

## 上游项目（官方 Hapi）

本仓库的 `参考源码/hapi/` 是官方仓库的一份**本地 clone**，作为只读参考用于移植对照（**不入库**，见下）。

| 项 | 值 |
|---|---|
| 仓库 | https://github.com/tiann/hapi |
| Git URL | `https://github.com/tiann/hapi.git` |
| npm 包 | [`@twsxtd/hapi`](https://www.npmjs.com/package/@twsxtd/hapi) |
| 参考版本 | `0.18.4` |
| 本地参考 commit | `ec3722a` |
| License | **AGPL-3.0-only** |
| 作者 | Kirill Dubovitskiy & weishu |

### 鸿蒙侧参考项目

| 项目 | 角色 | 参考范围 |
|---|---|---|
| **[chatcube](https://github.com/LongLiveY96/chatcube)**（MIT） | 🥇 主要 | **UI 样式（颜色 / 主题 / 字体 / 圆角 / 间距 / 动效）**、布局、流式对话、会话管理（业务 / 架构 / UX 全方位） |
| berry3 | 🔧 辅助 | **ArkTS 避坑文档库**（遇坑先查）+ 底层代码（系统能力），license 不明 → **仅参考不搬代码** |

> 🔒 **UI 样式一律以 chatcube 为准**（不自创、不参考 berry3 浏览器 UI）；ArkUI 写法 / 页面布局 / 对话 / 会话拿不准 → 先看 chatcube；**ArkTS / ArkUI 遇坑 → 先查 berry3 避坑文档**；只有底层 / 系统能力才看 berry3 代码。详见 [docs/参考项目.md](docs/参考项目.md)。

### 同步官方更新

`参考源码/hapi` 是独立 git clone（不是 submodule）。更新方式：

```bash
cd 参考源码/hapi
git fetch origin
git log --oneline -10 origin/main      # 先看上游新增
git checkout main && git pull           # 或切到指定 tag/commit
git rev-parse HEAD                      # 取新 commit，回填到上表
```

> **为什么 `参考源码/` 不入库**：它是上游 + chatcube 的本地对照 clone（共 245M，含各自独立 `.git`），仅供阅读对照；普通目录比 submodule 更简单，精确锁定版本靠记录 commit。clone 本仓库后如需对照，自行 `git clone tiann/hapi` 即可。

## 文档导航

- [CLAUDE.md](CLAUDE.md) — AI 助手工作指南、移植约定、命令速查
- [docs/官方仓库对照.md](docs/官方仓库对照.md) — 上游模块对照 + Hub API 速查 + 同步方法
- [docs/参考项目.md](docs/参考项目.md) — 鸿蒙侧参考项目（chatcube 为主、berry3 为辅）+ 文档检索 skill 说明

## License 与合规

官方 Hapi 采用 **AGPL-3.0-only**。本项目作为其客户端的衍生移植，同样以 **AGPL-3.0** 发布（见 [LICENSE](./LICENSE)）。

> ⚠️ AGPL 要求：通过网络提供服务的衍生作品必须公开源码。二次开发并对外提供服务时，需遵守 AGPL 开源义务。

## 致谢

- 上游项目：[tiann/hapi](https://github.com/tiann/hapi)（作者 Kirill Dubovitskiy & weishu）
- Hapi 是 [Happy](https://github.com/slopus/happy) 的本地优先分支，"HAPI" 即 "哈皮"
- 鸿蒙侧参考：[chatcube](https://github.com/LongLiveY96/chatcube)（MIT，布局 / 对话 / 会话 UX 参考）

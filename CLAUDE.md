# CLAUDE.md

本文件给 AI 编码助手（Claude Code 等）在本仓库工作时的指南。先读本文件，再看 [README.md](README.md)。

## 项目是什么

`hapi-hmos` 是官方 [Hapi](https://github.com/tiann/hapi) 的**鸿蒙原生客户端**。用 ArkTS + ArkUI 重写官方的 React Web/PWA 前端，对接**同一个 Hub 后端**（协议不变）。`参考源码/` 下有官方仓库的只读 clone：**当前主参考 `hapi-v0.25.4/`（固定 tag `v0.25.4`）**、历史快照 `hapi-v0.18.4/`（仅对比），用于移植对照。

## 仓库布局

```
参考源码/hapi-v0.25.4/   # 官方上游当前主参考（只读，勿改），固定 tag v0.25.4。结构见其 AGENTS.md
参考源码/hapi-v0.18.4/   # 官方上游历史快照（只读，仅对比），基线 v0.18.4
参考源码/chatcube/       # 业务/UX/UI 样式一线参考（ArkTS 原生 AI 聊天，只读快照，MIT）
参考源码/paseo/          # 业务范式 + 架构设计二线参考（RN+TS 的 agent 控制器，AGPL-3.0；不参考 UI/语法）
AppScope/        # 应用全局配置（待生成）
entry/           # 主模块：UI、Hub 客户端、能力封装（待生成）
docs/            # 移植对照、API 速查
```

## 架构与数据流（移植自上游）

```
ArkTS App  ←──HTTP REST + SSE──→  Hub(:3006)  ←──Socket.IO──→  CLI(agent)
              (CLI_API_TOKEN 鉴权)
```

- App 只对接 Hub，不直连 CLI / agent
- 实时更新走 SSE `/api/events`（对应官方 `web/src/hooks/useSSE.ts`）
- 用户操作走 REST API（对应官方 `web/src/api/client.ts`）
- 类型 / schema 对齐官方 `shared/src/`（types.ts、schemas.ts、socket.ts）

## 移植对照（web → 鸿蒙）

| 官方 Web（React） | 本项目（ArkTS） | 说明 |
|---|---|---|
| `web/src/api/client.ts` | `entry/.../api/HubClient.ts` | HTTP 封装，复用 REST 端点 |
| `web/src/hooks/useSSE.ts` | `entry/.../api/SSEClient.ts` | EventSource 等价实现 |
| `web/src/routes/sessions/` | `entry/.../pages/` | 会话列表 / 聊天 / 终端 / 文件页 |
| `web/src/components/SessionChat` | `entry/.../components/` | 聊天 UI（assistant-ui → ArkUI） |
| `web/src/hooks/queries/` | 页面 `@State` + `models/` | TanStack Query → ArkUI 状态管理 |
| `shared/src/types.ts` | `entry/.../models/` | 类型对齐 |
| `shared/src/schemas.ts`（Zod） | ArkTS 类型 + 手写校验 | ArkTS 无 Zod，手写校验替代 |

> 详细端点速查见 [docs/官方仓库对照.md](docs/官方仓库对照.md)。

## 开发约定

- **语言**：ArkTS（TypeScript 超集；禁动态特性：无 `any`、无 `eval`、强类型）
- **UI**：ArkUI 声明式（`@Component` / `@Builder` / 状态装饰器 `@State` `@Prop` `@Link`）
- **模型**：Stage 模型（`UIAbility` + `EntryAbility`）
- **缩进**：4 空格
- **命名**：页面 `XxxPage`、组件 `Xxx`、网络客户端 `XxxClient`；模型与上游命名对齐
- **类型优先**：所有 Hub 报文结构必须在 `models/` 显式定义，与 `shared/src` 保持一致
- **鉴权**：每个请求带 `CLI_API_TOKEN`（命名空间后缀 `:namespace`）
- **权限**：联网声明 `ohos.permission.INTERNET`；明文 HTTP 需在 `module.json5` 配置网络安全

## 常用命令（DevEco / hvigor）

构建以 DevEco Studio 为主；命令行可用 hvigor：

```bash
hvigorw assembleHap                              # 构建 HAP
hvigorw --mode module -p module=entry@default assembleHap
```

联调前先起 Hub：`npx @twsxtd/hapi hub --relay`，再把地址与 token 写入 App 配置。

## 参考源码使用规则

- `参考源码/hapi-v0.25.4/`（当前主参考）为**只读**：只读、对照，不要修改上游文件
- 同步上游：主参考固定在 tag `v0.25.4`（detached HEAD），不随 `main` 漂移；换版本见 [docs/官方仓库对照.md](docs/官方仓库对照.md)「同步上游」，更新后回填 README / 对照文档的版本与 commit 字段
- 实现 ArkTS 功能前，先读官方对应实现（**以 `参考源码/hapi-v0.25.4/` 为准**，路径见对照表），保持语义一致

## 鸿蒙实现参考

本项目有三类一线参考 + 一个二线参考：**chatcube 主（业务/UX）、berry3 主（ArkTS 语法 + 避坑文档 + 底层）、hapi 源码主（语义/协议）**；**paseo 二线（agent 编排业务范式 + 架构设计，RN + TS）**。详见 [docs/参考项目.md](docs/参考项目.md)。

| 项目 | 角色 | 参考范围 |
|---|---|---|
| **chatcube**（Cube Chat） | 🥇 主要 | **UI 样式（颜色 / 主题 / 字体 / 圆角 / 间距 / 阴影 / 动效 / 组件视觉）**、布局、流式对话、对话、会话管理（业务 / 架构 / UX 全方位） |
| **berry3**（Berry Browser） | 🔧 语法/避坑/底层 | **ArkTS 语法 + 避坑文档库**（遇坑先查）+ 底层代码（系统能力） |
| `参考源码/hapi-v0.25.4` | 语义 | 功能行为、Hub 协议、数据结构（当前主参考，v0.25.4） |
| **paseo**（Paseo） | 🥈 二线 | chatcube 未覆盖的 **agent 编排业务范式**（多 agent 并行 / worktree / 工具调用编排）+ **daemon-client 架构设计**（协议版本兼容 / 状态机 / 终端性能）。RN + TS，**不参考 UI 样式与 ArkTS 语法** |

- **位置**：chatcube → `参考源码/chatcube`（GitHub: LongLiveY96/chatcube）；berry3 → `~/Documents/harmony/project/berry3`（GitHub: miuiadmin/berry-browser）；paseo → `参考源码/paseo`（GitHub: getpaseo/paseo，AGPL-3.0，二线参考）
- **规则**：**UI 样式（颜色 / 主题 / 字体 / 圆角 / 间距 / 动效 / 组件视觉）一律以 chatcube 为准 —— 不自创、不参考 berry3 浏览器 UI**（具体文件见 [docs/参考项目.md](docs/参考项目.md) chatcube「UI 样式参考」表）；布局 / 对话 / 会话拿不准 → **先看 chatcube**；**ArkTS / ArkUI 遇坑（build/getter/ForEach/@Trace/JSON.parse/签名/hvigor 等）→ 先查 berry3 避坑文档**（尤其 berry3 `docs/ArkUI-V2严格模式避坑.md`）；底层 / 系统能力 chatcube 没有才看 berry3 代码
  - **⚠️ 例外：设置页看 berry3**。用户明确裁定（2026-08-04）：所有**设置页**（主页 `pages/SettingsPage.ets` 入口列表 + 子页 `pages/settings/*` + 组件层 `components/settings/*`）的样式**全面复刻 berry3**（iOS 设置风：莫兰迪彩色图标方块、分组白卡 r20、连续圆角咬合、按压态、搜索框、胶囊按钮），**不看 chatcube**。颜色仍走 JS 调色板 `paletteOf(isDark)`（非 `$r('sys.color.*')`），尺寸走 `$r('app.float.setting_*')`。**不要把设置页"修"回 chatcube 风。**
- **License**：chatcube = MIT（搬代码需保留版权，与 AGPL 兼容）；berry3 license 不明，仅参考不搬代码
- **查询鸿蒙官方文档**用本项目已复制的两个 retriever skill（`.claude/skills/`）：
  - ArkTS 语法 / 库 → `hmos-arkts-knowledge-retriever`
  - ArkUI 组件 / API / 错误码 → `hmos-arkui-knowledge-retriever`

## 关键思考

1. **对照优先**：不确定行为时，先读 `参考源码/hapi-v0.25.4/` 对应文件，再写 ArkTS
2. **协议不变**：不要改动与 Hub 的交互协议；行为对齐 Web 端
3. **根因修复**：修根因，不打补丁
4. **冲突 / 不确定**：简短列选项问，选更安全的路
5. **合规**：AGPL-3.0，衍生需开源

# CLAUDE.md

本文件给 AI 编码助手（Claude Code 等）在本仓库工作时的指南。先读本文件，再看 [README.md](README.md)。

## 项目是什么

`hapi-hmos` 是官方 [Hapi](https://github.com/tiann/hapi) 的**鸿蒙原生客户端**。用 ArkTS + ArkUI 重写官方的 React Web/PWA 前端，对接**同一个 Hub 后端**（协议不变）。`参考源码/hapi/` 是官方仓库的只读 clone，用于移植对照。

## 仓库布局

```
参考源码/hapi/   # 官方上游（只读，勿改）。结构见其 AGENTS.md
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

- `参考源码/hapi/` 为**只读**：只读、对照，不要修改上游文件
- 同步上游：`cd 参考源码/hapi && git pull`，更新后回填 README / 对照文档的 commit 字段
- 实现 ArkTS 功能前，先读官方对应实现（路径见对照表），保持语义一致

## 鸿蒙实现参考

本项目有两套鸿蒙侧参考，**优先级：chatcube 为主，berry3 为辅**。详见 [docs/参考项目.md](docs/参考项目.md)。

| 项目 | 角色 | 参考范围 |
|---|---|---|
| **chatcube**（Cube Chat） | 🥇 主要 | 布局、样式、流式对话、对话、会话管理（业务 / 架构 / UX 全方位） |
| **berry3**（Berry Browser） | 🥈 次要 | 仅底层代码参考（系统能力调用、特定底层实现） |
| `参考源码/hapi` | 语义 | 功能行为、Hub 协议、数据结构 |

- **位置**：chatcube → `参考源码/chatcube`（GitHub: LongLiveY96/chatcube）；berry3 → `~/Documents/harmony/project/berry3`（GitHub: miuiadmin/berry-browser）
- **规则**：ArkUI 写法 / 页面布局 / 对话 / 会话管理拿不准 → **先看 chatcube**；只有底层 / 系统能力类实现才看 berry3
- **License**：chatcube = MIT（搬代码需保留版权，与 AGPL 兼容）；berry3 license 不明，仅参考不搬代码
- **查询鸿蒙官方文档**用本项目已复制的两个 retriever skill（`.claude/skills/`）：
  - ArkTS 语法 / 库 → `hmos-arkts-knowledge-retriever`
  - ArkUI 组件 / API / 错误码 → `hmos-arkui-knowledge-retriever`

## 关键思考

1. **对照优先**：不确定行为时，先读 `参考源码/hapi` 对应文件，再写 ArkTS
2. **协议不变**：不要改动与 Hub 的交互协议；行为对齐 Web 端
3. **根因修复**：修根因，不打补丁
4. **冲突 / 不确定**：简短列选项问，选更安全的路
5. **合规**：AGPL-3.0，衍生需开源

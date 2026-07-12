<div align="center">

# HAPI HarmonyOS

**The native HarmonyOS client for [Hapi](https://github.com/tiann/hapi)**

A native rewrite of the official React Web/PWA frontend in **ArkTS + ArkUI**, talking to the same Hub backend —
control your locally-running AI coding agents (Claude Code / Codex / Gemini) remotely from HarmonyOS devices.

**English** · [简体中文](./README.md)

[![License: AGPL-3.0](https://img.shields.io/badge/license-AGPL--3.0-blue.svg)](./LICENSE)
![Platform](https://img.shields.io/badge/platform-HarmonyOS-1C1C1C?logo=huawei&logoColor=white)
![Language](https://img.shields.io/badge/lang-ArkTS-3178C6.svg)
![API](https://img.shields.io/badge/API-23%20%7C%20HarmonyOS%206.1-00B386.svg)
![Upstream](https://img.shields.io/badge/upstream-tiann%2Fhapi-8A2BE2.svg)

`hapi-hmos` = Hapi + **H**armony**OS**

</div>

---

## Screenshots

> 📱 Screenshots TBD: login / session list / chat / tool cards / reasoning / dark mode.
>
> <!-- Once available, show side by side, e.g.:
> <table>
>   <tr><td align="center">Sessions</td><td align="center">Chat + tool card</td><td align="center">Dark mode</td></tr>
>   <tr>
>     <td><img src="docs/screenshots/sessions.png" width="240"></td>
>     <td><img src="docs/screenshots/chat.png" width="240"></td>
>     <td><img src="docs/screenshots/dark.png" width="240"></td>
>   </tr>
> </table>
> -->

---

## Features

> The protocol is identical to the official Web client — only the frontend is replaced with a native HarmonyOS implementation.

### 💬 Chat experience
- **Message stream**: user / agent / **reasoning (thinking, collapsible)** / tool-call, color-coded bubbles
- **Markdown rendering**: code syntax highlighting + copy + fullscreen preview, in-app image preview, open external links
- **Full tool-card lifecycle**: running (elapsed timer) / completed / error / pending approval, with permission approval and AskUserQuestion / Checklist footers
- **In-conversation message search**: filter mode, searches body text + tool name / args / results
- **Message long-press menu**: copy / resend failed / share
- **Message timestamps** + cross-day date dividers (today / yesterday / date)
- **Export / share** an entire conversation as a plain-text transcript

### 📋 Session management
- Session list: **search & filter**, pull-to-refresh, long-press menu (**rename / archive / delete**)
- Session lifecycle actions (aligned with Hub REST: PATCH rename, archive, DELETE)
- Live status: active / generating (thinking) indicators

### ⚡ Realtime & reliability
- **SSE realtime push**: session & message deltas (`/api/events`, an EventSource-equivalent implementation)
- **JWT auto-refresh**: REST + SSE auth self-healing; tokens renew automatically on expiry
- **Message pagination**: load older history on scroll-to-top
- **Abort (stop generation)**: interrupt an in-flight generation with one tap

### 🎨 Theming
- JS-driven palette + light / dark color sets
- **Light / Dark / Follow system** three-way toggle + local persistence

### 🧪 Engineering quality
- **Pure-logic unit tests** (`entry/src/test` LocalUnit): Reducer, ChatSearch, Message, SyncEvent, AgentState, HubClient/SSE utils, …
- V2 state management (`@ComponentV2` / `@Local` / `@Param` / `@Event` / `@Builder`)
- Pure-function render pipeline: `ChatMessage[] + AgentState → Reducer → ChatBlock[]` (easy to test, easy to diff against upstream)

---

## Overview

[Official Hapi](https://github.com/tiann/hapi) is a **local-first** AI coding agent platform: agents run on your local machine and are controlled remotely via Web/PWA/Telegram. Its core architecture is three-tier:

```
CLI (wraps agent)  ←Socket.IO→  Hub (HTTP API + SSE + Telegram)  ←SSE/REST→  Web (React PWA)
```

The official project ships only a **Web/React PWA** client. `hapi-hmos` ports it to a **native HarmonyOS app**:

- **Protocol unchanged**: reuses the same Hub backend, only the frontend is replaced
- **Native experience**: rewritten in ArkTS + ArkUI, using HarmonyOS system capabilities
- **Tracks upstream**: follows the official Web feature set over time

## Architecture

```
┌───────────────────────┐   HTTP REST + SSE    ┌─────────────────┐
│   hapi-hmos (ArkTS)   │ ←──────────────────→ │    Hapi Hub      │
│  EntryAbility / Pages │   (CLI_API_TOKEN)    │  (:3006 default) │
└───────────────────────┘                      └─────────────────┘
   Native app talks only                                       ↑
   to Hub, never to CLI/agent                            Socket.IO
                                                          │
                                                   ┌─────────────┐
                                                   │  CLI (agent) │
                                                   └─────────────┘
```

Data flow (identical to the official Web client):

1. On launch, the app logs in to the Hub with `CLI_API_TOKEN`
2. Subscribes to SSE `/api/events` for realtime session / message updates
3. User actions → REST API → Hub → RPC → CLI → agent
4. Agent events → CLI → Hub (persisted to SQLite + broadcast via SSE) → app

## Tech stack

| Layer | Technology |
|---|---|
| Language | ArkTS (TypeScript superset; strongly typed, no dynamic features) |
| UI framework | ArkUI declarative, **V2 state management** (`@ComponentV2` / `@Local` / `@Param` / `@Event` / `@Builder`) |
| App model | Stage model (`UIAbility` + `EntryAbility`) |
| Networking | `@ohos.net.http` + SSE (EventSource-equivalent, custom frame parser) |
| Persistence | `@ohos.data.preferences` |
| Sharing | `@kit.ShareKit` |
| Markdown | `@cangjie-tpc/markdown_hybrid` |
| Build / IDE | DevEco Studio, hvigor |
| Target | HarmonyOS 6.1.0 (API 23) |

## Getting started

### Prerequisites

- DevEco Studio (latest stable)
- HarmonyOS SDK (API 23 / HarmonyOS 6.1+)
- A running Hapi Hub (for integration testing)

### Start the Hub (for testing)

```bash
npx @twsxtd/hapi hub --relay     # start a Hub with an E2E-encrypted relay
# the terminal prints a URL / QR code + CLI_API_TOKEN
```

The Hub listens on `127.0.0.1:3006` by default; for remote access from a HarmonyOS device you need a public address or reverse proxy — see `参考源码/hapi/docs/guide/installation.md`.

### Open the HarmonyOS project

1. DevEco Studio → **Open** → select this repo root
2. Sync the SDK and wait for the hvigor build to finish
3. Fill in the Hub address and `CLI_API_TOKEN` in the app config
4. Connect a device / emulator and run `entry`

> Emulator tip: if the Hub runs on the host at `127.0.0.1:3006`, access it as `http://10.0.2.2:3006` from the emulator; on a real device use the host's LAN IP.

## Project structure

```
hapi-hmos/
├── entry/src/main/ets/
│   ├── entryability/        # EntryAbility (Stage model entry)
│   ├── pages/               # LoginPage / Index (session list) / ChatPage / SettingsPage
│   ├── components/          # ToolCard, MarkdownText, ReasoningBubble, DiffView,
│   │                        # SessionActionMenu, CodeBlock, AskUserQuestion, …
│   ├── chat/                # render-pipeline pure logic: Reducer / ChatBlock / ChatSearch /
│   │                        # AgentState / NormalizedContent / Diff / Checklist, …
│   ├── api/                 # HubClient (REST) + SSEClient (with frame-parser utils)
│   ├── models/              # aligned with upstream shared/src: Types / Message / SyncEvent / Auth / HubConfig
│   ├── theme/               # Palette / ThemeService / ThemeState (JS palette + light/dark sets)
│   ├── services/            # Connection / Preferences / Share
│   └── utils/               # DateFormatUtils, …
├── AppScope/                # app-wide config (app.json5, icons)
├── entry/src/test/          # pure-logic unit tests (LocalUnit)
├── docs/                    # porting notes, reference-project notes
├── .claude/skills/          # HarmonyOS doc-retrieval skills (ArkTS / ArkUI retriever)
└── 参考源码/ (Reference/)   # local read-only references (NOT committed, see below)
```

## Upstream (official Hapi)

`参考源码/hapi/` is a **local clone** of the official repo, kept as a read-only porting reference (**not committed**, see below).

| Field | Value |
|---|---|
| Repo | https://github.com/tiann/hapi |
| Git URL | `https://github.com/tiann/hapi.git` |
| npm package | [`@twsxtd/hapi`](https://www.npmjs.com/package/@twsxtd/hapi) |
| Reference version | `0.18.4` |
| Local reference commit | `ec3722a` |
| License | **AGPL-3.0-only** |
| Authors | Kirill Dubovitskiy & weishu |

### HarmonyOS reference projects

| Project | Role | Reference scope |
|---|---|---|
| **[chatcube](https://github.com/LongLiveY96/chatcube)** (MIT) | 🥇 Primary | Layout, styling, streaming chat, session management (business / architecture / UX across the board) |
| berry3 | 🥈 Secondary | Low-level code only (system-capability calls, specific low-level impls); license unknown → **reference only, do not copy code** |

> When unsure about ArkUI patterns / page layout / chat / session management → check chatcube first; only consult berry3 for low-level / system capabilities.

### Syncing upstream

`参考源码/hapi` is a standalone git clone (not a submodule). To update:

```bash
cd 参考源码/hapi
git fetch origin
git log --oneline -10 origin/main      # review new upstream changes first
git checkout main && git pull           # or checkout a specific tag/commit
git rev-parse HEAD                      # take the new commit, fill it into the table above
```

> **Why `参考源码/` isn't committed**: it's a local reference clone of upstream + chatcube (245M total, each with its own `.git`), kept only for reading; a plain directory is simpler than a submodule, and commit pinning tracks the exact version. If you clone this repo and want the references, just `git clone tiann/hapi` yourself.

## Docs

- [CLAUDE.md](CLAUDE.md) — AI assistant working guide, porting conventions, command cheatsheet
- [docs/官方仓库对照.md](docs/官方仓库对照.md) — upstream module mapping + Hub API cheatsheet + sync method
- [docs/参考项目.md](docs/参考项目.md) — HarmonyOS reference projects (chatcube primary, berry3 secondary) + doc-retrieval skill notes

## License & compliance

Official Hapi is **AGPL-3.0-only**. As a derived client port, this project is likewise released under **AGPL-3.0** (see [LICENSE](./LICENSE)).

> ⚠️ AGPL requires: derivative works offered over a network must disclose their source. If you build on this and offer it as a service, you must comply with AGPL's open-source obligations.

## Acknowledgements

- Upstream: [tiann/hapi](https://github.com/tiann/hapi) (authors Kirill Dubovitskiy & weishu)
- Hapi is a local-first fork of [Happy](https://github.com/slopus/happy); "HAPI" is a transliteration of 哈皮 (Chinese for "happy")
- HarmonyOS reference: [chatcube](https://github.com/LongLiveY96/chatcube) (MIT — layout / chat / session UX reference)

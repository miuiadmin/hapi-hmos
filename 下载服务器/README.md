# Hapi 下载服务器（打包上传脚本集）

Hapi（鸿蒙客户端）安装包**自建公网分发站**的本地脚本：把 88-release 共存包打好 + HTTP 上传到服务器归档目录。访问 `https://berry.flyme.chat:8443/hapi?t=<token>` 即下载。

> ⚠️ **2026-07-10 重组（二）· 运行时融合**：下载站 Hono 路由已并入 **nodebook 单服务**（`nodebook.service`），不再有独立 `berry-dist.service` / 6699 端口，对外经 Caddy:8443。

> 🔧 **分工（重要）**：
> - **本目录**只管 **打包 + 上传**（`dist.sh` 打 88-release 1 包 → `sync-server.sh` HTTP 上传归档）。
> - **服务端**全在 **nodebook 项目**。hapi **复用 berry 同一台 nodebook 单服务**，仅加 `/hapi` 路由 + `/opt/hapi-dist` 存储 + 独立 `HAPI_TOKEN`（与 berry 的 `BERRY_TOKEN` / `/berry` 路由 / `/opt/berry-dist` 存储相互独立、互不影响）。这边不碰服务端。

## 现在的架构（一图看清）

```
本地 Mac                                     服务器 berry.flyme.chat（DNS → 实际机器 IP）
─────────────────────                       ──────────────────────────────────────
"帮我同步到服务器"                            systemd: nodebook.service（单服务）
  ↓ hapi-sync skill（若有）                     ↓ node /root/nodebook/dist/index.js
dist.sh → pack.sh 打 88-release 1 个 app       Hono app（一个进程干多件事）
  ├─ 默认变包名 88 + release .app                ├─ TG webhook（bot）
  └─ 写 manifest（含 bundleName/md5/...）        ├─ /sub/:token（Clash 订阅）
  ↓                                                  ├─ /berry/*（berry 人工下载，BERRY_TOKEN）
sync-server.sh HTTP POST /hapi/upload ────→         ├─ /hapi/*（hapi 人工下载，HAPI_TOKEN）
   └─ 上传 manifest → 服务端校验 md5                 ├─ /ota/*（berry 共存版 OTA 自更新，免 token）
                                                     ├─ /hapi-ota/*（hapi 共存版 OTA 自更新，免 token）
                                                  /opt/hapi-dist/files/archive/<日期>/<版本>/
                                                  Caddy 8443 → 127.0.0.1:8787（全量反代）
```

> 服务端怎么部署、hapi 的 `/hapi` 路由怎么加、token 怎么换 → 见 **nodebook `README.md`**。本目录只负责左半边（打包 + 上传）。

## 目录现状

```
下载服务器/
├── README.md           本文件（打包上传说明）
├── scripts/            ★ 本地发布脚本（本目录唯一可执行部分）
│   ├── config.example.sh   配置模板（进仓库）
│   ├── config.sh           实际配置（gitignore，含 token + PUBLIC_URL）
│   ├── dist.sh             打包 88-release 1 个 app（依赖 hapi-hmos 的 tools/pack.sh）
│   ├── sync-server.sh      HTTP 上传归档到服务器
│   └── publish.sh          ★一键发布（dist + sync，skill 调这个）
└── docs/
    └── 打包流程.md         dist.sh 1 个包怎么来、manifest 字段、发版时序约束
```

> hapi-sync skill 若存在则在 `.claude/hapi-sync/`（.claude/ gitignore，本地维护）。本任务只移植脚本，skill 不在其中——需要时另外建。

## 快速开始

### 每次发布新版本（本目录本职）
```bash
bash 下载服务器/scripts/publish.sh      # ★一键：打包 + 上传
# 或分两步：dist.sh 打包 → sync-server.sh 上传
```
或直接对 Claude 说「**帮我同步到服务器**」（若有 hapi-sync skill 则自动跑 publish.sh，否则手动跑上条）。上传后脚本打印下载页 URL，发给别人即可。

> 📦 **发版 TG 推送已关闭（沿用 berry 2026-07-16 决策）**：每次发版都推 TG 无必要，`sync-server.sh` 不再调 `/internal/release`（后端该端点已移除，现返 404）。发版后看脚本打印的下载页 URL 即可。

### ⚠️ 发版前置（首次 / 服务端 OTA 路由改动后）
**必须先部署 nodebook（含 bundleName 的 hapi OTA 路由）再发新客户端**。新客户端 `SelfUpdateManager.parseUpdateInfo` 要求 `/hapi-ota/update.json` 带 bundleName（非空），旧 nodebook 不带 → 新客户端 OTA 失效（拉到 JSON 但解析失败→无更新）。向前兼容：新 nodebook 多出的 bundleName 字段旧客户端忽略。部署见 nodebook README「部署 / 改代码」（本地 build → scp → restart，1G 内存绝不在服务器 tsc）。

### 首次部署 / 换机 / 改服务端代码
**不在本目录做** —— 见 **nodebook 项目 `README.md`**。本目录上传的归档，nodebook 实时 `readdir` 即生效，发新版本**无需重启服务、无需碰服务端代码**。

## 安装包（1 个，OTA 专用）

| 包 | 包名 | 用途 |
|----|------|------|
| `hapi-X.X.X-88-release.app` | `com.twsxtd.hapi88` | ⭐88 共存 release，OTA 升级源，与正式版互不冲突 |

未签名（pack.sh 清 signingConfig 生成侧载包），调试设备 `hdc install -r` 可装。

> **为什么只 1 个**：OTA 只推 88 共存包（正式版走 AGC 应用市场；debug 按需 `build.sh app-debug` 手打）。1 次编译，最快路径。

## 下载站现状

- **位置**：复用 berry 的下载站服务器（nodebook-rs Rust 服务，对外经 Caddy :8443）；对外域名 `berry.flyme.chat`（DNS 指向当前机器 IP，换机只改 DNS、hapi-hmos 零改）
- **人工下载**：`https://berry.flyme.chat:8443/hapi?t=<token>`（HTTPS :8443，要 HAPI_TOKEN）
- **OTA**：`https://berry.flyme.chat:8443/hapi-ota/update.json`（免 token，共存版 APP 内置 `SELF_UPDATE_HOST` 拉；客户端校验 `bundleName === 当前包名` 防 88 包装到非 88 包）
- **归档根**：`/opt/hapi-dist/files/archive/<日期>/<版本>/`（nodebook `FILES_ROOT` 指此，hapi 独立存储，与 berry 的 `/opt/berry-dist` 平行）
- **下载计数**：`/opt/hapi-dist/files/stats/downloads.json`（archive 同级，HTTP 上传不动）
- **APP 不内置人工下载地址**（只内置 OTA 主机常量 `SELF_UPDATE_HOST`）→ 换机换 IP 改这一处 + repack

## config.sh（本目录配置）

`下载服务器/scripts/config.sh`（gitignore，不进仓库）管四样：

| 变量 | 说明 |
|------|------|
| `SERVER_HOST` | 服务器对外域名（`berry.flyme.chat`，复用 berry 同服务器，DNS 解析到实际机器 IP）；HTTP/Caddy 全用此域名，换机只改 DNS |
| `TOKEN` | 下载站访问 token —— **必须与 nodebook `.env` 的 `HAPI_TOKEN` 一致**（hapi 独立 token，与 berry 的 `BERRY_TOKEN` 互不影响；上传/访问共用） |
| `PUBLIC_URL` | 对外域名（`https://berry.flyme.chat:8443`，经 DNS 指向 `SERVER_HOST`），拼下载页 URL 用，与服务器实际监听解耦 |
| `KEEP_VERSIONS` | 归档保留最近多少版本，超出自动清理（`sync-server.sh` 上传时带 `?keep=N` 让服务端删更旧的；默认 3，空间宽裕可调大如 100，`≤0` 关闭；只动 archive 不碰 stats） |

## ⚠️ 关键坑（打包相关，必读）

### 坑 1：~~打包顺序（deep_clean 时序）~~（已随 4→1 简化失效）
dist.sh 现只 1 阶段（pack.sh 打 88-release），不再有 deep_clean 时序问题。此坑保留作历史说明。

### 坑 2：~~AboutPage 时间戳（字节级恢复）~~（hapi 不适用）
berry 的 dist.sh 曾需对 `AboutPage.ets` 做字节级备份 + trap 恢复（pack.sh 步骤 0 会永久改 `BUILD_DATE_MARKER` 时间戳不还原）。**hapi 无 AboutPage.ets，移植时已整段删除备份/恢复逻辑**，无此步骤。此坑保留作历史说明。

### 坑 3：token 保护
- token 在 `config.sh`（gitignore）= nodebook `.env` 的 `HAPI_TOKEN`，**两边必须一致**
- config.sh 不进仓库 = 不泄露；完整轮换步骤见 nodebook README
- OTA（`/hapi-ota/*`）免 token：APP 内置 `SELF_UPDATE_HOST` 主机常量拉，不内置 token，换 token 无需 repack

### 坑 4：~~原始 release 签名依赖证书~~（已随 4→1 简化失效）
dist.sh 不打签名正式版（走 pack.sh 侧载包，清 signingConfig）。证书依赖仅 `build.sh build`（本地正式版编译 / AGC）需要，发版流程不再涉及。

### 坑 5：pack.sh 中途看 git status 会误判
pack.sh 运行中途 `git status` 会显示包名 patch 中间态（FILES_TO_PATCH 文件 M），是正常现象，trap 会恢复。确认工作区干净要 pack 前/后看。

### 坑 6：下载统计文件不能放归档目录
下载计数存 `files/stats/downloads.json`（`archive` **同级**的 `stats/` 下，**不在**归档目录里）。HTTP 上传同版本覆盖时别误碰 `files/stats/`（删了=清空所有历史计数）。

## 相关文档

- [docs/打包流程.md](docs/打包流程.md) — dist.sh 1 个包怎么来、manifest 字段、发版时序约束
- **服务端（部署/改代码/token/排错）→ nodebook 项目 `README.md`**

# Hapi 下载服务器（打包上传脚本集）

Hapi（鸿蒙客户端）88-release 共存包的**打包 + 上传**脚本。一键编译、打 88 共存包、生成 OTA 清单、rsync 上传到静态下载站。

> 📖 **完整架构 / OTA 契约 / 发版流程 / 加新 App / 排错 → [OTA接入文档.md](OTA接入文档.md)**（纯静态下载站的权威参考）。本 README 只讲本目录的定位与日常发版。

## 这是什么

下载站是一个**纯静态文件站**（服务器 Caddy `file_server browse` 托管 `/opt/dist/hapi/`），本目录负责把它喂饱：打好的 `.app` + 一份 `update.json` 上传上去，客户端就能读到新版并自更新。**没有动态后端、没有 token**（加新 App 不改代码，详见 OTA接入文档 §0/§7）。

```
本地 Mac                                     服务器 berry.flyme.chat:8443
─────────────────────                       ──────────────────────────────
publish.sh                                    Cloudflare 橙云 → :8443
  = dist.sh                                     Caddy file_server browse
    (pack.sh 打 88-release 包                       /opt/dist/hapi/
     + 本地生 manifest.json/update.json)            ├── update.json    ← 客户端读
  + sync-server.sh                                 ├── latest.app → hapi-0.0.x-88-release.app
    (rsync 归档 + 原子提升为最新)                     ├── hapi-0.0.x-88-release.app
                                                   └── archive/<日期>/<版本>/
```

> 服务端（Caddy/AWS/CF）由运维侧维护，见运维 `CLAUDE.md`；改服务端不在此目录。
> ✅ Hapi 的 OTA 客户端已实现（`entry/src/main/ets/services/SelfUpdateManager.ets`），按 OTA接入文档 §5 走，直接取规范路径 `/hapi/update.json`（全新接入，无需兼容桥）。

## 目录现状

```
下载服务器/
├── README.md           本文件
├── OTA接入文档.md       ★ 权威参考（架构/契约/流程/排错/加新 App）
├── scripts/            本目录唯一可执行部分
│   ├── config.example.sh   配置模板（进仓库）
│   ├── config.sh           实际配置（gitignore；见下）
│   ├── dist.sh             打 88-release 包 + 生 manifest/update.json
│   ├── sync-server.sh      rsync 上传归档 + 原子提升为最新
│   └── publish.sh          ★一键发布（dist + sync）
└── docs/
    └── 打包流程.md         dist.sh 内部机制（manifest 字段、BSD sed versionCode 坑）
```

## 快速开始

### 每次发新版本

```bash
# bump 版本号（AppScope/app.json5 的 versionName + versionCode，versionCode 须单调递增）
bash 下载服务器/scripts/publish.sh      # ★一键：打包 + 上传
```

> 或对 Claude 说「帮我同步到服务器」（若有 hapi-sync skill 则自动跑 publish.sh）。

发完验证：
```bash
curl -sk https://berry.flyme.chat:8443/hapi/update.json | head
```

> 发 OTA 包**不自动 git commit/push**；bump 改动留在工作区即可被打包，commit 是独立动作。

## 安装包（1 个，OTA 专用）

| 包 | 包名 | 用途 |
|----|------|------|
| `hapi-X.X.X-88-release.app` | `com.berry.hapi88` | ⭐88 共存 release，OTA 升级源，与正式版互不冲突 |

未签名（pack.sh 清 signingConfig 生成侧载包），调试设备 `hdc install -r` 可装。为什么只 1 个包 → OTA接入文档 §5/§6。

## config.sh（本目录配置）

`下载服务器/scripts/config.sh`（gitignore）是**本 App 的发布路由**，全字段说明见 OTA接入文档 §8。Hapi 的关键值：

| 变量 | Hapi 值 |
|------|----------|
| `APP` | `hapi` |
| `BUNDLE_NAME` | `com.berry.hapi88` |
| `PKG_PREFIX` / `PKG_GLOB` | `hapi` / `hapi-*.app` |
| `CHANGELOG_FILE` | （空，update.json.changelog=[]；将来接 changelog.json 再填） |
| `PROTECT_FILES` | （空，hapi 无 AboutPage.ets） |

## 关键坑（打包相关）

- **hapi 无 `AboutPage.ets`**，dist.sh 无字节级备份/恢复步骤（berry 才有，见 berry 项目打包流程.md 对照）。
- **pack.sh 中途看 git status 会误判**：运行中途 `git status` 显示包名 patch 中间态，正常，trap 会恢复。确认工作区干净要 pack 前/后看。

## 相关文档

- [OTA接入文档.md](OTA接入文档.md) — ★权威：架构 / update.json 契约 / URL 路由 / 客户端接入 / 发版流程 / 加新 App / 排错
- [docs/打包流程.md](docs/打包流程.md) — dist.sh 内部机制（1 个包怎么来、manifest 字段、BSD sed versionCode 坑）
- 服务端（Caddy/AWS/CF）：运维侧 `CLAUDE.md`

---
name: hapi-ota-release
description: "hapi-hmos 的 OTA 发版与验证 runbook。触发场景：(1) 出新 OTA 版本（bump 版本号→打包→上传下载站→验证）(2) 用户说「发新版/出个 OTA/同步到服务器」(3) 排查「设备没收到更新 / 装错包 / OTA 不生效」(4) 检查 FactoryPresets token 是否泄露进公开 HAP (5) 设备端查已装版本或验证 OTA 自更新链路。覆盖发布管线（publish.sh = dist + sync）、token 防泄露红线、设备端版本查询与模拟器 headless 验证的天花板。"
---

# hapi-hmos OTA 发版与验证

## 这是什么

hapi-hmos 通过**纯静态下载站**（`berry.flyme.chat:8443/hapi/`，Caddy `file_server`）向 **88 共存侧载包**（`com.berry.hapi88`）推 OTA 自更新。本 skill 是「出一次新版 + 确认它真的能更新到设备」的完整 runbook，并把反复踩过的坑固化下来。

```
本地 Mac                                  服务器 berry.flyme.chat:8443
────────────────────                      ──────────────────────────────
publish.sh                                  CF → :8443 → Caddy file_server
  = dist.sh                                   /opt/dist/hapi/
    (pack.sh 打 com.berry.hapi88 88-release       ├── update.json   ← 客户端读
     + 本地生 manifest.json / update.json)        ├── latest.app → hapi-0.0.x-88-release.app
  + sync-server.sh                                ├── hapi-0.0.x-88-release.app
    (rsync 归档 + 原子提升为最新)                  └── archive/<日期>/<版本>/
```

> 服务端架构 / `update.json` 契约 / URL 路由 / 客户端接入 / 加新 App / 回滚 → **[下载服务器/OTA接入文档.md](../../../下载服务器/OTA接入文档.md)**（权威，本 skill 不重复）。本 skill 只讲**发版动作 + 验证 + 这次的踩坑**。

---

## 发版流程（happy path）

### 0. 前置 ★安全红线：清 token

**这是最关键的一步，漏了就把私人 Hub token 发给全体用户。**

`entry/src/main/ets/config/FactoryPresets.local.ets` 本地可能存着真 Hub token（`git update-index --skip-worktree` 保护，git HEAD 是 `[]`，但工作区副本有真值）。**`dist.sh` 从工作区构建 → token 会被打进公开 HAP。**

```bash
# 1) 确认文件是空数组（与 HEAD 一致）
grep 'FACTORY_PRESETS' entry/src/main/ets/config/FactoryPresets.local.ets
#   应为: export const FACTORY_PRESETS: ServerPreset[] = [];

# 2) 全仓 grep 确认 token 片段 / Hub 主机名「仅」出现在 FactoryPresets.local 一处
#    （编译缓存 entry/build/.../FactoryPresets.local.ts 会有一份，pack.sh clean 会清掉重生成，无害）
grep -rn "<token前8位>" entry/src AppScope 2>/dev/null
grep -rn "<Hub主机名片段>" entry/src AppScope 2>/dev/null

# 3) skip-worktree 保留作防线（别 --no-skip-worktree）；清空内容即可
```

> 背景：deep-link 配置导入（`hapi://connect?server=&token=`）已取代编译期 FactoryPresets token——token 现在运行时导入 preferences，不入源码、不入 HAP。详见 `entry/.../services/DeepLinkImporter.ets`。

### 1. bump 版本号

编辑 `AppScope/app.json5`：
- `versionCode`：**+1，单调递增整数**（客户端用它判更新，不是 versionName）
- `versionName`：`"X.Y.Z"` 对应 +1

```json5
"versionCode": 6,
"versionName": "0.0.6",
```

### 2. 一键发布（打包 + 上传）

```bash
bash 下载服务器/scripts/publish.sh
#   = dist.sh   （pack.sh 变包名88 打 release.app + 本地生 update.json）
#   + sync-server.sh （rsync over ssh → aws:/opt/dist/hapi/，原子提升 latest）
#   dist 失败不会 sync（防半成品上线）
```

`config.sh`（gitignore）已填好路由：`APP=hapi / BUNDLE_NAME=com.berry.hapi88 / SSH_TARGET=aws / REMOTE_ROOT=/opt/dist/hapi / PUBLIC_URL=https://berry.flyme.chat:8443`。

> 约定：**发 OTA 包不自动 git commit/push**。bump 改动留在工作区即可被打包，commit 是独立的最后一步。

### 3. 验证（服务端，必做）

```bash
# ① 线上 update.json 的 versionCode 匹配
curl -sk https://berry.flyme.chat:8443/hapi/update.json | head
#   期望 versionCode=<新值>、bundleName=com.berry.hapi88、md5/size 齐全

# ② ★泄露复核：在产物里 grep token / Hub 主机名片段，必须 0 命中
APP=$(ls -t output/dist/*/hapi-*.app | head -1)
unzip -p "$APP" | grep -ac "<token前8位>"      # → 必须 0
unzip -p "$APP" | grep -ac "<Hub主机名片段>"   # → 必须 0
```

> `.app` 是 zip，`unzip -p` 流式吐全部条目供 grep。命中 >0 = 有泄露，**立即清 token → 重打 → 重发，并轮换 Hub 的 CLI_API_TOKEN**（已发出的旧包里的 token 视为泄露）。

### 4. 提交（commit 到 main，不 push）

两段提交（对齐仓库历史风格）：
```
<feat/refactor>:  <功能改动>
chore(release): 版本号 0.0.X → 0.0.Y
```
均带 `Co-Authored-By: Claude <noreply@anthropic.com>` 尾注，commit 到 `main` **不 push**。FactoryPresets.local 因 skip-worktree 对 git 不可见，不会进 commit。

---

## 验证（设备端）

### 查设备当前装的版本

```bash
hdc shell bm dump -n com.berry.hapi88
```
⚠️ **取根级 `versionName`/`versionCode`（JSON 末尾那对，如 `"versionCode": 3`）**。
**不要**被 `appQuickFix.{deployedAppqfInfo,deployingAppqfInfo}` 嵌套的 `"versionCode": 0 / "versionName": ""` 误导——那是热修复子字段，恒为 0/空，不是 app 版本。

OTA 目标包是 **`com.berry.hapi88`**（不是调试用的 `com.berry.hapi`）。客户端 `SelfUpdateManager` 校验「下载包 bundleName === 当前包 bundleName」，非 88 包不会真正发请求。

### 触发 OTA 自检 —— headless 天花板（重要）

**模拟器上无法 headless 触发 app 的 OTA 自更新**，原因是这一串墙：

| 墙 | 现象 |
|---|---|
| shell 非 root | `hdc shell id` = `uid=2000(shell)`；`su` 不存在 |
| 停不掉 app | `aa force-stop -b com.berry.hapi88` 报 `10104002「未安装」`（沙箱上下文，`bm dump` 能查但 aa 停不掉）；`kill -9 <pid>` EPERM |
| → 无法冷启动 | `aa start` 只把已在跑的 app 拉前台（不重启 → 不跑 bootstrap） |
| onForeground 节流 | `OtaController.checkForUpdates(false,true)` 走 **2h 节流**；冷启动 bootstrap 才是 `force=true` 静默检查 |
| 设备无 curl | 不能从设备 shell `curl update.json` 验可达性 |
| hilog 抓取 | `hilog -x` = **dump 完即退出**（非阻塞，适合捕获）；TAG=`SelfUpdate`；关键串「发现新版本: …(versionCode=A → B)」「所有可信主机取 update.json 均失败」 |

**结论**：app 自更新是 UI 流程，模拟器 headless 触发不了。两条出路：

1. **真自更新测试**（用户手动）：把 `com.berry.hapi88` 从最近任务划掉（冷启动 → bootstrap 静默检查 + 置「检查更新」徽标），或进 app 设置页 → **检查更新** → 弹「发现新版本」→ 下载安装。
   - ⚠️ 0.0.3 及更早**无**「进 app 主动弹更新」（那是 0.0.4+ 才有），只能走设置页手动检查。
2. **绕过自更新直接升级**（headless，用于验新功能）：直接 hdc 装新 88 包，等同 OTA 产物，立刻到新版：
   ```bash
   hdc install "$(ls -t output/dist/*/hapi-*.app | head -1)"   # emulator 接受未签名；同 bundle 覆盖升级
   hdc shell aa start -a EntryAbility -b com.berry.hapi88
   ```

### hdc 路径

不在 PATH，用全路径：`~/Documents/harmony/ohsdk/23/toolchains/hdc`（详见 memory `hapi-hmos-hdc-usage`）。

---

## 排错速查

| 现象 | 根因 / 处置 |
|---|---|
| `update.json` 版本号没变 | Caddy/CF 缓存。客户端带 `Cache-Control: no-cache`；curl 验加 `-H 'Cache-Control: no-cache'` 或等缓存过期 |
| 客户端不弹更新 | ① 本地 versionCode ≥ 服务端（查根级版本，见上）② 被「忽略此版本」过滤过 ③ 当前不是 `com.berry.hapi88`（只有 88 包真发请求）④ 0.0.3- 无主动弹窗，走设置页手动检查 |
| `bm dump` 显示 versionCode 0 | 取错字段了——那是 appQuickFix 嵌套值，取 JSON 末尾根级那对 |
| publish 上传失败 | `sync-server.sh` 走 `ssh aws`（ProxyCommand 经中继绕 GFW）。查 `~/.ssh/config` 的 `aws` 别名连通性 / 服务器 rsync / 磁盘空间 |
| pack.sh 预检命中硬编码包名 | 新增了含 `com.berry.hapi` 字面量的源文件 → 加进 `tools/pack.sh` 的 `FILES_TO_PATCH`（要替换）或 `SCAN_WHITELIST`（仅注释/正则，不替换） |
| pack.sh 中途 `git status` 脏 | 正常——包名 patch 中间态，trap 会逐文件恢复。pack 前/后看才准 |
| 产物 grep token 命中 >0 | **泄露**。立即清 FactoryPresets → 重打重发 → 轮换 Hub CLI_API_TOKEN |

---

## 相关文档（只指不重复）

- [下载服务器/OTA接入文档.md](../../../下载服务器/OTA接入文档.md) — ★权威：架构 / `update.json` 契约 / URL 路由 / 客户端接入 / 发版流程 / 加新 App / 排错 / 回滚
- [下载服务器/README.md](../../../下载服务器/README.md) — 目录定位 + 日常发版 + config.sh
- [下载服务器/docs/打包流程.md](../../../下载服务器/docs/打包流程.md) — dist.sh 内部机制（1 个包怎么来、manifest 字段、BSD sed versionCode 坑）
- [tools/pack.sh](../../../tools/pack.sh) — 变包名 88 侧载包构建（FILES_TO_PATCH / SCAN_WHITELIST / 备份恢复 trap）
- `entry/src/main/ets/services/SelfUpdateManager.ets` — 客户端 OTA 逻辑（多 host 容错 / versionCode 对比 / md5+size 双校验 / bundleName 守卫）
- `entry/src/main/ets/services/UpdateState.ets`（OtaController）— 检查调度（冷启动 force=true silent / onForeground 2h 节流 / 设置页手动）

# OTA 接入文档(纯静态下载站)

> 适用范围:Berry / Hapi / 任何未来接入的鸿蒙 App 的应用内自更新(OTA)。
> **本文档是 2026-08-03 起的纯静态下载站架构的权威参考**。与本目录其他文档冲突时**以本文档为准**。

---

## 0. 一句话设计

下载站就是一个**纯静态文件站**(Caddy `file_server browse` 托管一个目录),每个 App 一个子目录,里面放一个固定名字的 `update.json`(更新清单)+ `latest.app`(最新包)。客户端读 `update.json` 判断有没有新版、下包、校验、安装。

**核心承诺:加一个新 App = 在服务器建个子目录放文件 + 客户端项目里填个 `config.sh`,零后端代码改动。** 没有动态后端、没有 token、没有 per-app 逻辑。这是从旧「nodebook 多 App 后端(每加一个软件改一段代码)」整改过来的。

---

## 1. 架构

```
客户端 App                                  服务器(AWS 47.130.2.49)
─────────────                              ──────────────────────────────────────
SelfUpdateManager                          Cloudflare 橙云(加速+隐藏源站)
  GET /<app>/update.json  ─────HTTPS────→    ↓ :8443
  比版本 / 校验 bundleName                   Caddy(file_server browse,root /opt/dist)
  GET /<app>/latest.app   ─────HTTPS────→      ↓ 静态文件 + 目录浏览
  校验 md5+size → 安装                       /opt/dist/
                                              ├── berry/{update.json, latest.app, *.app, archive/}
                                              └── hapi/{update.json, latest.app, *.app, archive/}
```

- 对外域名 **`berry.flyme.chat:8443`**(所有 App 共用这一个站;`:8443` 因 443 被 reality 占,经 CF 橙云回源)。
- 换后端机器/IP/端口**只改服务端**(CF DNS + Caddy),客户端 URL 永不变。
- nodebook 后端**已退出下载站业务**,不再参与 OTA。

---

## 2. 服务器目录结构

```
/opt/dist/                                   ← Caddy root, browse 根 = 全站 App 列表
├── berry/
│   ├── update.json                          ← 当前最新版的 OTA 清单(客户端读这个)
│   ├── latest.app -> berry-1.3.156-88-release.app   ← 符号链接,版本无关的稳定下载 URL
│   ├── berry-1.3.156-88-release.app        ← 当前最新包(版本特定文件名,可长缓存)
│   ├── manifest.json                        ← 完整构建元数据(归档留档,browse 可见)
│   └── archive/<日期>/<版本>/               ← 历史版本(发版即归档,留最近 N 个日期)
│       └── {*.app, manifest.json, update.json}
└── hapi/
    ├── update.json
    ├── latest.app -> hapi-0.0.1-88-release.app
    ├── hapi-0.0.1-88-release.app
    └── archive/...
```

- `/` → browse 列全站 App(用户"进去看到所有文件")。
- `/<app>/` → browse 列该 App 的文件。
- `/<app>/update.json` → OTA 清单;`/<app>/latest.app` → 最新包。
- `latest.app` 符号链接每次发版重指 → `update.json.url` 用它做**跨版本稳定**的下载地址。

---

## 3. `update.json` 契约(★核心)

每个 App 根目录一个静态 `update.json`,**这就是客户端与服务端之间的全部约定**:

```json
{
  "versionName": "1.3.156",
  "versionCode": 10010456,
  "bundleName": "com.berry.browser88",
  "url": "https://berry.flyme.chat:8443/berry/latest.app",
  "md5": "76afc5cf0a264d0251dc8479dca83329",
  "size": 35021021,
  "changelog": [
    "弹窗背景对比度优化:……"
  ]
}
```

| 字段 | 类型 | 说明 |
|---|---|---|
| `versionName` | string | 展示用版本号(如 `1.3.156`)。客户端**不用它判更新**。 |
| `versionCode` | **number** | 单调递增整数。客户端**用它判更新**:`versionCode > 已装 versionCode` → 有新版。⚠️必须是数字不是字符串。 |
| `bundleName` | string | 升级目标包名。客户端校验 `=== 本机已装 bundleName`,**不符=无更新**(防 88 共存包装到非 88 包)。 |
| `url` | string | **绝对**下载地址,恒指 `https://berry.flyme.chat:8443/<app>/latest.app`(跨版本稳定)。 |
| `md5` | string | 包文件 md5,小写 32 位 hex。客户端下完校验,不符不装。 |
| `size` | number | 包文件字节数。客户端下完校验/用于进度条。 |
| `changelog` | string[] | 更新日志条目,OTA 弹窗展示。无则 `[]`。 |

> 客户端宽松解析:多余字段忽略;缺字段按"无更新/校验失败"处理。
> 此 JSON 由客户端打包脚本 `dist.sh` 在本地生成(见 §6),服务端原样托管。

---

## 4. URL 路由

### 规范路径(新版本客户端用这些)
| URL | 含义 |
|---|---|
| `/<app>/update.json` | OTA 清单 |
| `/<app>/latest.app` | 最新包(经 symlink) |
| `/<app>/` | browse 列该 App 文件 |
| `/` | browse 列全站 App |

### 兼容桥(只服务已装的老版本客户端)
老版本客户端的 OTA URL 是**硬编码进 hap 二进制**的、改不动。Caddy 用内部 rewrite 把这些旧 URL 转发到规范路径(URL 不变,客户端零改动):

| 老版本硬编码 URL | rewrite 到 |
|---|---|
| `/ota/update.json`、`/berry-ota/update.json` | `/berry/update.json` |
| `/hapi-ota/update.json` | `/hapi/update.json` |
| `/ota/latest`、`/berry-ota/latest` | `/berry/latest.app` |
| `/hapi-ota/latest` | `/hapi/latest.app` |

> 新版本客户端(见 §7)直接取规范路径,**不依赖兼容桥**。等所有用户升上新版,桥可删。
> 新 App 接入**无需**兼容桥 —— 桥只为已经有老版本在野的 App 准备(Berry)。

### 缓存
`update.json` 和 `latest.app` 是**可变内容**(发版后变),Caddy 强制 `Cache-Control: no-cache, no-transform`,CF 判定 `cf-cache-status: DYNAMIC`(不缓存) → 发版后客户端必拿新清单。版本特定的 `berry-1.3.156-….app` 按文件名不可变,可长缓存。

---

## 5. 客户端接入契约(客户端必须实现)

一个 App 要支持 OTA,客户端需实现以下流程(参考实现:**Berry** 的 `entry/src/main/ets/utils/SelfUpdateManager.ets`):

1. **取清单**:`GET https://berry.flyme.chat:8443/<app>/update.json`(带 no-cache 头,防中间层缓存旧清单漏检新版)。
2. **解析校验**:JSON parse,逐字段类型校验(`versionCode`/`size` 是 number、`md5`/`bundleName`/`url`/`versionName` 是非空 string、`changelog` 是数组)。
3. **判更新**:`update.json.versionCode > 本机已装 versionCode` → 有新版(用数字比较,不用 versionName)。
4. **校验包名**:`update.json.bundleName === 本机 bundleName` → 不符视为无更新(防装错包)。★ 必做。
5. **下载**:`GET update.json.url`(流式,带进度)。
6. **校验+安装**:下载内容 md5(小写)=== `update.json.md5` 且 size === `update.json.size` → 安装 `.app`;不符丢弃不装。

**推荐增强**(Berry 参考实现里有,新 App 可选):
- **多 host 容错**:可信主机列表逐个试,单点失败自动换下一个(Berry:`SELF_UPDATE_HOSTS`,berry.flyme.chat 永久首位)。
- **url 锚定安全**:校验 `url` 必须 startsWith 列表内可信 host(防 update.json 被篡改指向恶意域)。

> **Hapi** 的 OTA 客户端尚未实现;实现时按本契约走,直接用规范路径 `/hapi/update.json`(无需兼容桥,因为是全新接入)。

---

## 6. 发版流程(每次发新版本)

```bash
# 1. bump 版本号(必须:versionCode 单调递增)
#    编辑 AppScope/app.json5 的 versionName + versionCode

# 2. 写更新日志(Berry:entry/src/main/resources/rawfile/changelog.json,实质内容禁套模板)
#    (Hapi 未设 CHANGELOG_FILE → update.json.changelog=[];将来接再填)

# 3. 一键打包 + 上传
bash 下载服务器/scripts/publish.sh
#   = dist.sh(编译打 88 共存 release 包 + 本地生成 manifest.json/update.json)
#   + sync-server.sh(rsync 上传归档 + 原子提升为最新)
#   dist 失败不会 sync(防半成品上线)

# 4. 验证
curl -sk https://berry.flyme.chat:8443/<app>/update.json | head
```

### sync 原子提升顺序(保证客户端任何时刻读到的 url→包已就位)
1. rsync 整个 dist 目录 → `archive/<日期>/<版本>/`(归档历史)
2. 根层原子提升(**顺序关键**):`cp 包` → `ln -sfn latest.app` → `删旧 *.app` → `mv update.json`(最后换清单 = commit point)
3. prune:`archive/` 留最近 `KEEP_VERSIONS` 个日期(根层最新永不删)

> 打包内部机制(pack.sh / AboutPage 字节恢复 / manifest 字段来源 / BSD sed versionCode 坑)详见 [docs/打包流程.md](docs/打包流程.md)。
> ⚠️ 发 OTA 包**不自动 git commit/push**;bump + changelog 改动留在工作区即可被打包。commit 是独立动作。

---

## 7. 加一个新 App(zero-code onboarding)

假设要接入新 App `foo`:

1. **客户端项目**(本项目同款结构):
   ```bash
   # 复制脚本三件套(与已有项目逐字节一致)
   cp -r 下载服务器/scripts/  <foo项目>/下载服务器/scripts/
   # 填 config.sh(从模板创建后改)
   cp 下载服务器/scripts/config.example.sh 下载服务器/scripts/config.sh
   ```
   编辑 `config.sh`(见 §8),关键填:`APP="foo"`、`BUNDLE_NAME`(=本 App 的 88 共存包名)、`PKG_PREFIX`、`PKG_GLOB`。

2. **首次发版**:
   ```bash
   bash 下载服务器/scripts/publish.sh
   ```
   `sync-server.sh` 会自动在服务器 `mkdir -p /opt/dist/foo`(Caddy browse 是泛化的,新目录立即可浏览/服务,**无需改 Caddy、无需改任何后端代码**)。

3. **客户端**:按 §5 实现取 `https://berry.flyme.chat:8443/foo/update.json` 的更新逻辑。

完成。**没有第 4 步,没有服务端代码改动。** 这就是"加软件不改代码"。

> 若新 App 已有老版本在野、且老版本硬编码了别的 URL → 在 Caddy `berry.flyme.chat` 块加一条 rewrite 桥(参考 §4 现有桥的写法)。全新 App 无此问题。

---

## 8. `config.sh` 字段(每个 App 唯一的差异)

`下载服务器/scripts/config.sh`(gitignore,不进仓库)是**两个项目之间唯一的实质差异**;`dist.sh`/`sync-server.sh`/`publish.sh` 三者跨项目逐字节一致,全靠读它参数化:

| 变量 | 说明 |
|---|---|
| `APP` | slug = `/opt/dist` 子目录名 + URL 段(`berry`/`hapi`/`foo`) |
| `TITLE` | 横幅/日志显示名 |
| `BUNDLE_NAME` | OTA bundleName(客户端校验 === 本机包名;88 共存版 = 基础包名 + `88`) |
| `PKG_PREFIX` | 包文件名前缀(`<prefix>-<version>-88-release.app`) |
| `PKG_GLOB` | dist 产物 glob(如 `berry-*.app`) |
| `BUILD_CMD` | 构建钩子(默认 `tools/pack.sh`,产 `.app` 到项目根 `output/`) |
| `APP_JSON` | versionName/versionCode 来源(默认 `AppScope/app.json5`) |
| `CHANGELOG_FILE` | changelog 来源(相对项目根;空 = `[]`) |
| `PROTECT_FILES` | 打包前后字节备份+恢复的文件数组(相对项目根;Berry 保护 `AboutPage.ets`) |
| `PUBLIC_URL` | 静态站对外地址(`https://berry.flyme.chat:8443`) |
| `SSH_TARGET` | `~/.ssh/config` 别名(本机 `aws` = ProxyCommand 经火山92 中继绕 GFW) |
| `REMOTE_ROOT` | 该 App 静态根(`/opt/dist/<app>`) |
| `KEEP_VERSIONS` | `archive/` 保留最近 N 个日期,超出清理(`≤0` 关闭) |

> 改脚本逻辑(dist/sync/publish)→ 必须同步复制到另一项目(逐字节一致);改 `config.sh` = 只改本 App 的发布路由,不影响他项目。

---

## 9. 排错

| 现象 | 排查 |
|---|---|
| 客户端检测不到新版 | ① `curl …/<app>/update.json` 看 `versionCode` 是否 > 已装;② 看 `cf-cache-status` 是否 `DYNAMIC`(若 `HIT` = CF 缓存了旧清单,等 TTL 或发版后重试);③ `bundleName` 是否 === 本机包名 |
| 检测到但下载失败 | ① `curl …/<app>/latest.app` 是否 200;② 服务器 `ls -l /opt/dist/<app>/latest.app` symlink 是否指向存在的包 |
| 下载完 md5 不符 | 重新 `publish.sh`(可能上传截断);服务器 `md5sum latest.app` 与 `update.json.md5` 比对 |
| 新 App 目录 404 | 确认首次 `publish.sh` 跑过(自动 mkdir);Caddy browse 对新子目录即时生效 |
| 兼容桥失效(老版本) | 服务器 `cat /etc/caddy/Caddyfile` 看 `berry.flyme.chat` 块的 rewrite 是否在;`systemctl reload caddy` |

### 回滚
- **服务端目录** `/opt/dist/` 始终保留,无需回滚删除;发坏版本直接再发一版覆盖。
- **Caddy 配置**:改前已备份 `/etc/caddy/Caddyfile.bak.<ts>`,回滚 = `cp` 恢复 + `systemctl reload caddy`。
- **客户端**:OTA 失败不影响已装版本运行,修复后重新发版即可。

---

## 10. 相关文档

- [docs/打包流程.md](docs/打包流程.md) — `dist.sh` 1 个包怎么来、`manifest.json` 字段、`pack.sh` 机制、发版时序
- [scripts/config.example.sh](scripts/config.example.sh) — `config.sh` 模板
- 客户端参考实现(Berry):`entry/src/main/ets/utils/SelfUpdateManager.ets`
- 服务端(Caddy/AWS/CF)详情:运维侧 `CLAUDE.md`(§六 nodebook、§十一 协议节点)

---

*维护约定:本文档跨 Berry / Hapi 两项目**逐字节一致**(与 dist/sync/publish 脚本同理);改本文档须同步复制到另一项目。*

# hapi-hmos 工具脚本

移植自 berry3（Berry Browser）的构建/打包/签名/日志 shell 脚本，适配 hapi 身份
（bundle name `com.twsxtd.hapi`）。这些脚本只对接 hvigor / hdc / DevEco Studio，不依赖
berry3 的任何证书、changelog 或 AboutPage。

## 首次使用

```bash
chmod +x tools/*.sh            # 赋予可执行位（Windows clone 后可能丢失）
bash tools/setup-hooks.sh      # 一次性启用 .githooks/（配置 core.hooksPath）
tools/build.sh doctor          # 检查 hvigor / SDK / JAVA_HOME 是否正确发现
```

`debug.log`（logcat 输出）已被 `.gitignore` 的 `*.log` 忽略。**建议**额外把运行时产物
加入 `.gitignore`（本移植未自动改 `.gitignore`，避免越界改动）：

```
/output/
/.pack.lock
/.pack_backup_*/
```

## 脚本清单

| 脚本 | 作用 |
|---|---|
| `build.sh` | 编译总调度。子命令：`build`/`release`/`debug`/`app-debug`/`hap-release`/`run`（编+装+启）/`install`/`clean`/`lint`/`deprecated`/`doctor`。含 hvigor/SDK/JAVA_HOME 自动发现、release 签名校验闸、`sideload-*` 变包名状态闸。 |
| `logcat.sh` | hdc hilog 包装。模式：`snap`/`err`/`tag`/`grep`/`stream`/`js`/`clear`，按 `com.twsxtd.hapi` 的 PID 过滤，输出追加到 `debug.log`。 |
| `switch-signing.sh` | 切换 `build-profile.json5` 中 `products[0].signingConfig` 的引用名（`--show` / `--to <name>` / `--allow-debug`）。不创建证书。 |
| `check_release_signing.sh` | 发版前校验闸：读取当前 signingConfig，用 `strings` 解析其 `.p7b` 的 `type`，`release` 必须 `type="release"` 且 `keyAlias != debugKey`。 |
| `check_deprecated_apis.sh` | `rg` 扫描 deprecated API 模式（默认 `getContext(`）。 |
| `setup-hooks.sh` | 一次性把 `core.hooksPath` 指向 `.githooks/`。 |
| `pack.sh` | 侧载包构建（变包名 `com.twsxtd.hapi → com.twsxtd.hapiNN`，默认 `NN=88`）。模式：默认 release `.app` / `hap` debug `.hap` / `all`（debug HAP + release HAP + zip）。含备份/恢复 trap、`.pack.lock`、硬编码包名预检、`output/` 产物拷贝。 |
| `pack_common.sh` | `pack-app-*.sh` 的公共库（被 source，不直接执行）。 |
| `pack-app-release.sh` | 正式包 release `.app`（不变包名，走 `build.sh build`，含 release 签名校验）。 |
| `pack-app-debug.sh` | 正式包 debug `.app`（不变包名，走 `build.sh app-debug`）。 |

`.githooks/pre-commit`：当前为 no-op 占位（hapi 暂无 changelog 闸）。`setup-hooks.sh`
会把它纳入 git hooks 路径；未来需要提交期检查时在此追加逻辑。

## 签名配置（重要）

hapi 的 `build-profile.json5` 当前是 `"signingConfigs": []`、`"signingConfig": ""`（未配置
签名）。**所有 release 构建路径在签名配置好之前都会失败**——这是 `check_release_signing.sh`
的故意行为，防止误用 debug provision 发版。

签名必须**在 DevEco Studio 中**生成（机器本地的加密密码无法跨机器共享、不应入库）：

1. DevEco Studio → **File > Project Structure > Signing Configs**（或 Project Structure >
   Signing Configs）。
2. 勾选 **Automatically generate signature**（调试用自动证书），或手动 **Sign In** 用
   AGC 申请正式 release 证书 + profile（`.p7b`，type须为 release）。
3. 这会在 `build-profile.json5` 的 `signingConfigs[]` 写入配置项（含加密后的密码、本机
   cert 路径）。**不要把这些加密串/路径提交到公共仓库**——它们只在你本机有效。
4. 用 `tools/switch-signing.sh --show` 查看当前引用，`--to <name>` 切换；
   `tools/check_release_signing.sh` 可单独跑一次确认 profile type。

侧载包（`pack.sh`）会临时清空 `signingConfig` 生成未签名产物（调试设备 `hdc install`
可用），并在 trap 中无条件恢复——不涉及正式证书。

## 从 berry3 移植时做了什么

**包名重绑**：所有 `com.berry.browser` → `com.twsxtd.hapi`；`OFFICIAL_BUNDLE`/`BUNDLE`/
`ORIGINAL_BUNDLE` 全部重绑。侧载默认后缀 `88` → `com.twsxtd.hapi88`。

**删除的步骤**（hapi 无对应文件/数据）：
- `AboutPage.ets` 编译日期更新（`update_build_date`）——hapi 无此文件。
- `check_changelog.sh` 发版闸及 `.githooks/pre-commit` 的 changelog 占位模板扫描——
  hapi 无 `changelog.json`；pre-commit 改为 no-op 占位（保留文件，setup-hooks 仍指向它）。
- 共存版应用名改名（`Berry → Berry共存版`）——hapi 仅 `AppScope/app.json5` 硬编码包名，
  `FILES_TO_PATCH` 精简为这一份；label 改名逻辑整体移除。
- berry3 证书路径（`/Users/murongcheng/Documents/密钥/berry-*`）、
  `~/.ohos/config/fabu_berry3_*`、`下载服务器/`、`rawfile/easylist_cn.txt` 等引用——全部剔除。

**保留的通用核心**：hvigor/SDK/JAVA_HOME 自动发现逻辑、`set -euo pipefail`/`trap ... EXIT`
纪律、备份/恢复/锁/预检、release 签名校验、`sideload-*` 状态闸。

**未移植（已跳过）**：
| 脚本/目录 | 原因 |
|---|---|
| `agc-config*.sh`、`agc-publish.sh` | AppGallery Connect 上传，需凭据，进阶 |
| `uitest.sh`、`tools/uitest/` | hmdriver2 python 测试框架，独立运行时 |
| `update_easylist.sh`、`update_json.sh` | 浏览器专属 OTA/easylist |
| `check_changelog.sh` | hapi 无 changelog.json |
| `pack-app-release-88.sh`、`pack-app-debug-88.sh` | `pack.sh` 已支持后缀参数，`-88` 硬编码变体冗余 |
| `tools/aidriver/`、`tools/testserver/`、`tools/tests/` | 进阶，独立运行时 |

## 注意事项

- **hvigor 版本假设**：脚本通过 `hvigorw` / DevEco 自带 `hvigorw.js` 调用，具体版本由
  `hvigor/hvigor-config.json5` 锁定，与这些脚本无关。hapi 当前根目录无 `hvigorw`
  （DevEco 打开项目时生成），`resolve_hvigor_cmd` 会回退到 DevEco 自带的 hvigorw.js。
  跑 `tools/build.sh doctor` 可确认解析结果。
- **HAP 产物路径**：`deploy_and_launch` 期望
  `entry/build/default/outputs/default/entry-default-signed.hap`；`build.sh run` 先编 debug
  HAP 再安装启动。若 entry 模块名/产物名变化，需同步改 `build.sh` 的 `HAP_PATH`。
- **macOS 专属**：`sed -i ''`、`perl -0pi -e`、`/usr/libexec/java_home`、DevEco 的
  `.app/Contents/...` 路径均为 macOS 假设；Linux/Windows 需自行适配（与 berry3 一致）。

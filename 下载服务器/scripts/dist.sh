#!/usr/bin/env bash
# dist.sh — OTA 分发打包：只产 1 个 88 共存 release 包到 output/dist/<版本>_<时间戳>/
#
# 唯一产物：
#   hapi-<版本>-88-release.app   变包名 com.twsxtd.hapi88，release（pack.sh 默认固定后缀 88）
#
# 设计：OTA 只推 88 共存包（正式版走 AGC 应用市场；debug 按需 build.sh app-debug 手打）。
#   故发版只需 88-release 一个包，1 次编译，最快路径。历史 4 包流程已废弃。

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# 读版本号
VERSION=$(sed -n 's/.*"versionName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' AppScope/app.json5 | head -1)
[[ -z "$VERSION" ]] && { echo "✗ 无法读取 AppScope/app.json5 的 versionName"; exit 1; }

STAMP=$(date +%Y%m%d_%H%M)
DIST_DIR="output/dist/${VERSION}_${STAMP}"
# pack.sh 把最终 .app 拷到项目根 output/（pack.sh 的 OUTPUT_DIR），非 hvigor 中间目录 build/outputs/default
APP_OUTPUT="output"

log()  { echo "  $*"; }
ok()   { echo "  ✓ $*"; }
err()  { echo "  ✗ $*" >&2; }
step() { echo ""; echo "── $* ──"; }

mkdir -p "$DIST_DIR" "$APP_OUTPUT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Hapi OTA 分发打包  v${VERSION}  (${STAMP})"
echo "  产物: 88 共存 release ×1（OTA 专用）"
echo "  输出: $DIST_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 唯一阶段：pack.sh 打 88 共存 release（默认固定后缀 88 + release .app，1 次编译）──
step "[1/1] 变包名88 release: tools/pack.sh"
rm -f "$APP_OUTPUT"/*.app 2>/dev/null
if ! tools/pack.sh; then
  err "pack.sh 失败（88 共存 release）"
  err "排查：工作区代码编译不过 / pack.sh 预检命中未覆盖的硬编码包名（见 pack.sh FILES_TO_PATCH/SCAN_WHITELIST）"
  exit 1
fi
RELEASE_APP=$(ls "$APP_OUTPUT"/*.app 2>/dev/null | head -1)
[[ -z "$RELEASE_APP" ]] && { err "未在 $APP_OUTPUT 找到 88-release .app 产物"; exit 1; }
cp "$RELEASE_APP" "$DIST_DIR/hapi-${VERSION}-88-release.app"
ok "88 共存 release: $(du -h "$DIST_DIR/hapi-${VERSION}-88-release.app" | cut -f1)"

# ── 写 manifest.json（OTA 元数据，供 nodebook /hapi-ota/update.json 实时读）──
step "写 manifest.json（含 OTA 元数据）"

# versionCode（同 versionName 提取模式，从 app.json5）
# ⚠️ 用 sed -E（ERE）：BSD sed（macOS）BRE 下 \+ 是字面加号不识别，会导致提取空→兜底 0
VERSION_CODE=$(sed -nE 's/.*"versionCode"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' AppScope/app.json5 | head -1)
[[ -z "$VERSION_CODE" ]] && VERSION_CODE=0

# changelog：hapi 无 changelog.json，固定为空数组（供 OTA 弹窗展示更新日志，将来接 changelog 再改）
CHANGELOG_ITEMS='[]'

# md5（macOS md5 -q / Linux md5sum；小写，与 APP 端 @ohos.file.hash 返回大写后 toLowerCase 对齐）
md5_of() { (command -v md5 >/dev/null 2>&1 && md5 -q "$1") || (command -v md5sum >/dev/null 2>&1 && md5sum "$1" | awk '{print $1}'); }

# bundleName：OTA 升级目标包名，客户端 SelfUpdateManager 校验「下载包 bundleName === 当前包 bundleName」，
#   防 88 包装到非 88 包（服务端推错/归档混入）。固定 com.twsxtd.hapi88（pack.sh 默认 88 后缀）。
OTA_FILE="hapi-${VERSION}-88-release.app"
cat > "$DIST_DIR/manifest.json" <<EOF
{
  "version": "$VERSION",
  "versionCode": $VERSION_CODE,
  "bundleName": "com.twsxtd.hapi88",
  "buildTime": "$(date +%Y-%m-%dT%H:%M:%S)",
  "date": "$(date +%Y-%m-%d)",
  "changelog": $CHANGELOG_ITEMS,
  "files": [
    { "name": "$OTA_FILE", "type": "88共存 release", "size": $(stat -f%z "$DIST_DIR/$OTA_FILE" 2>/dev/null || echo 0), "md5": "$(md5_of "$DIST_DIR/$OTA_FILE")" }
  ]
}
EOF
ok "manifest.json 已写（含 bundleName/versionCode/changelog/md5，供 OTA）"

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ 88 共存 release 包已就绪"
ls -lh "$DIST_DIR"/*.app | awk -v d="$DIST_DIR" '{ print "  →", $NF, $5 }'
echo "  目录: $DIST_DIR"
echo "  下一步: bash 下载服务器/scripts/sync-server.sh   # 上传到下载站"
echo "  ★默认打包即上传：下次直接 bash 下载服务器/scripts/publish.sh（dist+sync 一条命令）"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

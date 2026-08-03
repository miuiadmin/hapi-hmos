#!/usr/bin/env bash
# dist.sh — OTA 分发打包:产 1 个 88 共存 release 包 + manifest.json + 静态 update.json
#
# 新架构(2026-08-03):下载站纯静态化(Caddy file_server),update.json 客户端本地生成(不再服务端算)。
#   manifest.json = 完整构建元数据(归档留档)
#   update.json   = OTA 清单(客户端读它更新),从 manifest 派生:
#       { versionName, versionCode, bundleName, url, md5, size, changelog }
#   url = <PUBLIC_URL>/<APP>/latest.app(绝对,跨版本稳定;服务端 latest.app symlink 指当前包)
#
# 全部 per-app 差异收敛进 config.sh(APP/BUNDLE_NAME/PKG_PREFIX/CHANGELOG_FILE/PROTECT_FILES/BUILD_CMD);
# 本脚本与另一项目(hapi-hmos)的 dist.sh 逐字节一致,改逻辑须同步两边。
#
# PROTECT_FILES(berry 保护 AboutPage.ets):打包前后字节级备份 + trap 恢复。
#   背景:pack.sh 会 sed 改 BUILD_DATE 时间戳且永久写入不恢复 → 备份兜底(不用 git checkout,避免丢并行改动)。

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
cd "$PROJECT_ROOT"

# 首次运行自动从模板创建 config.sh
CONFIG="$SCRIPT_DIR/config.sh"
if [[ ! -f "$CONFIG" ]]; then
  cp "$SCRIPT_DIR/config.example.sh" "$CONFIG"
  echo "  首次运行:已从 config.example.sh 创建 config.sh"
fi
source "$CONFIG"

APP="${APP:?config.sh 缺 APP}"
TITLE="${TITLE:-$APP}"
BUNDLE_NAME="${BUNDLE_NAME:?config.sh 缺 BUNDLE_NAME}"
BUILD_CMD="${BUILD_CMD:-tools/pack.sh}"
APP_JSON="${APP_JSON:-AppScope/app.json5}"
PKG_PREFIX="${PKG_PREFIX:-$APP}"

log()  { echo "  $*"; }
ok()   { echo "  ✓ $*"; }
err()  { echo "  ✗ $*" >&2; }
step() { echo ""; echo "── $* ──"; }

# 读版本号(versionName + versionCode)
# ⚠️ versionCode 用 sed -E(ERE):BSD sed(macOS)BRE 下 \+ 是字面加号,提取空→兜底 0
VERSION=$(sed -n 's/.*"versionName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$APP_JSON" | head -1)
[[ -z "$VERSION" ]] && { err "无法读取 $APP_JSON 的 versionName"; exit 1; }
VERSION_CODE=$(sed -nE 's/.*"versionCode"[[:space:]]*:[[:space:]]*([0-9]+).*/\1/p' "$APP_JSON" | head -1)
[[ -z "$VERSION_CODE" ]] && VERSION_CODE=0

STAMP=$(date +%Y%m%d_%H%M)
DIST_DIR="output/dist/${VERSION}_${STAMP}"
APP_OUTPUT="output"
OTA_FILE="${PKG_PREFIX}-${VERSION}-88-release.app"

# ── PROTECT_FILES:字节备份 + trap 恢复(空/未设 = 无保护)──
BACKUPS=()
protect_restore() {
  local code=$? pair f b
  for pair in "${BACKUPS[@]}"; do
    f="${pair%%|*}"; b="${pair#*|}"
    cp "$b" "$f" 2>/dev/null || err "恢复失败,手动检查: $f"
    rm -f "$b"
  done
  exit "$code"
}
trap protect_restore EXIT INT TERM
for f in "${PROTECT_FILES[@]}"; do
  [[ -z "$f" ]] && continue
  [[ ! -f "$f" ]] && { err "PROTECT_FILES 指定的文件不存在: $f"; exit 1; }
  b="$(mktemp)"; cp "$f" "$b"; BACKUPS+=("$f|$b")
  ok "已保护: $f"
done

mkdir -p "$DIST_DIR" "$APP_OUTPUT"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ${TITLE} OTA 分发打包  v${VERSION}  (${STAMP})"
echo "  产物: 88 共存 release ×1 + update.json(静态 OTA)"
echo "  输出: $DIST_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 打包:经 BUILD_CMD(默认 tools/pack.sh,产 .app 到项目根 output/)──
step "[1/2] 变包名88 release: $BUILD_CMD"
rm -f "$APP_OUTPUT"/*.app 2>/dev/null
if ! bash -c "$BUILD_CMD"; then
  err "$BUILD_CMD 失败"
  err "排查:工作区编译不过 / pack.sh 预检命中未覆盖硬编码包名(见 pack.sh FILES_TO_PATCH/SCAN_WHITELIST)"
  exit 1
fi
RELEASE_APP=$(ls "$APP_OUTPUT"/*.app 2>/dev/null | head -1)
[[ -z "$RELEASE_APP" ]] && { err "未在 $APP_OUTPUT 找到 .app 产物"; exit 1; }
cp "$RELEASE_APP" "$DIST_DIR/$OTA_FILE"
ok "88 共存 release: $(du -h "$DIST_DIR/$OTA_FILE" | cut -f1)"

# ── changelog(可选 CHANGELOG_FILE;无则 [])──
if [[ -n "${CHANGELOG_FILE:-}" && -f "$CHANGELOG_FILE" && -x "$(command -v jq)" ]]; then
  CHANGELOG_ITEMS=$(jq -c '[.releases[0].items[].text]' "$CHANGELOG_FILE" 2>/dev/null || echo '[]')
else
  CHANGELOG_ITEMS='[]'
fi

# ── md5 / size(macOS md5 -q / Linux md5sum;小写,对齐 APP 端 toLowerCase)──
md5_of() { (command -v md5 >/dev/null 2>&1 && md5 -q "$1") || (command -v md5sum >/dev/null 2>&1 && md5sum "$1" | awk '{print $1}'); }
OTA_MD5=$(md5_of "$DIST_DIR/$OTA_FILE")
OTA_SIZE=$(stat -f%z "$DIST_DIR/$OTA_FILE" 2>/dev/null || stat -c%s "$DIST_DIR/$OTA_FILE")

# ── manifest.json(归档元数据)──
step "[2/2] 写 manifest.json + update.json"
PUBLIC_URL="${PUBLIC_URL:-https://berry.flyme.chat:8443}"
cat > "$DIST_DIR/manifest.json" <<EOF
{
  "version": "$VERSION",
  "versionCode": $VERSION_CODE,
  "bundleName": "$BUNDLE_NAME",
  "buildTime": "$(date +%Y-%m-%dT%H:%M:%S)",
  "date": "$(date +%Y-%m-%d)",
  "changelog": $CHANGELOG_ITEMS,
  "files": [
    { "name": "$OTA_FILE", "type": "88共存 release", "size": $OTA_SIZE, "md5": "$OTA_MD5" }
  ]
}
EOF

# ── update.json(静态 OTA 清单,客户端读;url 指 latest.app 跨版本稳定)──
OTA_URL="${PUBLIC_URL}/${APP}/latest.app"
cat > "$DIST_DIR/update.json" <<EOF
{
  "versionName": "$VERSION",
  "versionCode": $VERSION_CODE,
  "bundleName": "$BUNDLE_NAME",
  "url": "$OTA_URL",
  "md5": "$OTA_MD5",
  "size": $OTA_SIZE,
  "changelog": $CHANGELOG_ITEMS
}
EOF
ok "manifest.json + update.json 已写"
ok "update.json.url = $OTA_URL"

# trap 会恢复 PROTECT_FILES
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ 88 共存 release 包 + update.json 就绪"
ls -lh "$DIST_DIR"/*.app | awk '{ print "  →", $NF, $5 }'
echo "  目录: $DIST_DIR"
echo "  下一步: bash 下载服务器/scripts/publish.sh   # 打包+上传一条命令"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

#!/usr/bin/env bash
# sync-server.sh — 把 dist 产物经 rsync over ssh 上传到静态下载站 /opt/dist/<app>/
#
# 新架构(2026-08-03):下载站纯静态化(Caddy file_server),nodebook 退出下载站。
#   上传 = rsync over ssh(经 ~/.ssh/config 的 SSH_TARGET 别名;本机默认 aws = ProxyCommand 经火山92 中继绕 GFW)。
#   归档:<REMOTE_ROOT>/archive/<date>/<version>/{*.app, manifest.json, update.json}
#   提升最新(根层原子,顺序 = 包 → symlink → update.json,保证客户端任何时刻读到的 url→包已就位):
#       <REMOTE_ROOT>/<pkg>、<REMOTE_ROOT>/latest.app -> <pkg>、<REMOTE_ROOT>/update.json
#   清理:脚本侧 prune archive 留最近 KEEP_VERSIONS 个日期(根层最新永不删)。
#
# 全部 per-app 差异收敛进 config.sh;本脚本与另一项目(hapi-hmos)的 sync-server.sh 逐字节一致。
#
# 用法:
#   bash sync-server.sh              # 上传 output/dist/ 下最新目录
#   bash sync-server.sh <dist目录>   # 指定 dist 目录(绝对或相对路径)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 首次运行自动从模板创建 config.sh
CONFIG="$SCRIPT_DIR/config.sh"
if [[ ! -f "$CONFIG" ]]; then
  cp "$SCRIPT_DIR/config.example.sh" "$CONFIG"
  echo "  首次运行:已从 config.example.sh 创建 config.sh"
fi
source "$CONFIG"

APP="${APP:?config.sh 缺 APP}"
TITLE="${TITLE:-$APP}"
PKG_GLOB="${PKG_GLOB:-${APP}-*.app}"
PKG_PREFIX="${PKG_PREFIX:-$APP}"
SSH_TARGET="${SSH_TARGET:-aws}"
REMOTE_ROOT="${REMOTE_ROOT:-/opt/dist/${APP}}"
KEEP_VERSIONS="${KEEP_VERSIONS:-3}"
PUBLIC_URL="${PUBLIC_URL:-https://berry.flyme.chat:8443}"

err() { echo "  ✗ $*" >&2; }

# ── 定位 dist 目录 ──
if [[ -n "${1:-}" ]]; then
  DIST_DIR="$1"
  [[ "$DIST_DIR" != /* ]] && DIST_DIR="$PROJECT_ROOT/$DIST_DIR"
else
  DIST_DIR=$(ls -td "$PROJECT_ROOT"/output/dist/*/ 2>/dev/null | head -1)
fi
DIST_DIR="${DIST_DIR%/}"
if [[ -z "$DIST_DIR" || ! -d "$DIST_DIR" ]]; then
  err "未找到 dist 产物目录,先跑: bash 下载服务器/scripts/dist.sh"
  exit 1
fi

# ── 收集包(nullglob 兼容 macOS bash 3.2)──
shopt -s nullglob
APPS=( "$DIST_DIR"/$PKG_GLOB )
shopt -u nullglob
if [[ ${#APPS[@]} -eq 0 ]]; then
  err "$DIST_DIR 下无 $PKG_GLOB,不是有效的 dist 产物"
  exit 1
fi

PKG=$(basename "${APPS[0]}")
VERSION=$(echo "$PKG" | sed -E "s/^${PKG_PREFIX}-([0-9.]+)-.*/\1/")
[[ -z "$VERSION" ]] && { err "无法从 $PKG 解析版本号"; exit 1; }

# 日期:优先读 update.json/manifest.json 的 date,否则当天
DATE=$(grep -oE '"date"[[:space:]]*:[[:space:]]*"[0-9-]+"' "$DIST_DIR/update.json" "$DIST_DIR/manifest.json" 2>/dev/null \
  | sed -E 's/.*"([0-9-]+)"/\1/' | head -1)
[[ -z "$DATE" ]] && DATE=$(date +%Y-%m-%d)

ARCHIVE="$REMOTE_ROOT/archive/$DATE/$VERSION"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ${TITLE} rsync 上传 → $SSH_TARGET:$ARCHIVE"
echo "  本地: $DIST_DIR(${#APPS[@]} 个包)"
echo "  版本: v$VERSION   日期: $DATE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. 归档历史版本(整个 dist 目录 → archive,含 manifest+update.json)──
# 先建归档目录:rsync 不递归建多层父目录,跨日首次 archive/<date>/ 不存在时
# mkdir 版本子目录会报 "No such file or directory"(兑现 OTA 接入文档 §7/§9 "自动 mkdir" 承诺)
ssh "$SSH_TARGET" "mkdir -p '$ARCHIVE'"
if ! rsync -rltDz --delete -e ssh "$DIST_DIR/" "$SSH_TARGET:$ARCHIVE/"; then
  err "rsync 归档失败(检查 SSH_TARGET 连通性 / 服务器 rsync / 磁盘空间)"
  exit 1
fi
echo "  ✓ 已归档: $ARCHIVE"

# ── 2. 提升为最新(根层原子;顺序:包 → symlink → 清旧 .app → update.json)──
if ! ssh "$SSH_TARGET" "set -e
  mkdir -p '$REMOTE_ROOT'
  cd '$REMOTE_ROOT'
  cp '$ARCHIVE/$PKG' './$PKG'
  ln -sfn '$PKG' latest.app
  # 删根层旧版本 .app(保留当前 \$PKG;latest.app 是 symlink,被 -type f 排除不删)
  find . -maxdepth 1 -type f -name '*.app' ! -name '$PKG' -delete 2>/dev/null || true
  cp '$ARCHIVE/update.json' update.json.new
  mv -f update.json.new update.json
  echo '  ✓ 根层已提升: $PKG + latest.app + update.json'
"; then
  err "提升最新失败"
  exit 1
fi

# ── 3. 清理旧归档(留最近 KEEP_VERSIONS 个日期;根层最新不在此管辖,永不删)──
if [[ "$KEEP_VERSIONS" =~ ^[0-9]+$ && "$KEEP_VERSIONS" -gt 0 ]]; then
  ssh "$SSH_TARGET" python3 -c '
import os,sys,shutil
root=sys.argv[1]; keep=int(sys.argv[2])
try:
    dates=sorted([d for d in os.listdir(root) if os.path.isdir(os.path.join(root,d))], reverse=True)
except FileNotFoundError:
    sys.exit(0)
for old in dates[keep:]:
    shutil.rmtree(os.path.join(root,old), ignore_errors=True)
    print("  prune date", old)
' "$REMOTE_ROOT/archive" "$KEEP_VERSIONS" 2>/dev/null || true
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ✓ ${TITLE} 发布完成"
echo "  OTA 清单: $PUBLIC_URL/$APP/update.json"
echo "  最新包:  $PUBLIC_URL/$APP/latest.app"
echo "  浏览页:  $PUBLIC_URL/$APP/"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

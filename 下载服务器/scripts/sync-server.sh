#!/usr/bin/env bash
# sync-server.sh — 把 dist.sh 产出的 88-release 包经 HTTP 接口上传到下载站归档
#
# 用法：
#   bash sync-server.sh              # 上传 output/dist/ 下最新目录
#   bash sync-server.sh <dist目录>   # 指定 dist 目录（绝对或相对路径）
#
# 上传到：<FILES_ROOT>/<日期>/<版本>/  （FILES_ROOT 在服务端 nodebook-rs，= /opt/hapi-dist/files/archive）
# 日期 = 构建当天；版本 = 从文件名 hapi-<版本>-*.app 解析
#
# 改造自 berry sync-server.sh：HTTP POST /hapi/upload（零 SSH 依赖，任何机器/CI 拿到 token 即可发版）。
#   · 传 manifest.json → 服务端校验每个包 md5（不符 422，防传坏）
#   · ?force=1 → 覆盖同名版本（等价旧 rsync --delete 重发同版本）
#   · uploaded.json 服务端自动写（标 via:http-upload）
#   · 旧版本清理（KEEP_VERSIONS）：?keep=N 让服务端上传后按全局最新优先保留 N 个、删更早的

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 首次运行自动从模板创建 config.sh
CONFIG="$SCRIPT_DIR/config.sh"
if [[ ! -f "$CONFIG" ]]; then
  cp "$SCRIPT_DIR/config.example.sh" "$CONFIG"
  echo "  首次运行：已从 config.example.sh 创建 config.sh"
fi
source "$CONFIG"

err() { echo "  ✗ $*" >&2; }

# 校验 token
if [[ -z "$TOKEN" ]]; then
  err "config.sh 的 TOKEN 为空——手动编辑填入: $CONFIG"
  exit 1
fi
# PUBLIC_URL 兜底（= https://<SERVER_HOST>:8443）
BASE="${PUBLIC_URL:-https://${SERVER_HOST}:8443}"

# 定位 dist 目录
if [[ -n "${1:-}" ]]; then
  DIST_DIR="$1"
  [[ "$DIST_DIR" != /* ]] && DIST_DIR="$PROJECT_ROOT/$DIST_DIR"
else
  DIST_DIR=$(ls -td "$PROJECT_ROOT"/output/dist/*/ 2>/dev/null | head -1)
fi
DIST_DIR="${DIST_DIR%/}"
if [[ -z "$DIST_DIR" || ! -d "$DIST_DIR" ]]; then
  err "未找到 dist 产物目录，先跑: bash 下载服务器/scripts/dist.sh"
  exit 1
fi

# 收集 .app 包（可能有多个；用 nullglob 兼容 macOS bash 3.2，无 mapfile）
shopt -s nullglob
APPS=( "$DIST_DIR"/hapi-*.app )
shopt -u nullglob
if [[ ${#APPS[@]} -eq 0 ]]; then
  err "$DIST_DIR 下无 hapi-*.app，不是有效的 dist 产物"
  exit 1
fi
LOCAL_COUNT=${#APPS[@]}

# 从文件名解析版本（hapi-<版本>-*.app）
FIRST_APP="${APPS[0]}"
VERSION=$(basename "$FIRST_APP" | sed -E 's/^hapi-([0-9.]+)-.*/\1/')
[[ -z "$VERSION" ]] && { err "无法从文件名解析版本号: $FIRST_APP"; exit 1; }

# 日期：优先读 manifest.json 的 date，否则用当天
DATE=$(grep -oE '"date"[[:space:]]*:[[:space:]]*"[0-9-]+"' "$DIST_DIR/manifest.json" 2>/dev/null \
  | sed -E 's/.*"([0-9-]+)"/\1/')
[[ -z "$DATE" ]] && DATE=$(date +%Y-%m-%d)

UPLOAD_URL="${BASE}/hapi/upload?t=${TOKEN}&force=1"
# KEEP_VERSIONS>0 时传 ?keep=N 让服务端上传后自动清理旧版（0/空 = 用服务端默认）
if [[ "${KEEP_VERSIONS:-0}" =~ ^[0-9]+$ && "$KEEP_VERSIONS" -gt 0 ]]; then
  UPLOAD_URL="${UPLOAD_URL}&keep=${KEEP_VERSIONS}"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  HTTP 上传（POST /hapi/upload）"
echo "  本地: $DIST_DIR（$LOCAL_COUNT 个包）"
echo "  接口: $UPLOAD_URL"
echo "  版本: v$VERSION   日期: $DATE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 组装 multipart：每个 .app 一个 file 字段 + manifest（有则带，服务端校验 md5）+ version/date 兜底 ──
UPLOAD_ARGS=(-X POST "$UPLOAD_URL" -m 180 --connect-timeout 15)
for app in "${APPS[@]}"; do
  [[ -z "$app" ]] && continue
  UPLOAD_ARGS+=(-F "file=@${app}")
  echo "  · $(basename "$app")"
done
if [[ -f "$DIST_DIR/manifest.json" ]]; then
  UPLOAD_ARGS+=(-F "manifest=@${DIST_DIR}/manifest.json;type=application/json")
  echo "  · manifest.json（md5 校验）"
fi
UPLOAD_ARGS+=(-F "version=${VERSION}" -F "date=${DATE}")

# ── 上传：抓 HTTP code + body ──
RESP_FILE=$(mktemp)
trap 'rm -f "$RESP_FILE"' EXIT
HTTP_CODE=$(curl -sS -o "$RESP_FILE" -w "%{http_code}" "${UPLOAD_ARGS[@]}" 2>&1) || {
  # curl 自身失败（连接超时/DNS/网络）—— HTTP_CODE 此时含错误串
  err "上传请求失败: $HTTP_CODE"
  err "响应: $(cat "$RESP_FILE" 2>/dev/null)"
  exit 1
}

echo ""
if [[ "$HTTP_CODE" != "200" ]]; then
  err "上传失败 HTTP $HTTP_CODE"
  err "服务端响应: $(cat "$RESP_FILE" 2>/dev/null | head -c 500)"
  # 常见错误码提示
  case "$HTTP_CODE" in
    401) err "→ token 错误（检查 config.sh TOKEN 与服务端 HAPI_TOKEN 一致）";;
    409) err "→ 版本已存在且未带 force=1（脚本已默认 force=1，若仍 409 检查 URL）";;
    413) err "→ 包过大（服务端上限 200MB）";;
    422) err "→ md5 校验失败（manifest 里 md5 与实际上传文件不符，重新 dist 打包）";;
    502|503) err "→ 服务端未就绪（重启中？稍等 ≥3s 重试）";;
  esac
  exit 1
fi

# ── 解析响应：以服务端返回的权威 version/date 为准（= manifest 里的值）拼 URL，避免文件名解析与 manifest 版本不一致时 URL 错 ──
REMOTE_COUNT=$(grep -oE '"name"[[:space:]]*:[[:space:]]*"[^"]+\.app"' "$RESP_FILE" | wc -l | tr -d ' ')
UPLOADED_AT=$(grep -oE '"uploaded"[[:space:]]*:[[:space:]]*"[^"]+"' "$RESP_FILE" | sed -E 's/.*"([^"]+)"$/\1/')
SVER=$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$RESP_FILE" | head -1 | sed -E 's/.*:"([^"]+)".*/\1/')
SDATE=$(grep -oE '"date"[[:space:]]*:[[:space:]]*"[0-9-]+"' "$RESP_FILE" | head -1 | sed -E 's/.*"([0-9-]+)".*/\1/')
[[ -n "$SVER" ]] && VERSION="$SVER"
[[ -n "$SDATE" ]] && DATE="$SDATE"
HOME_URL="${BASE}/hapi?t=$TOKEN"
DIRECT_URL="${BASE}/hapi/history/$DATE/$VERSION?t=$TOKEN"
# 服务端清理结果（prune 对象:null=未清理/keep=0;否则 {kept,total,deleted,failed}）
PRUNE_DEL=$(grep -oE '"deleted"[[:space:]]*:[[:space:]]*[0-9]+' "$RESP_FILE" | head -1 | grep -oE '[0-9]+$')
PRUNE_TOTAL=$(grep -oE '"total"[[:space:]]*:[[:space:]]*[0-9]+' "$RESP_FILE" | head -1 | grep -oE '[0-9]+$')

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [[ "$REMOTE_COUNT" == "$LOCAL_COUNT" ]]; then
  echo "  ✓ 上传完成（$REMOTE_COUNT 个包）"
else
  echo "  ⚠ 上传可能不完整（本地 $LOCAL_COUNT，服务端确认 $REMOTE_COUNT）"
fi
[[ -n "$UPLOADED_AT" ]] && echo "  ✓ 记录上传时间: $UPLOADED_AT"
if [[ -n "$PRUNE_TOTAL" ]]; then
  if [[ "${PRUNE_DEL:-0}" == "0" ]]; then
    echo "  ✓ 服务端清理:共 $PRUNE_TOTAL 版无需清理"
  else
    echo "  ✓ 服务端清理:删除 ${PRUNE_DEL} 个旧版（共 $PRUNE_TOTAL，留最新 KEEP）"
  fi
fi
echo "  下载页（首页）: $HOME_URL"
echo "  该版本直链页:   $DIRECT_URL"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 旧版本清理(KEEP_VERSIONS)= 服务端 /hapi/upload 成功后自动做 ──
# KEEP_VERSIONS(config.sh,默认 3)>0 时本脚本传 ?keep=N,服务端按全局最新优先保留 N 个、删更早的,
# 刚上传版本双重保护绝不删。响应 JSON 的 prune 字段回传 {kept,total,deleted,failed},上面已回显。
# KEEP_VERSIONS=0/空 → 不传 keep,用服务端 .env KEEP_VERSIONS 默认。
true

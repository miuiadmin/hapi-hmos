#!/usr/bin/env bash
# publish.sh — 一键发布:dist.sh 打包 + sync-server.sh 上传
#
# 阶段1 dist.sh  → 产 88-release 1 个 .app + manifest.json + 静态 update.json
# 阶段2 sync     → rsync 上传到静态站 /opt/dist/<app>/archive + 根层提升为最新
# dist 失败则不 sync(避免上传半成品)。
#
# 全部 per-app 差异收敛进 config.sh;本脚本与另一项目(hapi-hmos)的 publish.sh 逐字节一致。
#
# 用法:
#   bash publish.sh                # 打最新版并上传
#   bash publish.sh <dist目录>     # 跳过 dist,直接上传指定目录(透传给 sync)

set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.sh" 2>/dev/null || true
TITLE="${TITLE:-App}"

# 透传参数:有 $1 = 指定 dist 目录(跳过 dist 阶段,直接 sync);无 = 完整打包+上传
if [[ -n "${1:-}" ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ${TITLE} 发布(跳过打包,直接上传指定目录)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  bash "$SCRIPT_DIR/sync-server.sh" "$1"
  exit $?
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  ${TITLE} 一键发布(打包 + 上传)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 阶段1:打包
bash "$SCRIPT_DIR/dist.sh" || {
  echo ""
  echo "  ✗ 打包失败,已中止(不会上传半成品)"
  echo "  排查:看上方编译错误;通常是工作区代码编译不过"
  exit 1
}

echo ""

# 阶段2:上传
bash "$SCRIPT_DIR/sync-server.sh" || {
  echo ""
  echo "  ✗ 上传失败"
  echo "  排查:SSH 连通性(aws 别名)/ 服务器 rsync / 磁盘空间(详见 sync-server.sh 输出)"
  exit 1
}

# ── 阶段3:发版后一致性校验(2026-09-20 workflow P1 复盘加,与 check_changelog.sh 同一卡点思路) ──
# 防「发版后又追加条目」三方不一致:服务器 update.json 的 changelog 条数须 == 本地 releases[0].items.length。
# 不一致通常 = 发版后本地 changelog.json 又改过(线上升级弹窗永远看不到新条目)→ 历史不可改,收口到下版 bump。
# 注:上传已完成,本校验失败不代表发版失败,是强制人工确认口径;透传分支(旧 dist 目录)不做此校验(本地早已改过必误报)。
echo ""
if [[ -z "${CHANGELOG_FILE:-}" ]]; then
  echo "  ── 发版后一致性校验:CHANGELOG_FILE 未设,跳过(本项目无 changelog.json) ──"
else
  echo "  ── 发版后一致性校验 ──"
  PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
  REMOTE_N=$(curl -sf --max-time 15 "$PUBLIC_URL/$APP/update.json" | jq '.changelog | length' 2>/dev/null)
  LOCAL_N=$(jq '.releases[0].items | length' "$PROJECT_ROOT/$CHANGELOG_FILE" 2>/dev/null)
  if [[ -z "${REMOTE_N:-}" ]]; then
    echo "  ⚠ 无法读取服务器 update.json(网络/CF?),跳过条数比对(本地 releases[0] 共 ${LOCAL_N:-?} 条)"
  elif [[ "$REMOTE_N" != "$LOCAL_N" ]]; then
    echo "  ✗ 校验不一致: 服务器 changelog ${REMOTE_N} 条 vs 本地 releases[0] ${LOCAL_N:-?} 条"
    echo "  含义: 本地 changelog.json 与刚上传的 update.json 不同步(发版后又改过本地?)"
    echo "  处理: 历史版本已发布不可改,新条目收口到下版 bump 时补录;确信无误可忽略"
    exit 1
  else
    echo "  ✓ 校验通过: changelog 条数一致(${LOCAL_N} 条)"
  fi
fi

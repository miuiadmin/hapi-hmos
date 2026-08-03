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

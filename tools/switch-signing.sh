#!/usr/bin/env bash
# tools/switch-signing.sh — 显式切换签名配置
#
# 移植自 berry3/tools/switch-signing.sh，逻辑通用（直接操作 build-profile.json5）。
#
# ⚠ 前置条件：签名配置须先在 DevEco Studio 中生成（Project Structure > Signing Configs）。
#   本脚本只切换 products[0].signingConfig 的「引用名」，不创建/导入证书；
#   加密密码与证书路径是机器本地配置，无法跨机器共享，请勿提交入库。
#   典型配置名：default（release）、fabu/debug（调试分发），由你在 DevEco 中命名。
#
# 功能：
#   切换 build-profile.json5 中 products[0].signingConfig 的引用值，
#   不再做 default↔fabu 隐式互换，避免误把 debug provision 当 release 发布。
#   signingConfigs 数组本身不做任何变动。
#
# 用法：
#   tools/switch-signing.sh --show   # 仅显示当前状态，不做修改
#   tools/switch-signing.sh --to default
#   tools/switch-signing.sh --to fabu --allow-debug

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_PROFILE="$PROJECT_ROOT/build-profile.json5"

if [[ ! -f "$BUILD_PROFILE" ]]; then
  echo "错误: 找不到 build-profile.json5"
  exit 1
fi

# 读取当前 signingConfig 值
CURRENT=$(grep '"signingConfig"' "$BUILD_PROFILE" | head -1 \
  | sed 's/.*"signingConfig"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')

if [[ -z "$CURRENT" ]]; then
  echo "错误: 无法读取 signingConfig（当前为空——若尚未在 DevEco 配置签名，请先配置后再切换）"
  exit 1
fi

read_key_alias() {
  local name="$1"
  awk -v name="$name" '
    index($0, "\"name\": \"" name "\"") { in_block = 1 }
    in_block && index($0, "\"keyAlias\"") { print; exit }
  ' "$BUILD_PROFILE" | sed 's/.*"keyAlias"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/'
}

show_current() {
  local alias
  alias=$(read_key_alias "$CURRENT")
  echo "当前签名配置: $CURRENT"
  echo "  keyAlias: ${alias:-<unknown>}"
  if [[ "$alias" == "debugKey" ]]; then
    echo "  → debug provision（禁止用于正式 release）"
  else
    echo "  → 非 debugKey（正式 release 仍以 tools/check_release_signing.sh 校验 profile type 为准）"
  fi
}

if [[ "${1:-}" == "--show" || "${1:-}" == "-s" || $# -eq 0 ]]; then
  show_current
  if [[ $# -eq 0 ]]; then
    echo ""
    echo "提示: 为避免误切到 debug 签名，本脚本不再默认 toggle；请使用 --to <name> 显式指定。"
  fi
  exit 0
fi

TARGET=""
ALLOW_DEBUG=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --to)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        echo "错误: 缺少 --to <signingConfig>"
        exit 1
      fi
      TARGET="${2:-}"
      shift 2
      ;;
    --allow-debug)
      ALLOW_DEBUG=1
      shift
      ;;
    *)
      echo "错误: 未知参数 $1"
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET" ]]; then
  echo "错误: 缺少 --to <signingConfig>"
  exit 1
fi

TARGET_ALIAS=$(read_key_alias "$TARGET")
if [[ -z "$TARGET_ALIAS" ]]; then
  echo "错误: signingConfig='$TARGET' 不存在或无法读取 keyAlias"
  echo "       请先在 DevEco Studio > Project Structure > Signing Configs 创建该配置。" >&2
  exit 1
fi
if [[ "$TARGET_ALIAS" == "debugKey" && "$ALLOW_DEBUG" != "1" ]]; then
  echo "错误: signingConfig='$TARGET' 使用 debugKey，禁止默认切换；如确为调试用途，请加 --allow-debug"
  exit 1
fi

# 只替换 "signingConfig": "xxx" 这一处
sed -i '' "s/\"signingConfig\": \"${CURRENT}\"/\"signingConfig\": \"${TARGET}\"/" "$BUILD_PROFILE"

echo "========================================"
echo "  签名配置已切换"
echo "========================================"
echo "  $CURRENT → $TARGET"
echo "  target keyAlias: $TARGET_ALIAS"
echo "========================================"

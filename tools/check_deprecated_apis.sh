#!/usr/bin/env bash
# tools/check_deprecated_apis.sh - Deprecated API 扫描
#
# 移植自 berry3/tools/check_deprecated_apis.sh，逐字保留（逻辑完全通用）。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TARGET_DIR="${1:-$PROJECT_ROOT/entry/src/main/ets}"

if [[ ! -d "$TARGET_DIR" ]]; then
  echo "错误: 目录不存在: $TARGET_DIR"
  exit 2
fi

declare -a RULES=(
  "getContext\\("
)

echo "扫描目录: $TARGET_DIR"
echo "规则数量: ${#RULES[@]}"
echo ""

total_hits=0
for pattern in "${RULES[@]}"; do
  echo "[规则] $pattern"
  # rg 无匹配时返回 1，这里不让脚本退出
  set +e
  output="$(rg -n "$pattern" "$TARGET_DIR")"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    echo "$output"
    hits=$(echo "$output" | wc -l | tr -d ' ')
    total_hits=$((total_hits + hits))
    echo "命中: $hits"
  else
    echo "命中: 0"
  fi
  echo ""
done

if [[ $total_hits -gt 0 ]]; then
  echo "失败: 共发现 $total_hits 处 deprecated API 使用。"
  exit 1
fi

echo "通过: 未发现 deprecated API 使用。"

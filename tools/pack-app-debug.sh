#!/usr/bin/env bash
# tools/pack-app-debug.sh — 正式包 debug .app
#
# 移植自 berry3/tools/pack-app-debug.sh，适配 hapi（com.twsxtd.hapi）。
#
# 正式包名 com.twsxtd.hapi，debug .app（开 TestBridge/CDP 调试闸）。
# 即 build.sh app-debug 的命名化封装，纳入 pack-app-* 统一系列。
# 用于正式包调试 / 自动化测试。不变包名、不清签名。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
用法: tools/pack-app-debug.sh

正式包 com.twsxtd.hapi + debug .app（开 TestBridge/CDP 调试闸）。
不变包名、不清签名，直接 build.sh app-debug（assembleApp debug）。

流程：
  1. build.sh app-debug（assembleApp debug）
  2. 拷贝 .app 到 output/

输出：
  output/<版本>_APP_DEBUG_<时间戳>.app
EOF
  exit 0
fi

# 公共库配置：正式包（SUFFIX 空=不变包名）+ debug
SUFFIX=
BUILD_CMD=app-debug
LABEL=APP_DEBUG
PREFIX=

source "$SCRIPT_DIR/pack_common.sh"
run_pack

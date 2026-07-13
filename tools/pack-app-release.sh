#!/usr/bin/env bash
# tools/pack-app-release.sh — 正式包 release .app
#
# 移植自 berry3/tools/pack-app-release.sh，适配 hapi（com.twsxtd.hapi）。
#
# 正式包名 com.twsxtd.hapi，release .app（带正式签名校验：release 签名）。
# 即 build.sh build 的命名化封装，纳入 pack-app-* 统一系列。
# 用于正式发版 / 归档。不变包名、不清签名。
#
# ⚠ 前置：须先在 DevEco Studio > Project Structure > Signing Configs 生成 release
#   签名配置（如 default），否则 build.sh build 内的 check_release_signing.sh 会失败。

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
用法: tools/pack-app-release.sh

正式包 com.twsxtd.hapi + release .app（带正式签名校验）。
不变包名、不清签名，直接 build.sh build（含 release-signing 强校验）。

流程：
  1. build.sh build（release 签名校验 + assembleApp release）
  2. 拷贝签名 .app 到 output/

输出：
  output/<版本>_APP_<时间戳>_signed.app（带正式签名）
EOF
  exit 0
fi

# 公共库配置：正式包（SUFFIX 空=不变包名）+ release
SUFFIX=
BUILD_CMD=build
LABEL=APP
PREFIX=

source "$SCRIPT_DIR/pack_common.sh"
run_pack

#!/usr/bin/env bash
# 校验 release 构建不能误用 debug provision。
#
# 移植自 berry3/tools/check_release_signing.sh，逻辑通用。
# 读取 build-profile.json5 中 products[0].signingConfig 引用，打开其 .p7b profile
# 用 strings 解析 type 字段：release 必须为 type="release" 且 keyAlias != debugKey。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_PROFILE="$PROJECT_ROOT/build-profile.json5"

fail() {
  echo "✗ release 签名校验失败: $*" >&2
  exit 1
}

if [[ ! -f "$BUILD_PROFILE" ]]; then
  fail "找不到 build-profile.json5"
fi

SIGNING_CONFIG="$(sed -n 's/.*"signingConfig"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$BUILD_PROFILE" | head -n 1)"

if [[ -z "$SIGNING_CONFIG" ]]; then
  if [[ "${HAPI_ALLOW_UNSIGNED_RELEASE:-0}" == "1" ]]; then
    fail "HAPI_ALLOW_UNSIGNED_RELEASE 已废弃，不能绕过 release 签名校验；侧载包必须通过 tools/pack.sh 生成"
  else
    fail "当前 products[0].signingConfig 为空。正式 release 必须使用 release provision；侧载包必须通过 tools/pack.sh 生成"
  fi
fi

PROFILE_LINE="$(awk -v name="$SIGNING_CONFIG" '
  index($0, "\"name\": \"" name "\"") { in_block = 1 }
  in_block && index($0, "\"profile\"") { print; exit }
' "$BUILD_PROFILE")"
KEY_ALIAS_LINE="$(awk -v name="$SIGNING_CONFIG" '
  index($0, "\"name\": \"" name "\"") { in_block = 1 }
  in_block && index($0, "\"keyAlias\"") { print; exit }
' "$BUILD_PROFILE")"

PROFILE_PATH="$(printf '%s\n' "$PROFILE_LINE" | sed -n 's/.*"profile"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
KEY_ALIAS="$(printf '%s\n' "$KEY_ALIAS_LINE" | sed -n 's/.*"keyAlias"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

if [[ -z "$PROFILE_PATH" ]]; then
  fail "无法从 signingConfig='$SIGNING_CONFIG' 读取 profile 路径"
fi
if [[ ! -f "$PROFILE_PATH" ]]; then
  fail "profile 文件不存在: $PROFILE_PATH"
fi
if [[ "$KEY_ALIAS" == "debugKey" ]]; then
  fail "signingConfig='$SIGNING_CONFIG' 使用 debugKey，禁止用于 release"
fi

PROFILE_TYPE="$(strings "$PROFILE_PATH" 2>/dev/null | sed -n 's/.*"type":"\([^"]*\)".*/\1/p' | head -n 1)"
if [[ -z "$PROFILE_TYPE" ]]; then
  fail "无法从 profile 读取 type 字段: $PROFILE_PATH"
fi
if [[ "$PROFILE_TYPE" != "release" ]]; then
  fail "signingConfig='$SIGNING_CONFIG' 的 profile type='$PROFILE_TYPE'，release 必须为 type='release'"
fi

echo "✓ release 签名校验通过: signingConfig=$SIGNING_CONFIG profileType=$PROFILE_TYPE"

#!/usr/bin/env bash
# tools/build.sh - Hapi 项目编译脚本
#
# 移植自 berry3/tools/build.sh，适配 hapi 身份（com.twsxtd.hapi）。
# 已移除：AboutPage 编译日期更新（hapi 无 AboutPage.ets）、check_changelog 闸（hapi 无 changelog.json）。
# 保留：hvigor/SDK/JAVA_HOME 自动发现、release 签名校验、sideload 变包名状态闸。

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
SCRIPT_NAME="$(basename "$0")"

PROJECT_HVIGORW="$PROJECT_ROOT/hvigorw"
DEVECO_APP_MAC_DEFAULT="/Applications/DevEco-Studio.app"
DEVECO_HOME_EFFECTIVE="${DEVECO_HOME:-$DEVECO_APP_MAC_DEFAULT}"
OFFICIAL_BUNDLE="com.twsxtd.hapi"

# 默认禁用 daemon，避免 daemon 锁文件导致构建失败
HVIGOR_NO_DAEMON="${HVIGOR_NO_DAEMON:-1}"

HVIGOR_CMD=()
HVIGOR_DESC=""
SDK_DESC=""
JAVA_DESC=""

cd "$PROJECT_ROOT"

usage() {
  cat <<EOF
用法: $SCRIPT_NAME [命令] [额外 hvigor 参数]

命令:
  build        编译 APP（release，默认）      → build/outputs/default/*.app
  release      编译 release 版 APP（同 build）
  debug        编译 debug 版 HAP              → entry/build/.../entry-default-*.hap
  app-debug    编译 debug 版 APP              → build/outputs/default/*.app
  hap-release  编译 release 版 HAP            → entry/build/.../entry-default-*.hap
  run          编译 + 安装 + 启动应用（一键部署）
  install      仅安装已编译的 HAP + 启动应用
  clean        清理构建产物
  lint         运行 deprecated 扫描 + hvigor lint
  deprecated   仅扫描 deprecated API 使用
  doctor       输出 hvigor 运行环境诊断信息
  -h, --help   显示帮助

  build / release / app-debug / debug / hap-release 五者组合出
  app×{release,debug} + hap×{release,debug} 四种产物，pack.sh all 全量打包用到。

环境变量:
  HVIGOR_NO_DAEMON=1|0   1: 默认追加 --no-daemon（默认 1）
  HVIGOR_USER_HOME=PATH  指定 hvigor 用户目录
  DEVECO_HOME=PATH       指定 DevEco Studio 安装目录
  release 签名校验不可通过环境变量绕过；变包名侧载包请使用 tools/pack.sh

示例:
  tools/build.sh build --stacktrace
  tools/build.sh debug --parallel
  HVIGOR_NO_DAEMON=0 tools/build.sh build
EOF
}

resolve_hvigor_cmd() {
  local deveco_hvigor_js="${DEVECO_HOME_EFFECTIVE}/Contents/tools/hvigor/bin/hvigorw.js"
  local deveco_node="${DEVECO_HOME_EFFECTIVE}/Contents/tools/node/bin/node"

  if [[ -f "$PROJECT_HVIGORW" ]]; then
    if [[ -x "$PROJECT_HVIGORW" ]]; then
      HVIGOR_CMD=("$PROJECT_HVIGORW")
      HVIGOR_DESC="project hvigorw"
    else
      HVIGOR_CMD=("bash" "$PROJECT_HVIGORW")
      HVIGOR_DESC="project hvigorw (via bash)"
    fi
    return
  fi

  if command -v hvigorw >/dev/null 2>&1; then
    HVIGOR_CMD=("hvigorw")
    HVIGOR_DESC="global hvigorw"
    return
  fi

  if command -v hvigor >/dev/null 2>&1; then
    HVIGOR_CMD=("hvigor")
    HVIGOR_DESC="global hvigor"
    return
  fi

  if [[ -f "$deveco_hvigor_js" ]]; then
    if [[ -x "$deveco_node" ]]; then
      HVIGOR_CMD=("$deveco_node" "$deveco_hvigor_js")
      HVIGOR_DESC="DevEco hvigorw.js + DevEco node"
      return
    fi
    if command -v node >/dev/null 2>&1; then
      HVIGOR_CMD=("node" "$deveco_hvigor_js")
      HVIGOR_DESC="DevEco hvigorw.js + system node"
      return
    fi
  fi

  echo "错误: 未找到可用的 hvigor 运行器。"
  echo "请检查："
  echo "  1) 项目根目录是否存在 hvigorw"
  echo "  2) 是否可用全局命令 hvigorw/hvigor"
  echo "  3) DevEco Studio 路径是否正确（当前: $DEVECO_HOME_EFFECTIVE）"
  exit 1
}

resolve_sdk_env() {
  local sdk_from_local=""
  if [[ -f "$PROJECT_ROOT/local.properties" ]]; then
    # local.properties 常见字段：sdk.dir=/path/to/sdk
    sdk_from_local="$(sed -n 's/^sdk\.dir=\(.*\)$/\1/p' "$PROJECT_ROOT/local.properties" | head -n 1)"
  fi

  local current_sdk="${DEVECO_SDK_HOME:-}"
  if [[ -n "$current_sdk" && -d "$current_sdk" ]]; then
    SDK_DESC="DEVECO_SDK_HOME(env)"
    return
  fi

  local -a sdk_candidates=()
  if [[ -n "$sdk_from_local" ]]; then
    sdk_candidates+=("$sdk_from_local")
  fi
  if [[ -n "${OHOS_SDK_HOME:-}" ]]; then
    sdk_candidates+=("${OHOS_SDK_HOME}")
  fi
  sdk_candidates+=("${DEVECO_HOME_EFFECTIVE}/Contents/sdk")
  sdk_candidates+=("${DEVECO_APP_MAC_DEFAULT}/Contents/sdk")

  local candidate=""
  for candidate in "${sdk_candidates[@]}"; do
    if [[ -n "$candidate" && -d "$candidate" ]]; then
      export DEVECO_SDK_HOME="$candidate"
      SDK_DESC="auto-detected"
      return
    fi
  done
}

resolve_java_env() {
  # 优先使用已配置且有效的 JAVA_HOME
  if [[ -n "${JAVA_HOME:-}" && -x "${JAVA_HOME}/bin/java" ]]; then
    JAVA_DESC="JAVA_HOME(env)"
    return
  fi

  local deveco_java_home="${DEVECO_HOME_EFFECTIVE}/Contents/jbr/Contents/Home"
  if [[ -x "${deveco_java_home}/bin/java" ]]; then
    export JAVA_HOME="${deveco_java_home}"
    export PATH="${JAVA_HOME}/bin:${PATH}"
    JAVA_DESC="DevEco JBR"
    return
  fi

  # macOS: 尝试系统 java_home
  if command -v /usr/libexec/java_home >/dev/null 2>&1; then
    local detected_java_home=""
    set +e
    detected_java_home="$(/usr/libexec/java_home 2>/dev/null)"
    set -e
    if [[ -n "$detected_java_home" && -x "${detected_java_home}/bin/java" ]]; then
      export JAVA_HOME="${detected_java_home}"
      export PATH="${JAVA_HOME}/bin:${PATH}"
      JAVA_DESC="macOS java_home"
      return
    fi
  fi

  JAVA_DESC="not found"
}

run_hvigor() {
  resolve_java_env
  resolve_sdk_env
  resolve_hvigor_cmd
  local hvigor_args=("$@")
  if [[ "$HVIGOR_NO_DAEMON" == "1" ]]; then
    hvigor_args+=("--no-daemon")
  fi
  "${HVIGOR_CMD[@]}" "${hvigor_args[@]}"
}

# 注：berry3 在此更新 AboutPage 编译日期；hapi 无 AboutPage.ets，该步骤已移除。
# hapi 暂无 changelog.json，故 check_changelog.sh 发版闸也已移除（如未来加入 changelog，
# 在此处重新接入 bash "$PROJECT_ROOT/tools/check_changelog.sh" 即可）。

run_build() {
  # 发版强制校验：release 不能误用 debug provision，否则 TestBridge/CDP debug 闸会被打开
  bash "$PROJECT_ROOT/tools/check_release_signing.sh"
  run_hvigor assembleApp -p buildMode=release "$@"
}

run_release_hap() {
  bash "$PROJECT_ROOT/tools/check_release_signing.sh"
  run_hvigor assembleHap -p buildMode=release "$@"
}

assert_sideload_release_state() {
  local app_profile="$PROJECT_ROOT/AppScope/app.json5"
  local build_profile="$PROJECT_ROOT/build-profile.json5"
  local bundle_name
  local signing_config

  bundle_name="$(sed -n 's/.*"bundleName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$app_profile" | head -n 1)"
  signing_config="$(sed -n 's/.*"signingConfig"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$build_profile" | head -n 1)"

  if [[ -z "$bundle_name" ]]; then
    echo "错误: 无法读取 AppScope/app.json5 bundleName，拒绝跳过 release 签名校验" >&2
    exit 1
  fi
  if [[ "$bundle_name" == "$OFFICIAL_BUNDLE" ]]; then
    echo "错误: sideload-release 只能用于 pack.sh 变包名产物，正式包名禁止跳过 release 签名校验" >&2
    exit 1
  fi
  if [[ -n "$signing_config" ]]; then
    echo "错误: sideload-release 只允许 signingConfig 为空的侧载产物，正式签名产物必须走 build/release/hap-release" >&2
    exit 1
  fi
}

run_sideload_release_app() {
  assert_sideload_release_state
  echo "⚠ 侧载 release APP 构建：跳过正式 release 签名校验（仅供 tools/pack.sh 变包名未签名产物使用）"
  run_hvigor assembleApp -p buildMode=release "$@"
}

run_sideload_release_hap() {
  assert_sideload_release_state
  echo "⚠ 侧载 release HAP 构建：跳过正式 release 签名校验（仅供 tools/pack.sh 变包名未签名产物使用）"
  run_hvigor assembleHap -p buildMode=release "$@"
}

# HDC 路径与包名
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
BUNDLE="com.twsxtd.hapi"
HAP_PATH="$PROJECT_ROOT/entry/build/default/outputs/default/entry-default-signed.hap"
DEVICE_TMP="/data/local/tmp/entry-default-signed.hap"

# 安装 HAP 到设备并启动应用
deploy_and_launch() {
  if [[ ! -x "$HDC" ]]; then
    echo "错误: 未找到 hdc: $HDC" >&2; exit 1
  fi
  if [[ ! -f "$HAP_PATH" ]]; then
    echo "错误: HAP 包不存在: $HAP_PATH" >&2
    echo "请先执行 build 编译" >&2; exit 1
  fi

  echo "── 传输 HAP 到设备 ──"
  "$HDC" file send "$HAP_PATH" "$DEVICE_TMP"

  echo "── 安装 HAP ──"
  "$HDC" shell "bm install -p $DEVICE_TMP"

  echo "── 启动应用 ──"
  "$HDC" shell "aa start -a EntryAbility -b $BUNDLE"

  echo "✓ 部署完成，应用已启动"
}

run_deprecated_check() {
  "$PROJECT_ROOT/tools/check_deprecated_apis.sh"
}

doctor() {
  resolve_java_env
  resolve_sdk_env
  resolve_hvigor_cmd
  echo "project_root=$PROJECT_ROOT"
  echo "hvigor_desc=$HVIGOR_DESC"
  echo "hvigor_cmd=${HVIGOR_CMD[*]}"
  echo "sdk_desc=${SDK_DESC:-<not resolved>}"
  echo "DEVECO_SDK_HOME=${DEVECO_SDK_HOME:-<not set>}"
  echo "java_desc=${JAVA_DESC:-<not resolved>}"
  echo "JAVA_HOME=${JAVA_HOME:-<not set>}"
  echo "java_bin=$(command -v java || echo '<not found>')"
  echo "HVIGOR_NO_DAEMON=$HVIGOR_NO_DAEMON"
  echo "HVIGOR_USER_HOME=${HVIGOR_USER_HOME:-<not set>}"
  echo "DEVECO_HOME_EFFECTIVE=$DEVECO_HOME_EFFECTIVE"
}

cmd="${1:-build}"
if [[ $# -gt 0 ]]; then
  shift
fi

case "$cmd" in
  build)
    run_build "$@"
    ;;
  debug)
    run_hvigor assembleHap -p buildMode=debug "$@"
    ;;
  release)
    run_build "$@"
    ;;
  app-debug)
    run_hvigor assembleApp -p buildMode=debug "$@"
    ;;
  hap-release)
    run_release_hap "$@"
    ;;
  sideload-release)
    run_sideload_release_app "$@"
    ;;
  sideload-hap-release)
    run_sideload_release_hap "$@"
    ;;
  run)
    # 一键部署真机调试：编 debug HAP（非 release APP）。
    # assembleHap debug 产物即 HAP_PATH，无 .app 打包时序；debug 闸开，便于真机排查。
    run_hvigor assembleHap -p buildMode=debug "$@"
    deploy_and_launch
    ;;
  install)
    deploy_and_launch
    ;;
  clean)
    run_hvigor clean "$@"
    ;;
  lint)
    run_deprecated_check
    run_hvigor lint "$@"
    ;;
  deprecated)
    run_deprecated_check "$@"
    ;;
  doctor)
    doctor
    ;;
  -h|--help)
    usage
    ;;
  *)
    echo "未知命令: $cmd"
    usage
    exit 1
    ;;
esac

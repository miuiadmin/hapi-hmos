#!/usr/bin/env bash
# tools/logcat.sh — Hapi 设备日志工具
#
# 移植自 berry3/tools/logcat.sh，包名过滤改为 com.twsxtd.hapi。
#
# ── Agent 友好模式（自动退出）────────────────────────────────────────────────
#   tools/logcat.sh snap [N]         最近 N 行 Hapi 日志（默认 300，按 PID 过滤）
#   tools/logcat.sh err  [N]         最近 N 行中的 Error/Warn 级别（默认 200）
#   tools/logcat.sh tag  TAG [N]     按 hilog tag 过滤，N 行后退出（默认 200）
#   tools/logcat.sh grep KW  [N]     按关键字过滤 Hapi 日志（默认 200）
#
# ── 持续流模式（阻塞，需 Ctrl+C，仅交互使用）────────────────────────────────
#   tools/logcat.sh stream           实时输出所有 Hapi 日志（按 PID 过滤）
#   tools/logcat.sh js               只显示 JS 诊断日志（默认 tag=MLK，按需改下方 JS_TAG）
#
# ── 维护 ────────────────────────────────────────────────────────────────────
#   tools/logcat.sh clear            清空 debug.log 并清除设备日志缓冲区
#
# 输出文件：<project>/debug.log（追加模式）

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
HDC="/Applications/DevEco-Studio.app/Contents/sdk/default/openharmony/toolchains/hdc"
LOG_FILE="$PROJECT_ROOT/debug.log"
BUNDLE="com.twsxtd.hapi"

# JS 诊断日志的 hilog tag；berry3 用 MLK，hapi 暂沿用，如 ArkTS 侧自定义了 tag 在此改。
JS_TAG="${HAPI_JS_TAG:-MLK}"

# ── 前置检查 ─────────────────────────────────────────────────────────────────

if [[ ! -x "$HDC" ]]; then
  echo "错误: 未找到 hdc: $HDC" >&2; exit 1
fi

TARGETS=$("$HDC" list targets 2>&1)
if [[ -z "$TARGETS" || "$TARGETS" == *"[Empty]"* ]]; then
  echo "错误: 未检测到已连接设备" >&2; exit 1
fi

# ── 辅助函数 ─────────────────────────────────────────────────────────────────

# 通过 pidof 获取 Hapi 主进程 PID（HarmonyOS 原生支持，比 ps grep 更可靠）
# 只保留数字，彻底过滤 hdc 回传的 \r 等控制字符
get_hapi_pid() {
  "$HDC" shell "pidof ${BUNDLE}" 2>&1 | tr -cd '0-9'
}

# 从设备缓冲区读取最近 N 行 Hapi 日志（按 PID），自动退出
# 使用 hilog -z N -P PID：-z 限制行数并退出，-P 按进程过滤
hilog_snap_pid() {
  local lines="$1" pid="$2"
  "$HDC" shell "hilog -z ${lines} -P ${pid}" 2>&1
}

# 从设备缓冲区读取最近 N 行，按 tag 过滤，自动退出
hilog_snap_tag() {
  local lines="$1" tag="$2"
  "$HDC" shell "hilog -z ${lines} -T ${tag}" 2>&1
}

log_header() {
  local cmd="$1"
  local ts; ts=$(date "+%Y-%m-%d %H:%M:%S")
  { echo "========================================"; echo "[$ts] logcat cmd=$cmd"; echo "========================================"; } | tee -a "$LOG_FILE"
}

# ── 命令分发 ─────────────────────────────────────────────────────────────────

CMD="${1:-snap}"
ARG2="${2:-}"
ARG3="${3:-}"

case "$CMD" in

  # ── snap：最近 N 行 Hapi 进程日志，自动退出 ─────────────────────────────
  snap)
    LINES="${ARG2:-300}"
    log_header "snap lines=$LINES"
    PID=$(get_hapi_pid)
    if [[ -z "$PID" ]]; then
      echo "错误: Hapi 未运行（pidof ${BUNDLE} 无结果），请先启动应用" | tee -a "$LOG_FILE" >&2
      exit 1
    fi
    echo "Hapi PID=$PID" | tee -a "$LOG_FILE"
    hilog_snap_pid "$LINES" "$PID" | tee -a "$LOG_FILE"
    ;;

  # ── err：最近 N 行中的 Error / Warn，自动退出 ────────────────────────────
  err)
    LINES="${ARG2:-200}"
    log_header "err lines=$LINES"
    PID=$(get_hapi_pid)
    if [[ -z "$PID" ]]; then
      echo "错误: Hapi 未运行" | tee -a "$LOG_FILE" >&2; exit 1
    fi
    echo "Hapi PID=${PID}，过滤 E/W 级别" | tee -a "$LOG_FILE"
    # hilog -L E 只输出 Error；W/E 都要则分两次取并合并（hilog 不支持多级别）
    { hilog_snap_pid "$LINES" "$PID" | grep -E " [WEF] [A-Z0-9]" || true; } | tee -a "$LOG_FILE"
    ;;

  # ── tag：按 hilog tag 过滤，自动退出 ────────────────────────────────────
  tag)
    TAG="${ARG2:-Hapi}"
    LINES="${ARG3:-200}"
    log_header "tag=$TAG lines=$LINES"
    hilog_snap_tag "$LINES" "$TAG" | tee -a "$LOG_FILE"
    ;;

  # ── grep：在 Hapi 进程日志中按关键字过滤，自动退出 ──────────────────────
  grep)
    KW="${ARG2:?'用法: logcat.sh grep <关键字> [行数]'}"
    LINES="${ARG3:-200}"
    log_header "grep=$KW lines=$LINES"
    PID=$(get_hapi_pid)
    if [[ -z "$PID" ]]; then
      echo "错误: Hapi 未运行" | tee -a "$LOG_FILE" >&2; exit 1
    fi
    echo "Hapi PID=${PID}，关键字=$KW" | tee -a "$LOG_FILE"
    { hilog_snap_pid "$LINES" "$PID" | grep -i "$KW" || true; } | tee -a "$LOG_FILE"
    ;;

  # ── stream：实时流式输出 Hapi 日志（阻塞，交互使用）────────────────────
  stream)
    log_header "stream"
    PID=$(get_hapi_pid)
    if [[ -z "$PID" ]]; then
      echo "错误: Hapi 未运行" | tee -a "$LOG_FILE" >&2; exit 1
    fi
    echo "Hapi PID=${PID}，实时监听中（Ctrl+C 停止）..." | tee -a "$LOG_FILE"
    "$HDC" shell "hilog -P ${PID}" 2>&1 | tee -a "$LOG_FILE"
    ;;

  # ── js：JS 诊断日志实时流（默认 tag=MLK，阻塞）────────────────────────
  js)
    log_header "js"
    echo "过滤 JS 诊断日志（tag=${JS_TAG}），Ctrl+C 退出..." | tee -a "$LOG_FILE"
    "$HDC" shell "hilog -T ${JS_TAG}" 2>&1 | tee -a "$LOG_FILE"
    ;;

  # ── clear：清空日志文件 + 设备缓冲区 ─────────────────────────────────────
  clear)
    > "$LOG_FILE"
    "$HDC" shell "hilog -r" 2>&1 || true
    echo "已清空 debug.log 及设备 hilog 缓冲区"
    ;;

  help|--help|-h)
    sed -n '2,23p' "$0"
    ;;

  *)
    echo "未知命令: $CMD" >&2
    echo "用法: $0 [snap|err|tag|grep|stream|js|clear] [参数...]" >&2
    exit 1
    ;;
esac

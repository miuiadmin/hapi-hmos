#!/usr/bin/env bash
# tools/pack.sh — Hapi 侧载包构建脚本
#
# 移植自 berry3/tools/pack.sh，适配 hapi 身份（com.twsxtd.hapi）。
# 已移除：AboutPage 编译日期更新（hapi 无 AboutPage.ets）、check_changelog 闸（hapi 无 changelog.json）、
#         应用名共存版改名（hapi 当前仅 app.json5 硬编码包名）。
#
# 功能：
#   1. 自动将 com.twsxtd.hapi 改为 com.twsxtd.hapiNN（NN 为数字后缀，默认 88）
#   2. 每个被修改的文件单独备份，保证任何情况下都能逐文件精确恢复
#   3. 编译前/恢复后各执行一次 clean，杜绝增量缓存混入旧包名产物
#   4. 调用 build.sh/hvigor 编译（侧载 release 走 sideload-* 状态闸，生成未签名 .app/.hap）
#   5. 将生成的产物拷贝到项目根目录 output/ 下
#   6. 无论成功/失败/Ctrl-C/kill，都强制恢复所有修改，并二次校验
#
# 用法：
#   tools/pack.sh              # 默认固定后缀 88（com.twsxtd.hapi88），打 release .app
#   tools/pack.sh hap          # 变包名88，打 debug .hap
#   tools/pack.sh all          # ★ 全量：一次打出 3 个发布文件（见下）
#   tools/pack.sh all 99       # 全量，后缀用 99（com.twsxtd.hapi99）
#   tools/pack.sh 42           # 指定后缀数字（com.twsxtd.hapi42），打 release .app
#   tools/pack.sh --help       # 显示帮助
#
# all 模式产出（变包名88，一次发布所需全部）：
#   1. debug  HAP   → output/<版本>_侧载包_HAP_DEBUG_<时间戳>.hap
#   2. release HAP  → output/<版本>_侧载包_HAP_RELEASE_<时间戳>.hap
#   3. zip(内含 release .app + debug .app) → output/<版本>_侧载包_APPS_<时间戳>.zip

# pipefail：管道任意阶段失败即报错；不使用 -e，以便 restore 函数能完整运行
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ========== 配置 ==========

ORIGINAL_BUNDLE="com.twsxtd.hapi"

# 需要替换包名的文件列表（扫描到新的硬编码时在此添加）。
# 当前 hapi 仅 AppScope/app.json5 硬编码 bundleName，故只列这一份。
FILES_TO_PATCH=(
  "AppScope/app.json5"
)

# 预检白名单：包名仅出现在 URL/注释/文档中，不影响运行时，无需替换。
# hapi 暂无此类文件；发现误报时在此添加相对路径。
SCAN_WHITELIST=()

APP_OUTPUT_DIR="build/outputs/default"
OUTPUT_DIR="$PROJECT_ROOT/output"

# 备份目录（每次打包使用独立目录，避免并发冲突）
BACKUP_DIR=""

# 锁文件（防止并发运行踩踏）
LOCK_FILE="$PROJECT_ROOT/.pack.lock"

# 标记：包名是否已经被修改（控制 restore 是否需要执行 sed 恢复）
PATCHED=0

# ========== 帮助 ==========

if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
  cat <<EOF
用法: tools/pack.sh [all|hap] [后缀数字]

  不传参数：固定后缀 88，打 release .app（com.twsxtd.hapi88）
  all      ：★ 全量打包，一次产出发布所需的 3 个文件（变包名88）
              ① debug HAP    ② release HAP    ③ zip(内含 release .app + debug .app)
  hap      ：只打 debug .hap（com.twsxtd.hapi88，可 hdc install）
  数字     ：用该数字作后缀（如 tools/pack.sh 42）

流程：
  1. 预检：扫描源码中所有硬编码包名（发现遗漏时警告）
  2. 逐文件备份后修改包名 + 清空 signingConfig（变包名后证书校验会失败）
  3. clean 清除旧构建缓存
  4. 编译（all 模式循环 4 次：app×{release,debug} + hap×{release,debug}）
  5. 拷贝产物到 output/ 目录（all 额外把两个 .app 打进一个 zip）
  6. 强制恢复所有修改 + clean 清除变包名缓存，二次校验确认

输出：
  output/ 目录下的 .app / .hap / .zip 文件（均未签名，调试设备可 hdc install）

示例：
  tools/pack.sh        # com.twsxtd.hapi → com.twsxtd.hapi88，打 release .app
  tools/pack.sh all    # ★ 全量：debug HAP + release HAP + zip(release app + debug app)
  tools/pack.sh hap    # 变包名88，打 debug .hap
  tools/pack.sh all 99 # 全量，后缀 99（com.twsxtd.hapi99）
EOF
  exit 0
fi

# ========== 工具函数 ==========

log_info()  { echo "  $*"; }
log_ok()    { echo "  ✓ $*"; }
log_warn()  { echo "  ⚠ $*" >&2; }
log_err()   { echo "  ✗ $*" >&2; }
log_step()  { echo ""; echo "$*"; }

# 深度清除构建缓存（hvigor clean 不一定清干净增量缓存目录）
deep_clean() {
  local label="${1:-构建缓存}"
  echo "  [清缓存] 清除${label}..."

  # 1. hvigor clean（常规清理）
  "$SCRIPT_DIR/build.sh" clean >/dev/null 2>&1 || true

  # 2. 强删增量缓存目录（hvigor clean 可能遗漏）
  local dirs_to_remove=(
    "$PROJECT_ROOT/.hvigor"
    "$PROJECT_ROOT/entry/.hvigor"
    "$PROJECT_ROOT/build"
    "$PROJECT_ROOT/entry/build"
    "$PROJECT_ROOT/entry/.cxx"
    "$PROJECT_ROOT/.cxx"
  )
  for dir in "${dirs_to_remove[@]}"; do
    if [[ -d "$dir" ]]; then
      rm -rf "$dir"
      log_ok "已删除: ${dir#$PROJECT_ROOT/}"
    fi
  done

  log_ok "${label}已清除"
}

# 编译单个目标并拷贝产物到 output/
# 参数：$1=build.sh命令  $2=产物标签  $3=扩展名  $4=产物目录  $5=find模式
# 依赖全局：VERSION_UNDER / TIMESTAMP / OUTPUT_DIR（在步骤 3 区已赋值）
build_one() {
  local cmd="$1" label="$2" ext="$3" product_dir="$4" pattern="$5"

  # 编译前只清 build 产物（保留 .hvigor：deep_clean 重建慢 + 偶发 ProcessRouterMap 坑）
  "$SCRIPT_DIR/build.sh" clean >/dev/null 2>&1 || true

  log_step "[编译] ${label}（build.sh ${cmd}）..."
  # pack.sh 会刻意清空 signingConfig 生成侧载/测试产物；正式 release 仍由 build.sh 默认硬校验。
  # ⚠️ 坑：不要让 check_release_signing.sh 提供任何 unsigned 放行口，否则正式 release 闸会被复用绕过。
  # 解法：release 侧载产物走 build.sh 的 sideload-* 显式命令，不调用 release 签名校验。
  local build_cmd="$cmd"
  if [[ "$cmd" == "build" || "$cmd" == "release" ]]; then
    build_cmd="sideload-release"
  elif [[ "$cmd" == "hap-release" ]]; then
    build_cmd="sideload-hap-release"
  fi

  if ! "$SCRIPT_DIR/build.sh" "$build_cmd"; then
    log_err "编译 ${label} 失败！"
    return 1
  fi

  # 拷贝产物（未签名→无后缀；已签名→带 _signed）
  local found=0
  if [[ -d "$product_dir" ]]; then
    while IFS= read -r prod_file; do
      [[ -z "$prod_file" ]] && continue
      local out_name
      if [[ "$prod_file" == *"-unsigned.$ext" ]]; then
        out_name="${VERSION_UNDER}_侧载包_${label}_${TIMESTAMP}.$ext"
      else
        out_name="${VERSION_UNDER}_侧载包_${label}_${TIMESTAMP}_signed.$ext"
      fi
      cp "$prod_file" "$OUTPUT_DIR/$out_name"
      log_ok "已拷贝: output/$out_name  ($(du -sh "$OUTPUT_DIR/$out_name" | cut -f1))"
      found=1
    done < <(find "$product_dir" -maxdepth 1 -name "$pattern" 2>/dev/null | sort)
  fi
  [[ "$found" -eq 0 ]] && log_warn "未找到 ${label} 的 .${ext} 产物（搜索: ${product_dir} / ${pattern}）"
  return 0
}

# ========== 锁文件 ==========

acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    STALE_PID=$(cat "$LOCK_FILE" 2>/dev/null || true)
    # PID 已退出 → 陈旧锁，自动清除后继续
    if [[ -n "$STALE_PID" ]] && ! kill -0 "$STALE_PID" 2>/dev/null; then
      log_warn "清除陈旧锁文件（PID $STALE_PID 已不存在）"
      rm -f "$LOCK_FILE"
    else
      log_err "pack.sh 已在运行（PID: ${STALE_PID:-unknown}），请勿并发执行。"
      log_err "如确认无其他进程在运行，手动删除锁文件后重试："
      log_err "  rm -f $LOCK_FILE"
      exit 1
    fi
  fi
  echo $$ > "$LOCK_FILE"
}

release_lock() {
  rm -f "$LOCK_FILE"
}

# ========== 备份与恢复 ==========

# 备份单个文件到 BACKUP_DIR
backup_file() {
  local rel="$1"
  local src="$PROJECT_ROOT/$rel"
  local dst="$BACKUP_DIR/${rel//\//__}"   # 把路径斜杠换成 __ 作为备份文件名
  if [[ -f "$src" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp "$src" "$dst"
  fi
}

# 从 BACKUP_DIR 恢复单个文件（精确字节级恢复，不依赖 sed）
restore_file_from_backup() {
  local rel="$1"
  local src="$PROJECT_ROOT/$rel"
  local bak="$BACKUP_DIR/${rel//\//__}"
  if [[ -f "$bak" ]]; then
    cp "$bak" "$src"
    return 0
  fi
  return 1
}

# 恢复单个文件（优先备份，兜底 sed，无论 PATCHED 是否为 1）
_restore_one() {
  local file="$1"
  local filepath="$PROJECT_ROOT/$file"
  [[ -f "$filepath" ]] || return 0

  # 优先从备份精确恢复
  if restore_file_from_backup "$file"; then
    log_ok "从备份恢复: $file"
    return 0
  fi

  # 兜底：备份不存在时，检查文件是否含新包名，有则 sed 反向替换
  if grep -qF "${NEW_BUNDLE:-__UNKNOWN__}" "$filepath" 2>/dev/null; then
    if sed -i '' "s/${NEW_BUNDLE:-__UNKNOWN__}/${ORIGINAL_BUNDLE}/g" "$filepath" 2>/dev/null; then
      log_warn "用 sed 兜底恢复（备份丢失）: $file"
      return 0
    fi
    log_err "恢复失败: $file"
    return 1
  fi

  # 文件里没有新包名，视为已恢复
  return 0
}

# 主恢复函数：trap 触发时调用，保证任何情况下都执行
restore_all() {
  local exit_code=$?
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  [恢复] 开始恢复所有临时修改..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local restore_errors=0

  # FILES_TO_PATCH 中的文件
  for file in "${FILES_TO_PATCH[@]}"; do
    local filepath="$PROJECT_ROOT/$file"
    [[ -f "$filepath" ]] || continue
    _restore_one "$file" && continue
    (( restore_errors++ )) || true
  done

  # build-profile.json5 单独恢复（不在 FILES_TO_PATCH 里）
  _restore_one "build-profile.json5" || (( restore_errors++ )) || true

  # ── 二次校验 + 自动修复：确认原始包名已回来，新包名不存在 ──
  echo ""
  echo "  [校验] 验证包名恢复结果..."
  local verify_errors=0
  local all_files=("${FILES_TO_PATCH[@]}" "build-profile.json5")
  for file in "${all_files[@]}"; do
    local filepath="$PROJECT_ROOT/$file"
    [[ -f "$filepath" ]] || continue

    # 新包名还在 → 先 sed 兜底修复，再判断结果
    if grep -qF "${NEW_BUNDLE:-__UNKNOWN__}" "$filepath" 2>/dev/null; then
      if sed -i '' "s/${NEW_BUNDLE:-__UNKNOWN__}/${ORIGINAL_BUNDLE}/g" "$filepath" 2>/dev/null \
         && ! grep -qF "${NEW_BUNDLE:-__UNKNOWN__}" "$filepath" 2>/dev/null; then
        log_warn "备份恢复不完整，已自动修复: $file"
      else
        log_err "校验失败（新包名未清除）: $file"
        (( verify_errors++ )) || true
      fi
    else
      log_ok "校验通过: $file"
    fi
  done

  # 清理备份目录
  if [[ -n "$BACKUP_DIR" && -d "$BACKUP_DIR" ]]; then
    rm -rf "$BACKUP_DIR"
  fi

  # ── 恢复后深度清除构建缓存 ──
  # 防止残留变包名编译产物污染下次正常构建
  deep_clean "变包名构建产物"

  # 释放锁
  release_lock

  if [[ "$verify_errors" -gt 0 || "$restore_errors" -gt 0 ]]; then
    echo ""
    log_err "⚠ 有 $((verify_errors + restore_errors)) 个文件未能完整恢复！"
    log_err "请手动检查以下文件，将 '${NEW_BUNDLE:-}' 替换回 '${ORIGINAL_BUNDLE}'："
    for file in "${FILES_TO_PATCH[@]}" "build-profile.json5"; do
      local filepath="$PROJECT_ROOT/$file"
      [[ -f "$filepath" ]] || continue
      if grep -qF "${NEW_BUNDLE:-__UNKNOWN__}" "$filepath" 2>/dev/null; then
        log_err "  → $file"
      fi
    done
    echo ""
    log_err "紧急修复命令："
    log_err "  grep -rl '${NEW_BUNDLE:-}' entry/ AppScope/ build-profile.json5 \\"
    log_err "    | xargs sed -i '' 's/${NEW_BUNDLE:-}/${ORIGINAL_BUNDLE}/g'"
  else
    echo ""
    echo "  [恢复] 全部完成 ✓"
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit "$exit_code"
}

# 捕获所有退出信号：正常退出、Ctrl-C、kill、脚本错误
trap restore_all EXIT INT TERM HUP

# ========== 参数解析 ==========

# 打包类型：app（默认，release 未签名 .app）/ hap（debug .hap）/ all（全量 4 产物 + zip）
PACK_TYPE="app"
if [[ "${1:-}" == "all" ]]; then
  PACK_TYPE="all"
  SUFFIX="${2:-88}"        # tools/pack.sh all [后缀]
elif [[ "${1:-}" == "hap" ]]; then
  PACK_TYPE="hap"
  SUFFIX="${2:-88}"        # tools/pack.sh hap [后缀]
elif [[ -n "${1:-}" ]]; then
  SUFFIX="$1"              # tools/pack.sh <后缀>
else
  SUFFIX=88                # tools/pack.sh
fi

NEW_BUNDLE="${ORIGINAL_BUNDLE}${SUFFIX}"
BACKUP_DIR="$PROJECT_ROOT/.pack_backup_$$"

# ========== 锁 ==========

acquire_lock

# ========== 预检：扫描遗漏的硬编码包名 ==========

log_step "[预检] 扫描源码中所有硬编码包名..."

# 扫描范围：entry/ 和 AppScope/，排除 build/ docs/ .cxx/
SCAN_MATCHES=$(grep -rl "$ORIGINAL_BUNDLE" \
  "$PROJECT_ROOT/entry/src" \
  "$PROJECT_ROOT/AppScope" \
  "$PROJECT_ROOT/build-profile.json5" \
  2>/dev/null \
  | grep -v "/build/" | grep -v "/docs/" | grep -v "/\.cxx/" \
  | sort)

# 对比 FILES_TO_PATCH，找出未覆盖的文件
UNPATCHED_FILES=()
while IFS= read -r abs_path; do
  rel_path="${abs_path#$PROJECT_ROOT/}"
  covered=0
  for f in "${FILES_TO_PATCH[@]}" "${SCAN_WHITELIST[@]}"; do
    [[ "$f" == "$rel_path" ]] && covered=1 && break
  done
  # build-profile.json5 单独处理，不需要出现在预检警告里
  [[ "$rel_path" == "build-profile.json5" ]] && covered=1
  if [[ "$covered" -eq 0 ]]; then
    UNPATCHED_FILES+=("$rel_path")
  fi
done <<< "$SCAN_MATCHES"

if [[ "${#UNPATCHED_FILES[@]}" -gt 0 ]]; then
  log_warn "发现以下文件含包名但不在 FILES_TO_PATCH 列表中（可能导致运行时崩溃）："
  for f in "${UNPATCHED_FILES[@]}"; do
    log_warn "  → $f"
  done
  log_warn "请将上述文件加入 pack.sh 的 FILES_TO_PATCH 后重试。"
  log_warn "若确认这些文件无需修改（如注释/文档），忽略此警告。"
  echo ""
  read -r -p "  是否继续打包？[y/N] " confirm
  confirm_lower=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
  # ⚠️ 取消必须 exit 1（非 0）：非交互调用时 read 读不到输入走取消分支，
  #    若 exit 0 会让上游误判成功、静默继续解到上次残留的旧产物。
  #    取消 = 未完成打包，必须非零退出码让上游捕获失败。
  [[ "$confirm_lower" == "y" ]] || { echo "已取消。"; exit 1; }
else
  log_ok "预检通过，所有硬编码包名均已覆盖"
fi

# ========== 打印摘要 ==========

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Hapi 侧载包构建"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
log_info "原始包名 : ${ORIGINAL_BUNDLE}"
log_info "临时包名 : ${NEW_BUNDLE}"
case "$PACK_TYPE" in
  all) log_info "构建模式 : 全量（app+hap × release+debug → 3 个发布文件）" ;;
  hap) log_info "构建模式 : debug HAP（未签名，调试设备可装）" ;;
  *)   log_info "构建模式 : release APP（未签名）" ;;
esac
log_info "备份目录 : ${BACKUP_DIR}"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 注：berry3 在此更新 AboutPage 编译日期并校验 changelog.json；
#     hapi 两者皆无，已移除。如未来加入 changelog，在此重新接入 check_changelog.sh。

# ========== 步骤 1/4：逐文件备份 + 替换包名 ==========

log_step "[步骤 1/4] 备份并修改包名 → ${NEW_BUNDLE}"

mkdir -p "$BACKUP_DIR"

for file in "${FILES_TO_PATCH[@]}"; do
  filepath="$PROJECT_ROOT/$file"
  if [[ ! -f "$filepath" ]]; then
    log_warn "文件不存在，跳过: $file"
    continue
  fi
  # 先备份，再修改
  backup_file "$file"
  sed -i '' "s/${ORIGINAL_BUNDLE}/${NEW_BUNDLE}/g" "$filepath"
  log_ok "已修改: $file"
done

# build-profile.json5：单独备份后清空 signingConfig，避免证书包名校验失败
BUILD_PROFILE="$PROJECT_ROOT/build-profile.json5"
backup_file "build-profile.json5"
# ⚠️ 坑：switch-signing.sh 支持任意 signingConfig 名称，不能只枚举 default/fabu。
# 解法：只清空 products[0] 当前 signingConfig 值，让侧载构建通过 build.sh 的状态闸。
perl -0pi -e 's/"signingConfig"\s*:\s*"[^"]*"/"signingConfig": ""/m' "$BUILD_PROFILE"
log_ok "已清空签名配置: build-profile.json5"

# 标记：包名已被修改，restore 需要执行恢复
PATCHED=1

# ========== 步骤 2/4：清除构建缓存 ==========

log_step "[步骤 2/4] 深度清除构建缓存（防止增量编译混入旧包名产物）..."

cd "$PROJECT_ROOT"
deep_clean "编译前缓存"

# ========== 步骤 3/4：编译 + 拷贝产物 ==========

log_step "[步骤 3/4] 编译并拷贝产物..."

mkdir -p "$OUTPUT_DIR"

# 提前算版本号与时间戳（build_one 命名要用）
VERSION_NAME=$(sed -n 's/.*"versionName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
  "$PROJECT_ROOT/AppScope/app.json5" | head -n 1)
VERSION_UNDER="${VERSION_NAME//./_}"   # 0.1.0 → 0_1_0
TIMESTAMP=$(date +%m%d%H%M)            # 03281425 格式

# 产物目录
APP_PRODUCT_DIR="$PROJECT_ROOT/$APP_OUTPUT_DIR"           # build/outputs/default
HAP_PRODUCT_DIR="$PROJECT_ROOT/entry/build/default/outputs/default"

# 按 PACK_TYPE 编译（build_one 内部先 build.sh clean 再编译，避免 app release/debug 产物互相覆盖）
BUILD_FAIL=0
if [[ "$PACK_TYPE" == "all" ]]; then
  # 全量：app×{release,debug} + hap×{release,debug}
  build_one build       APP_RELEASE app "$APP_PRODUCT_DIR" "*.app"               || BUILD_FAIL=1
  build_one app-debug   APP_DEBUG   app "$APP_PRODUCT_DIR" "*.app"               || BUILD_FAIL=1
  build_one hap-release HAP_RELEASE hap "$HAP_PRODUCT_DIR" "entry-default-*.hap" || BUILD_FAIL=1
  build_one debug       HAP_DEBUG   hap "$HAP_PRODUCT_DIR" "entry-default-*.hap" || BUILD_FAIL=1
elif [[ "$PACK_TYPE" == "hap" ]]; then
  build_one debug HAP hap "$HAP_PRODUCT_DIR" "entry-default-*.hap" || BUILD_FAIL=1
else
  build_one build APP app "$APP_PRODUCT_DIR" "*.app" || BUILD_FAIL=1
fi

if [[ "$BUILD_FAIL" -ne 0 ]]; then
  echo ""
  log_err "有编译步骤失败！包名将自动恢复，已产出的文件保留在 output/。"
  exit 1
fi

# ========== 步骤 4a/4b：all 模式把 release .app + debug .app 合并打成一个 zip ==========

ZIP_NAME=""
if [[ "$PACK_TYPE" == "all" ]]; then
  log_step "[步骤 4a/4b] 合并 release .app + debug .app → zip..."

  RELEASE_APP=$(ls -t "$OUTPUT_DIR"/*侧载包_APP_RELEASE*.app 2>/dev/null | head -1)
  DEBUG_APP=$(ls -t "$OUTPUT_DIR"/*侧载包_APP_DEBUG*.app 2>/dev/null | head -1)

  ZIP_NAME="${VERSION_UNDER}_侧载包_APPS_${TIMESTAMP}.zip"
  TMP_ZIP_DIR="/tmp/hapi_apps_pack_$$"
  rm -rf "$TMP_ZIP_DIR"
  mkdir -p "$TMP_ZIP_DIR"

  ZIP_COUNT=0
  if [[ -n "$RELEASE_APP" ]]; then
    cp "$RELEASE_APP" "$TMP_ZIP_DIR/hapi-${VERSION_NAME}-release.app"
    ZIP_COUNT=$((ZIP_COUNT + 1))
  else
    log_warn "未找到 release .app，zip 将不含它"
  fi
  if [[ -n "$DEBUG_APP" ]]; then
    cp "$DEBUG_APP" "$TMP_ZIP_DIR/hapi-${VERSION_NAME}-debug.app"
    ZIP_COUNT=$((ZIP_COUNT + 1))
  else
    log_warn "未找到 debug .app，zip 将不含它"
  fi

  if [[ "$ZIP_COUNT" -gt 0 ]]; then
    ( cd "$TMP_ZIP_DIR" && zip -q "$OUTPUT_DIR/$ZIP_NAME" *.app )
    log_ok "已打包: output/$ZIP_NAME  ($(du -sh "$OUTPUT_DIR/$ZIP_NAME" | cut -f1)，内含 ${ZIP_COUNT} 个 .app)"
    # zip 成功后删除 output/ 里单独的两个 .app：发布只要合并 zip，避免 output 冗余
    [[ -n "$RELEASE_APP" ]] && rm -f "$RELEASE_APP"
    [[ -n "$DEBUG_APP" ]] && rm -f "$DEBUG_APP"
  else
    log_err "无 .app 可打包，跳过 zip"
    ZIP_NAME=""
  fi
  rm -rf "$TMP_ZIP_DIR"
fi

# ========== 步骤 4b/4b：打印摘要 ==========

log_step "[步骤 4b/4b] 构建完成"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  构建完成！"
log_info "包名  : ${NEW_BUNDLE}"
log_info "本次产出（output/）："
# 用本次 TIMESTAMP 过滤，只列这次产出的文件（历史产物不列）
find "$OUTPUT_DIR" -maxdepth 1 -name "*${TIMESTAMP}*" 2>/dev/null | sort \
  | while IFS= read -r f; do log_info "  → $(basename "$f")  ($(du -sh "$f" | cut -f1))"; done
case "$PACK_TYPE" in
  all) log_info "类型  : 全量（2 HAP + 1 zip，均未签名，调试设备/模拟器可 hdc install）" ;;
  hap) log_info "类型  : debug .hap（未签名，调试设备可装）" ;;
  *)   log_info "类型  : release .app（未签名）" ;;
esac
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
# EXIT trap 会接管后续恢复流程

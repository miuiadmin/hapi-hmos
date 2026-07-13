#!/usr/bin/env bash
# tools/pack_common.sh — pack-app-* 系列脚本公共库
#
# 移植自 berry3/tools/pack_common.sh，适配 hapi 身份（com.twsxtd.hapi）。
# 已移除：AboutPage 编译日期更新（hapi 无 AboutPage.ets）、check_changelog 闸（hapi 无 changelog.json）。
#
# 被 tools/pack-app-{release,debug}.sh source，提供：
#   变包名 / 备份恢复 / 锁 / 预检 / 编译 / 拷贝 / 摘要 全套逻辑。
#
# 调用方在 source 前设置（必填）：
#   SCRIPT_DIR / PROJECT_ROOT   路径（调用方计算）
#   BUILD_CMD  build.sh 命令：build / app-debug / sideload-release
#   LABEL      产物标签：APP / APP_DEBUG
#   PREFIX     文件名前缀："侧载包_"（88 侧载）或 ""（正式包）
# 可选：
#   SUFFIX     包名后缀：空=正式包（不变包名）；88=变包名 com.twsxtd.hapi88
#
# source 后调用 run_pack 执行。

# 防止直接执行（必须被 source）
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  echo "pack_common.sh 是公共库，必须被 pack-app-*.sh source 调用，不能直接执行。" >&2
  echo "用法：通过 pack-app-release.sh / pack-app-debug.sh 调用。" >&2
  exit 1
fi

# ========== 配置常量 ==========

ORIGINAL_BUNDLE="com.twsxtd.hapi"

# 需要替换包名的文件列表（扫描到新硬编码时在此添加；与 pack.sh 保持同步）。
# 当前 hapi 仅 AppScope/app.json5 硬编码 bundleName。
FILES_TO_PATCH=(
  "AppScope/app.json5"
)

# 预检白名单：包名仅出现在 URL/注释/文档中，不影响运行时，无需替换。
SCAN_WHITELIST=()

APP_OUTPUT_DIR="build/outputs/default"
OUTPUT_DIR="$PROJECT_ROOT/output"
# 与 pack.sh 共用锁：都改包名，必须互斥
LOCK_FILE="$PROJECT_ROOT/.pack.lock"

# 运行时变量（run_pack 初始化）
NEW_BUNDLE=""
BACKUP_DIR=""
BUILD_TIMESTAMP=""

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

  "$SCRIPT_DIR/build.sh" clean >/dev/null 2>&1 || true

  local dirs_to_remove=(
    "$PROJECT_ROOT/.hvigor"
    "$PROJECT_ROOT/entry/.hvigor"
    "$PROJECT_ROOT/build"
    "$PROJECT_ROOT/entry/build"
    "$PROJECT_ROOT/entry/.cxx"
    "$PROJECT_ROOT/.cxx"
  )
  local dir
  for dir in "${dirs_to_remove[@]}"; do
    if [[ -d "$dir" ]]; then
      rm -rf "$dir"
      log_ok "已删除: ${dir#$PROJECT_ROOT/}"
    fi
  done

  log_ok "${label}已清除"
}

# ========== 锁文件 ==========

acquire_lock() {
  if [[ -f "$LOCK_FILE" ]]; then
    local stale_pid
    stale_pid=$(cat "$LOCK_FILE" 2>/dev/null || true)
    if [[ -n "$stale_pid" ]] && ! kill -0 "$stale_pid" 2>/dev/null; then
      log_warn "清除陈旧锁文件（PID $stale_pid 已不存在）"
      rm -f "$LOCK_FILE"
    else
      log_err "打包脚本已在运行（PID: ${stale_pid:-unknown}），请勿并发执行。"
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
  local dst="$BACKUP_DIR/${rel//\//__}"   # 路径斜杠换 __ 作备份文件名
  if [[ -f "$src" ]]; then
    mkdir -p "$BACKUP_DIR"
    cp "$src" "$dst"
  fi
}

# 从 BACKUP_DIR 精确恢复（字节级，不依赖 sed）
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

# 恢复单个文件（优先备份，兜底 sed）
_restore_one() {
  local file="$1"
  local filepath="$PROJECT_ROOT/$file"
  [[ -f "$filepath" ]] || return 0

  if restore_file_from_backup "$file"; then
    log_ok "从备份恢复: $file"
    return 0
  fi

  if grep -qF "${NEW_BUNDLE}" "$filepath" 2>/dev/null; then
    if sed -i '' "s/${NEW_BUNDLE}/${ORIGINAL_BUNDLE}/g" "$filepath" 2>/dev/null; then
      log_warn "用 sed 兜底恢复（备份丢失）: $file"
      return 0
    fi
    log_err "恢复失败: $file"
    return 1
  fi

  return 0
}

# 主恢复：trap 触发时调用（仅变包名模式做事，正式包仅释放锁）
restore_all() {
  local exit_code=$?

  # 正式包（不变包名）：无修改需恢复，仅释放锁
  if [[ -z "${SUFFIX:-}" ]]; then
    release_lock
    exit "$exit_code"
  fi

  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  [恢复] 开始恢复所有临时修改..."
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

  local restore_errors=0
  local file filepath

  for file in "${FILES_TO_PATCH[@]}"; do
    filepath="$PROJECT_ROOT/$file"
    [[ -f "$filepath" ]] || continue
    _restore_one "$file" && continue
    (( restore_errors++ )) || true
  done

  # build-profile.json5 单独恢复（不在 FILES_TO_PATCH 里）
  _restore_one "build-profile.json5" || (( restore_errors++ )) || true

  # ── 二次校验 + 自动修复：确认新包名已不存在 ──
  echo ""
  echo "  [校验] 验证包名恢复结果..."
  local verify_errors=0
  local all_files=("${FILES_TO_PATCH[@]}" "build-profile.json5")
  for file in "${all_files[@]}"; do
    filepath="$PROJECT_ROOT/$file"
    [[ -f "$filepath" ]] || continue
    if grep -qF "${NEW_BUNDLE}" "$filepath" 2>/dev/null; then
      if sed -i '' "s/${NEW_BUNDLE}/${ORIGINAL_BUNDLE}/g" "$filepath" 2>/dev/null \
         && ! grep -qF "${NEW_BUNDLE}" "$filepath" 2>/dev/null; then
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

  # 恢复后深度清除构建缓存（防残留变包名产物污染下次构建）
  deep_clean "变包名构建产物"

  release_lock

  if [[ "$verify_errors" -gt 0 || "$restore_errors" -gt 0 ]]; then
    echo ""
    log_err "⚠ 有 $((verify_errors + restore_errors)) 个文件未能完整恢复！"
    log_err "请手动将 '${NEW_BUNDLE}' 替换回 '${ORIGINAL_BUNDLE}'。"
    log_err "紧急修复命令："
    log_err "  grep -rl '${NEW_BUNDLE}' entry/ AppScope/ build-profile.json5 \\"
    log_err "    | xargs sed -i '' 's/${NEW_BUNDLE}/${ORIGINAL_BUNDLE}/g'"
  else
    echo ""
    echo "  [恢复] 全部完成 ✓"
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  exit "$exit_code"
}

# ========== 预检（仅变包名模式调用） ==========

run_preflight() {
  log_step "[预检] 扫描源码中所有硬编码包名..."

  local scan_matches
  scan_matches=$(grep -rl "$ORIGINAL_BUNDLE" \
    "$PROJECT_ROOT/entry/src" \
    "$PROJECT_ROOT/AppScope" \
    "$PROJECT_ROOT/build-profile.json5" \
    2>/dev/null \
    | grep -v "/build/" | grep -v "/docs/" | grep -v "/\.cxx/" \
    | sort)

  local unpatched=()
  local abs_path rel_path covered f
  while IFS= read -r abs_path; do
    rel_path="${abs_path#$PROJECT_ROOT/}"
    covered=0
    for f in "${FILES_TO_PATCH[@]}" "${SCAN_WHITELIST[@]}"; do
      [[ "$f" == "$rel_path" ]] && covered=1 && break
    done
    # build-profile.json5 单独处理，不出现在预检警告里
    [[ "$rel_path" == "build-profile.json5" ]] && covered=1
    if [[ "$covered" -eq 0 ]]; then
      unpatched+=("$rel_path")
    fi
  done <<< "$scan_matches"

  if [[ "${#unpatched[@]}" -gt 0 ]]; then
    log_warn "发现以下文件含包名但不在 FILES_TO_PATCH 列表中（可能导致运行时崩溃）："
    for f in "${unpatched[@]}"; do
      log_warn "  → $f"
    done
    log_warn "请将上述文件加入 FILES_TO_PATCH 后重试。"
    log_warn "若确认这些文件无需修改（如注释/文档），忽略此警告。"
    echo ""
    read -r -p "  是否继续打包？[y/N] " confirm
    local confirm_lower
    confirm_lower=$(echo "$confirm" | tr '[:upper:]' '[:lower:]')
    [[ "$confirm_lower" == "y" ]] || { echo "已取消。"; exit 0; }
  else
    log_ok "预检通过，所有硬编码包名均已覆盖"
  fi
}

# ========== 步骤函数 ==========

# 步骤 1：变包名 + 清签名（仅变包名模式调用）
# 注：berry3 在此之前还有 update_build_date_step + check_changelog；
#     hapi 两者皆无，已移除。
patch_bundle() {
  log_step "[步骤 1] 备份并修改包名 → ${NEW_BUNDLE}"

  mkdir -p "$BACKUP_DIR"

  local file filepath
  for file in "${FILES_TO_PATCH[@]}"; do
    filepath="$PROJECT_ROOT/$file"
    if [[ ! -f "$filepath" ]]; then
      log_warn "文件不存在，跳过: $file"
      continue
    fi
    backup_file "$file"
    sed -i '' "s/${ORIGINAL_BUNDLE}/${NEW_BUNDLE}/g" "$filepath"
    log_ok "已修改: $file"
  done

  # build-profile.json5：清空 signingConfig（变包名后证书校验会失败）
  backup_file "build-profile.json5"
  # ⚠️ 坑：switch-signing.sh 支持任意 signingConfig 名称，不能只枚举 default/fabu。
  # 解法：只清空 products[0] 当前 signingConfig 值，让侧载构建走 build.sh 的状态闸。
  perl -0pi -e 's/"signingConfig"\s*:\s*"[^"]*"/"signingConfig": ""/m' "$PROJECT_ROOT/build-profile.json5"
  log_ok "已清空签名配置: build-profile.json5"
}

# 编译 + 拷贝产物
build_and_copy() {
  log_step "[编译+拷贝] build.sh ${BUILD_CMD}..."

  mkdir -p "$OUTPUT_DIR"

  local version_name
  version_name=$(sed -n 's/.*"versionName"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    "$PROJECT_ROOT/AppScope/app.json5" | head -n 1)
  local version_under="${version_name//./_}"   # 0.1.0 → 0_1_0
  local timestamp
  timestamp=$(date +%m%d%H%M)                  # 07060123 格式
  BUILD_TIMESTAMP="$timestamp"

  local product_dir="$PROJECT_ROOT/$APP_OUTPUT_DIR"

  # 编译前只清 build 产物（保留 .hvigor：deep_clean 重建慢 + 偶发 ProcessRouterMap 坑）
  "$SCRIPT_DIR/build.sh" clean >/dev/null 2>&1 || true

  if ! "$SCRIPT_DIR/build.sh" "$BUILD_CMD"; then
    log_err "编译失败！"
    if [[ -n "${SUFFIX:-}" ]]; then
      log_err "包名将自动恢复，已产出的文件保留在 output/。"
    fi
    exit 1
  fi

  # 拷贝产物（未签名→无后缀；已签名→带 _signed）
  local found=0
  local prod_file out_name
  if [[ -d "$product_dir" ]]; then
    while IFS= read -r prod_file; do
      [[ -z "$prod_file" ]] && continue
      if [[ "$prod_file" == *"-unsigned.app" ]]; then
        out_name="${version_under}_${PREFIX}${LABEL}_${timestamp}.app"
      else
        out_name="${version_under}_${PREFIX}${LABEL}_${timestamp}_signed.app"
      fi
      cp "$prod_file" "$OUTPUT_DIR/$out_name"
      log_ok "已拷贝: output/$out_name  ($(du -sh "$OUTPUT_DIR/$out_name" | cut -f1))"
      found=1
    done < <(find "$product_dir" -maxdepth 1 -name "*.app" 2>/dev/null | sort)
  fi
  [[ "$found" -eq 0 ]] && log_warn "未找到 .app 产物（搜索: ${product_dir}）"
}

# ========== 摘要 ==========

print_header() {
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  Hapi 打包（${LABEL}）"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  if [[ -n "${SUFFIX:-}" ]]; then
    log_info "原始包名 : ${ORIGINAL_BUNDLE}"
    log_info "临时包名 : ${NEW_BUNDLE}"
    log_info "构建命令 : build.sh ${BUILD_CMD}（变包名+清签名）"
    log_info "备份目录 : ${BACKUP_DIR}"
  else
    log_info "包名     : ${ORIGINAL_BUNDLE}（正式，不变包名）"
    log_info "构建命令 : build.sh ${BUILD_CMD}"
  fi
  log_info "产物标签 : ${LABEL}"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

print_summary() {
  log_step "[完成]"
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  构建完成！"
  log_info "包名  : ${NEW_BUNDLE}"
  log_info "本次产出（output/）："
  # 用本次 timestamp 过滤，只列这次产出的文件（历史产物不列）
  find "$OUTPUT_DIR" -maxdepth 1 -name "*${BUILD_TIMESTAMP}*" 2>/dev/null | sort \
    | while IFS= read -r f; do log_info "  → $(basename "$f")  ($(du -sh "$f" | cut -f1))"; done
  log_info "类型  : ${LABEL}（build.sh ${BUILD_CMD}）"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
}

# ========== 主入口 ==========

run_pack() {
  # 校验调用方配置
  if [[ -z "${BUILD_CMD:-}" || -z "${LABEL:-}" ]]; then
    echo "错误：调用方必须设置 BUILD_CMD 和 LABEL（PREFIX/SUFFIX 可选）" >&2
    exit 1
  fi
  if [[ -z "${SCRIPT_DIR:-}" || -z "${PROJECT_ROOT:-}" ]]; then
    echo "错误：调用方必须设置 SCRIPT_DIR 和 PROJECT_ROOT" >&2
    exit 1
  fi

  NEW_BUNDLE="${ORIGINAL_BUNDLE}${SUFFIX:-}"
  BACKUP_DIR="$PROJECT_ROOT/.pack_backup_$$"
  BUILD_TIMESTAMP=""

  acquire_lock
  trap restore_all EXIT INT TERM HUP

  print_header

  if [[ -n "${SUFFIX:-}" ]]; then
    # 侧载模式：预检 + 变包名 + 清缓存
    run_preflight
    patch_bundle
    deep_clean "编译前缓存"
  fi
  # 正式包：build.sh 自己处理 release 签名校验
  # 注：berry3 在此处还会 update_build_date + check_changelog，hapi 两者皆无，已移除。

  build_and_copy
  print_summary
  # EXIT trap 接管恢复流程
}

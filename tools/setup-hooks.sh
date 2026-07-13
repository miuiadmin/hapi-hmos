#!/usr/bin/env bash
# tools/setup-hooks.sh
# 一次性启用仓库内置 git hooks：把 core.hooksPath 指向 .githooks。
# .git/hooks/ 不纳入版本控制，故 hooks 放仓库内 .githooks/ + 此脚本配置 hooksPath，
# 每个 clone 后运行一次即可（含新机器、CI）。
#
# 用法：bash tools/setup-hooks.sh

set -euo pipefail

# 定位仓库根（支持从任意子目录调用）
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
  echo "❌ 不在 git 仓库内" >&2
  exit 1
}
cd "$REPO_ROOT"

if [[ ! -d ".githooks" ]]; then
  echo "❌ 仓库内无 .githooks 目录" >&2
  exit 1
fi

# 配置 hooksPath（仓库级，写入 .git/config，不影响全局）
git config core.hooksPath .githooks

# 确保 hook 可执行（Windows clone 可能丢可执行位）
chmod +x .githooks/* 2>/dev/null || true

CURRENT="$(git config core.hooksPath)"
echo "✅ git hooks 已启用（core.hooksPath = ${CURRENT}）"
echo "   pre-commit：当前为占位 no-op（hapi 暂无 changelog 闸）；在此添加自定义检查。"
echo "   关闭：git config --unset core.hooksPath"

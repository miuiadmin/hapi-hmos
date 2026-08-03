#!/usr/bin/env bash
# 下载站配置模板 — 复制为 config.sh 后填值(新架构 2026-08-03:纯静态站,免 token,上传走 rsync over ssh)
# 由 dist.sh / sync-server.sh / publish.sh source。
# ⚠️ 改脚本逻辑(dist/sync/publish)须与 berry3 同名脚本同步(逐字节一致)。

APP=""                         # slug = /opt/dist 子目录 + URL 段(berry | hapi | ...)
TITLE=""                       # 横幅显示名
BUNDLE_NAME=""                 # OTA bundleName(客户端校验 === 本机包名;88 共存版 = base + "88")
PKG_PREFIX=""                  # 包文件名前缀(<prefix>-<version>-88-release.app)
PKG_GLOB=""                    # dist 产物 glob(如 hapi-*.app)
BUILD_CMD="tools/pack.sh"      # 构建钩子(产 .app 到项目根 output/)
APP_JSON="AppScope/app.json5"  # versionName/versionCode 来源
CHANGELOG_FILE=""              # changelog 来源(相对项目根;空 = [])
PROTECT_FILES=()               # 打包前后字节备份+恢复的文件(相对项目根)

PUBLIC_URL="https://berry.flyme.chat:8443"  # 静态站对外地址(Caddy :8443)
SSH_TARGET="aws"                            # ~/.ssh/config 别名
REMOTE_ROOT=""                              # 该 app 静态根(/opt/dist/<app>)
KEEP_VERSIONS="3"                           # archive/ 保留最近 N 个日期

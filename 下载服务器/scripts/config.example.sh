#!/usr/bin/env bash
# 下载服务器配置模板
# 用法：复制为 config.sh 后填值（config.sh 含 token，已被 .gitignore 排除，不进仓库）
# 首次运行 dist.sh / sync-server.sh / publish.sh 时会自动从本模板复制生成 config.sh
# 由三个脚本 source 引用
#
# ⚠️ hapi 复用 berry 同一台下载站服务器（nodebook 单服务），但用独立路由 /hapi、
#    独立存储 /opt/hapi-dist、独立 token HAPI_TOKEN（与 berry 的 BERRY_TOKEN 互不影响）。
#    下载站对外经 Caddy:8443 暴露（PUBLIC_URL）。本目录只管打包 + 上传归档文件。

SERVER_HOST="berry.flyme.chat"  # 服务器对外域名（复用 berry 同服务器；DNS 解析到实际机器 IP；HTTP/Caddy 全用此域名，换机只改 DNS 零改配置）
SSH_USER="root"                   # SSH 用户（历史残留：现走 HTTP 上传不用 SSH，保留供未来排错/手动 rsync）
REMOTE_ROOT="/opt/hapi-dist"      # 服务器归档根目录（nodebook 读 FILES_ROOT=$REMOTE_ROOT/files/archive；hapi 独立存储，与 berry 的 /opt/berry-dist 平行）
TOKEN=""                          # 访问 token（= nodebook .env 的 HAPI_TOKEN；与 berry 的 BERRY_TOKEN 相互独立；上传/访问共用）
PUBLIC_URL=""                     # 下载站对外地址（nodebook :8443 /hapi），形如 https://berry.flyme.chat:8443（Caddy https_port=8443，443 被 reality 占；域名经 DNS 指向 SERVER_HOST）
KEEP_VERSIONS="3"                 # 归档保留最近多少个版本，超出自动清理（?keep=N 传服务端按全局最新优先保留；空间大了可调大如 100，≤0 则不清理）

#!/usr/bin/env bash
# deploy-server.sh — 上线 nodebook-rs「多 App OTA 托管」改造到 awssg(47.130.2.49)。
#
# 在本机(Mac)跑:scp 新二进制 → 服务端加 HAPI_* 键 → 建归档目录 → 备份换二进制 → 重启 → 冒烟。
# ★前置:已跑 nodebook-rs/cross/build.sh(产物 ~/.cargo-target/x86_64-unknown-linux-musl/ship/nodebook)。
# ★SSH:用你日常能连 awssg 的终端跑(本机出口 IP 须在服务端 sshd 白名单)。
#
# 用法:
#   HAPI_TOKEN=<48位hex> bash 下载服务器/scripts/deploy-server.sh
#   不传 HAPI_TOKEN → 脚本自动 openssl rand 生成并打印(记下来,同步写进本地 config.sh 的 TOKEN=)。
#
# 幂等:.env 已有 HAPI_TOKEN 则跳过追加;二进制每次备份 .bak.<ts>;可重复跑。
# 回滚:见末尾提示(二进制层 / .env 层)。
set -euo pipefail

SERVER=root@47.130.2.49
REMOTE_BIN=/usr/local/bin/nodebook-rs
BIN="$HOME/.cargo-target/x86_64-unknown-linux-musl/ship/nodebook"
FILES_ROOT=/opt/hapi-dist/files/archive
PUBHOST=berry.flyme.chat:8443
KEEP=3
SSHO="-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20"

# ── token ─────────────────────────────────────────────
if [ -z "${HAPI_TOKEN:-}" ]; then
  HAPI_TOKEN=$(openssl rand -hex 24)
  echo "⚠️  未传 HAPI_TOKEN,已生成: $HAPI_TOKEN"
  echo "    记下来 → 同步写进 下载服务器/scripts/config.sh 的 TOKEN= 与服务端(本脚本会写服务端)"
fi

# ── 前置检查 ───────────────────────────────────────────
if [ ! -f "$BIN" ]; then
  echo "❌ 二进制不存在: $BIN"
  echo "   先跑:cd nodebook-rs && ./cross/build.sh"
  exit 1
fi
echo "本地二进制: $BIN ($(file "$BIN" | cut -d, -f2))"

echo "==> [1/4] scp 新二进制 → $SERVER:$REMOTE_BIN.new"
scp $SSHO "$BIN" "$SERVER:$REMOTE_BIN.new"

echo "==> [2/4] 服务端:.env 加 HAPI_*(幂等)+ 建归档目录 + 备份换二进制 + 重启"
ssh $SSHO "$SERVER" "HAPI_TOKEN=$HAPI_TOKEN FILES_ROOT=$FILES_ROOT PUBHOST=$PUBHOST KEEP=$KEEP REMOTE_BIN=$REMOTE_BIN bash -s" <<'REMOTE'
set -euo pipefail
cd /root/nodebook-rs
ts=$(date +%s)

# .env 加 HAPI_* 键(已有 HAPI_TOKEN 则跳过 → 幂等)
cp .env ".env.bak.$ts"
if ! grep -q '^HAPI_TOKEN=' .env; then
  cat >> .env <<EOF

# ===== hapi 下载站(多 App OTA 托管)=====
HAPI_TOKEN=$HAPI_TOKEN
HAPI_FILES_ROOT=$FILES_ROOT
HAPI_KEEP_VERSIONS=$KEEP
HAPI_HOST=$PUBHOST
EOF
  echo "  .env 已追加 HAPI_* 键"
else
  echo "  .env 已有 HAPI_TOKEN(跳过追加;换 token 须手动改 .env 的 HAPI_TOKEN=)"
fi
echo "  当前 HAPI_ 键名:"; grep -oE '^HAPI_[A-Z_]+=' .env | sort -u | sed 's/^/    /'

# 归档目录
mkdir -p "$FILES_ROOT"
echo "  归档目录: $FILES_ROOT ($( [ -d "$FILES_ROOT" ] && echo ok || echo MISSING ))"

# 备份在跑二进制 + 原子换 + 重启
cp "$REMOTE_BIN" "$REMOTE_BIN.bak.$ts"
chmod +x "$REMOTE_BIN.new"
mv -f "$REMOTE_BIN.new" "$REMOTE_BIN"
systemctl restart nodebook-rs
sleep 2
echo "  服务状态: $(systemctl is-active nodebook-rs)"
# 清理 6 个版本前的备份
ls -t "$REMOTE_BIN".bak.* 2>/dev/null | tail -n +7 | xargs rm -f 2>/dev/null || true
REMOTE

echo "==> [3/4] 冒烟(公网 HTTPS,免 token 即可判定)"
B="https://$PUBHOST"
code() { curl -sk -o /dev/null -w "%{http_code}" --max-time 20 "$1"; }
echo "  berry 无token    (须 401) : $(code "$B/berry")"
echo "  /ota/update.json (须 200) : $(code "$B/ota/update.json")   ← berry OTA 别名,零回归"
echo "  /hapi 无token    (须 401) : $(code "$B/hapi")   ← 改造前是 404,变 401 = 新二进制已上线"
echo "  /hapi-ota(路由存在): $(code "$B/hapi-ota/update.json")  ← 空清单 404-noRelease 也算路由存在"
echo
echo "==> [4/4] 完成"
echo "HAPI_TOKEN(写进本地 config.sh 的 TOKEN=): $HAPI_TOKEN"
echo "人工下载页: $B/hapi?t=$HAPI_TOKEN"
echo "OTA 清单  : $B/hapi-ota/update.json"
echo
echo "回滚(出问题时):"
echo "  二进制层:ssh $SERVER 'cd /usr/local/bin && L=\$(ls -t nodebook-rs.bak.*|head -1) && cp -f \"\$L\" nodebook-rs && chmod +x nodebook-rs && systemctl restart nodebook-rs'"
echo "  .env 层 :ssh $SERVER 'cd /root/nodebook-rs && L=\$(ls -t .env.bak.*|head -1) && cp -f \"\$L\" .env && systemctl restart nodebook-rs'"
echo
echo "判定:/hapi 由 404→401 且 /ota 仍 200 = 部署成功(berry 零回归)。"

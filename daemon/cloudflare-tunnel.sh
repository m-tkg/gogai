#!/bin/bash
# cloudflare-tunnel.sh
# cloudflared quick tunnel を起動し、割り当てられた URL を GitHub Gist に書き込む

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"

# .env を読み込む
if [ -f "$ENV_FILE" ]; then
  # shellcheck source=/dev/null
  source "$ENV_FILE"
fi

: "${GITHUB_PAT:?GITHUB_PAT が $ENV_FILE に設定されていません}"

GIST_ID="ae26d3342733622b70e9a2740d78cd47"
GIST_FILENAME="gistfile1.txt"
TARGET_URL="http://localhost:3040"
LOGFILE="/tmp/cloudflared-tunnel.log"

rm -f "$LOGFILE"

echo "[cloudflare-tunnel] Starting tunnel -> $TARGET_URL"

# cloudflared をバックグラウンドで起動（stdout/stderr をログファイルへ）
cloudflared tunnel --url "$TARGET_URL" >> "$LOGFILE" 2>&1 &
CF_PID=$!

# URL が出力されるまで最大 60 秒待機
TUNNEL_URL=""
for i in $(seq 1 30); do
  sleep 2
  TUNNEL_URL=$(grep -oE 'https://[a-zA-Z0-9-]+\.trycloudflare\.com' "$LOGFILE" 2>/dev/null | head -1)
  if [ -n "$TUNNEL_URL" ]; then
    break
  fi
done

if [ -z "$TUNNEL_URL" ]; then
  echo "[cloudflare-tunnel] ERROR: 60 秒以内にトンネル URL を取得できませんでした" >&2
  cat "$LOGFILE" >&2
  kill "$CF_PID" 2>/dev/null
  exit 1
fi

echo "[cloudflare-tunnel] Tunnel URL: $TUNNEL_URL"

# GitHub Gist を更新
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -X PATCH \
  -H "Authorization: token $GITHUB_PAT" \
  -H "Content-Type: application/json" \
  -d "{\"files\":{\"$GIST_FILENAME\":{\"content\":\"$TUNNEL_URL\"}}}" \
  "https://api.github.com/gists/$GIST_ID")

if [ "$HTTP_STATUS" = "200" ]; then
  echo "[cloudflare-tunnel] Gist を更新しました: $TUNNEL_URL"
else
  echo "[cloudflare-tunnel] WARNING: Gist 更新失敗 (HTTP $HTTP_STATUS)" >&2
fi

# cloudflared が終了するまで待機（サービスのメインプロセスとして生存し続ける）
wait "$CF_PID"

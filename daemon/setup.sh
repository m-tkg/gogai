#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_USER="${SUDO_USER:-$(whoami)}"

echo "=== Gogai daemon setup ==="

# サービスファイルをコピー
sudo cp "$SCRIPT_DIR/gogai-backend.service" "$SYSTEMD_DIR/"
sudo cp "$SCRIPT_DIR/gogai-frontend.service" "$SYSTEMD_DIR/"

# systemd をリロード
sudo systemctl daemon-reload

# 自動起動を有効化
sudo systemctl enable gogai-backend
sudo systemctl enable gogai-frontend

# サービスを起動
sudo systemctl start gogai-backend
sudo systemctl start gogai-frontend

# 旧バージョンが導入した公開トンネルのサービスが残っていれば停止・無効化・削除する
# （再実行しても復活しない。存在しなければ何もしない）
if [ -f "$SYSTEMD_DIR/gogai-cloudflare.service" ]; then
  sudo systemctl disable --now gogai-cloudflare || true
  sudo systemctl reset-failed gogai-cloudflare 2>/dev/null || true
  sudo rm -f "$SYSTEMD_DIR/gogai-cloudflare.service"
  sudo systemctl daemon-reload
fi

# 管理 API（更新確認・git pull して再起動）は ADMIN_SECRET が未設定だと全拒否になる。
BACKEND_ENV="$SCRIPT_DIR/backend.env"
if [ ! -f "$BACKEND_ENV" ] || ! grep -q '^ADMIN_SECRET=[^[:space:]"'"'"']' "$BACKEND_ENV"; then
  echo ""
  echo "注意: daemon/backend.env に ADMIN_SECRET が未設定のため、管理 API は無効（403）です。"
  echo "      使う場合は以下を実行し、アプリ側の「管理シークレット」にも同じ値を設定してください:"
  echo "        (umask 077; printf 'ADMIN_SECRET=%s\\n' \"\$(openssl rand -hex 32)\" >> $BACKEND_ENV)"
  echo "        sudo systemctl restart gogai-backend"
fi

# アプリ内「git pull して再起動」ボタン用: パスワードなしで systemctl restart を許可
SUDOERS_FILE="/etc/sudoers.d/gogai"
echo "${SERVICE_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart gogai-backend gogai-frontend" \
  | sudo tee "$SUDOERS_FILE" > /dev/null
sudo chmod 440 "$SUDOERS_FILE"
echo "sudoers: ${SUDOERS_FILE} を設定しました (${SERVICE_USER})"

echo ""
echo "=== 完了 ==="
echo "状態確認: sudo systemctl status gogai-backend gogai-frontend"
echo "ログ確認: journalctl -u gogai-backend -f"
echo "         journalctl -u gogai-frontend -f"

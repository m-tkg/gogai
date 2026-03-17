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

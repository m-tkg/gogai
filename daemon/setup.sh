#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSTEMD_DIR="/etc/systemd/system"
SERVICE_USER="${SUDO_USER:-$(whoami)}"

echo "=== Gogai daemon setup ==="

# スクリプトに実行権限を付与
chmod +x "$SCRIPT_DIR/cloudflare-tunnel.sh"

# サービスファイルをコピー
sudo cp "$SCRIPT_DIR/gogai-backend.service" "$SYSTEMD_DIR/"
sudo cp "$SCRIPT_DIR/gogai-frontend.service" "$SYSTEMD_DIR/"
sudo cp "$SCRIPT_DIR/gogai-cloudflare.service" "$SYSTEMD_DIR/"

# systemd をリロード
sudo systemctl daemon-reload

# 自動起動を有効化
sudo systemctl enable gogai-backend
sudo systemctl enable gogai-frontend

# サービスを起動
sudo systemctl start gogai-backend
sudo systemctl start gogai-frontend

# gogai-cloudflare は daemon/.env に GITHUB_PAT(gist スコープ)が必須なため、
# 未設定のまま有効化するとクラッシュループしてしまう。.env がある場合のみ自動起動する。
if [ -f "$SCRIPT_DIR/.env" ]; then
  sudo systemctl enable gogai-cloudflare
  sudo systemctl start gogai-cloudflare
  CLOUDFLARE_ENABLED=1
else
  CLOUDFLARE_ENABLED=0
  echo ""
  echo "警告: daemon/.env が見つからないため gogai-cloudflare は起動していません。"
  echo "      Cloudflare トンネル(リモートアクセス用 URL)を使う場合は以下を実行してください:"
  echo "        echo \"GITHUB_PAT=ghp_xxxx\" > $SCRIPT_DIR/.env"
  echo "        chmod 600 $SCRIPT_DIR/.env"
  echo "        sudo systemctl enable --now gogai-cloudflare"
fi

# アプリ内「git pull して再起動」ボタン用: パスワードなしで systemctl restart を許可
SUDOERS_FILE="/etc/sudoers.d/gogai"
echo "${SERVICE_USER} ALL=(ALL) NOPASSWD: /usr/bin/systemctl restart gogai-backend gogai-frontend" \
  | sudo tee "$SUDOERS_FILE" > /dev/null
sudo chmod 440 "$SUDOERS_FILE"
echo "sudoers: ${SUDOERS_FILE} を設定しました (${SERVICE_USER})"

echo ""
echo "=== 完了 ==="
if [ "$CLOUDFLARE_ENABLED" = "1" ]; then
  echo "状態確認: sudo systemctl status gogai-backend gogai-frontend gogai-cloudflare"
  echo "ログ確認: journalctl -u gogai-backend -f"
  echo "         journalctl -u gogai-frontend -f"
  echo "         journalctl -u gogai-cloudflare -f"
else
  echo "状態確認: sudo systemctl status gogai-backend gogai-frontend"
  echo "ログ確認: journalctl -u gogai-backend -f"
  echo "         journalctl -u gogai-frontend -f"
fi

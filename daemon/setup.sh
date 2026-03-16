#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SYSTEMD_DIR="/etc/systemd/system"

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

echo ""
echo "=== 完了 ==="
echo "状態確認: sudo systemctl status gogai-backend gogai-frontend"
echo "ログ確認: journalctl -u gogai-backend -f"
echo "         journalctl -u gogai-frontend -f"

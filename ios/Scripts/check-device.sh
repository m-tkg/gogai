#!/bin/sh
# 指定した DEVICE_ID が devicectl から見て接続済みか確認する。
# 個人の実機 UDID が Makefile のデフォルト値になっているため、他の環境で
# 実行された場合や実機が未接続の場合に devicectl の分かりにくいエラーで
# 落ちるのを防ぎ、対処方法を示した分かりやすいエラーを出す。
set -eu

device_id="${1:?使用法: check-device.sh <DEVICE_ID>}"

line="$(xcrun devicectl list devices 2>/dev/null | grep "$device_id" || true)"

if [ -z "$line" ]; then
  echo "error: DEVICE_ID=$device_id が見つかりません。" >&2
  echo "  'xcrun devicectl list devices' で接続中の実機の Identifier を確認し、" >&2
  echo "  make ios-deploy DEVICE_ID=<uuid> を指定してください。" >&2
  exit 1
fi

case "$line" in
  *connected*|*available*)
    exit 0
    ;;
  *)
    echo "error: DEVICE_ID=$device_id は接続されていません。ケーブル/Wi-Fi 接続を確認してください。" >&2
    echo "  現在の状態: $line" >&2
    exit 1
    ;;
esac

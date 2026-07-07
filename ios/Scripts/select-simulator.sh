#!/bin/sh
# 利用可能な iPhone シミュレーターの名前を1件出力する。
# シミュレーター一覧は Xcode バージョンアップ等で入れ替わるため、
# Makefile に固定端末名をハードコードせず都度解決する。
set -eu

name="$(xcrun simctl list devices available 2>/dev/null \
  | grep -E '^[[:space:]]+iPhone' \
  | head -1 \
  | sed -E 's/^[[:space:]]*([^(]+)\(.*/\1/' \
  | sed -E 's/[[:space:]]*$//')"

if [ -z "$name" ]; then
  echo "error: 利用可能な iPhone シミュレーターが見つかりません" >&2
  exit 1
fi

echo "$name"

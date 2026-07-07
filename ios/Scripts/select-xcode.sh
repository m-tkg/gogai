#!/bin/sh
# 使用する Xcode の DEVELOPER_DIR を1件出力する。
# ローカル開発機は iOS 26/27 ベータ SDK(Foundation Models 等)を使うため
# Xcode-beta.app を優先する。無ければ CI と同じロジックでインストール済みの
# 最新 Xcode を動的解決する(Makefile と CI でロジックが二重管理・食い違うのを防ぐ)。
set -eu

if [ -d /Applications/Xcode-beta.app ]; then
  echo /Applications/Xcode-beta.app/Contents/Developer
  exit 0
fi

latest="$(ls -d /Applications/Xcode*.app 2>/dev/null | sort -V | tail -1)"

if [ -z "$latest" ]; then
  echo "error: 利用可能な Xcode が見つかりません" >&2
  exit 1
fi

echo "$latest/Contents/Developer"

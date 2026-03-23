#!/bin/sh
set -e

# Xcode Cloud: Metal toolchain を事前にダウンロードしてマウントを確立する
# Mac Catalyst ビルド時に "Search path not found" エラーが出る問題を回避

echo "==> Triggering Metal toolchain download..."
xcrun metal --version 2>/dev/null || true

echo "==> Pre-build setup complete."

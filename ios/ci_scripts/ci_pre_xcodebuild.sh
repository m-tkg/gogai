#!/bin/sh
set -e

# Xcode Cloud: Metal toolchain を事前にダウンロードしてマウントを確立する
# Mac Catalyst ビルド時に "Search path not found" エラーが出る問題を回避

echo "==> Triggering Metal toolchain initialization..."
xcrun metal --version 2>/dev/null || true
xcrun -sdk macosx metal --version 2>/dev/null || true

# metal バイナリのパスから toolchain root を導出し、
# maccatalyst ディレクトリがマウントされるまで最大 90 秒待機する
METAL_BIN=$(xcrun --find metal 2>/dev/null || true)

if [ -n "$METAL_BIN" ]; then
  # metal バイナリは <toolchain>/usr/bin/metal にあるため 3 段上がる
  TOOLCHAIN_ROOT=$(cd "$(dirname "$METAL_BIN")/../../.." && pwd)
  MACCATALYST_PATH="$TOOLCHAIN_ROOT/usr/lib/swift/maccatalyst"

  echo "==> Toolchain root: $TOOLCHAIN_ROOT"
  echo "==> Waiting for maccatalyst path: $MACCATALYST_PATH"

  i=0
  while [ ! -d "$MACCATALYST_PATH" ] && [ "$i" -lt 90 ]; do
    sleep 1
    i=$((i + 1))
    if [ $((i % 10)) -eq 0 ]; then
      echo "==> Still waiting... (${i}s)"
    fi
  done

  if [ -d "$MACCATALYST_PATH" ]; then
    echo "==> Metal toolchain maccatalyst ready (${i}s elapsed)."
  else
    echo "==> Warning: maccatalyst not found after 90s, proceeding anyway."
  fi
else
  echo "==> Warning: metal binary not found via xcrun."
fi

echo "==> Pre-build setup complete."

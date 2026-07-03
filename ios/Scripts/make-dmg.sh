#!/bin/bash
# .app から配布用 DMG を作成する(Applications へのショートカット同梱)。
# Makefile の mac-dmg と GitHub Actions の両方から呼ばれる共通スクリプト。
#
# Usage: make-dmg.sh <app_path> <volume_name> <dmg_path>
set -euo pipefail

APP_PATH="$1"
VOLUME_NAME="$2"
DMG_PATH="$3"

STAGING=$(mktemp -d)
trap 'rm -rf "$STAGING"' EXIT

cp -R "$APP_PATH" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

rm -f "$DMG_PATH"
hdiutil create -volname "$VOLUME_NAME" \
  -srcfolder "$STAGING" \
  -ov -format UDZO \
  "$DMG_PATH"

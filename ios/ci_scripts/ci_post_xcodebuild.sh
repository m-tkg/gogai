#!/bin/sh
set -e

# Xcode Cloud: アーカイブ後に .dmg を作成する
# 実行タイミング: xcodebuild の後（Notarize の前）

# Mac Catalyst ビルド以外はスキップ
if [ "$CI_PRODUCT_PLATFORM" != "macOS" ]; then
  echo "Not a macOS build, skipping DMG creation."
  exit 0
fi

APP_PATH="$CI_ARCHIVE_PATH/Products/Applications/Gogai.app"
DMG_PATH="$CI_DERIVED_DATA_PATH/Gogai.dmg"

if [ ! -d "$APP_PATH" ]; then
  echo "Gogai.app not found at $APP_PATH, skipping DMG creation."
  exit 0
fi

echo "==> Creating DMG at $DMG_PATH"
hdiutil create -volname "Gogai" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH"

# App Store Connect のビルド詳細からダウンロードできるようアーカイブにもコピー
cp "$DMG_PATH" "$CI_ARCHIVE_PATH/Gogai.dmg"

echo "==> DMG created: $DMG_PATH"

#!/bin/sh
set -e

# Xcode Cloud: アーカイブ後に .dmg を作成し GitHub Releases にアップロードする
# 実行タイミング: xcodebuild の後（Notarize の前）

# Mac Catalyst ビルド以外はスキップ
if [ "$CI_PRODUCT_PLATFORM" != "macOS" ]; then
  echo "Not a macOS build (CI_PRODUCT_PLATFORM=${CI_PRODUCT_PLATFORM}), skipping DMG creation."
  exit 0
fi

REPO="m-tkg/gogai"
APP_PATH="$CI_ARCHIVE_PATH/Products/Applications/Gogai.app"
DMG_PATH="$CI_DERIVED_DATA_PATH/Gogai.dmg"

if [ ! -d "$APP_PATH" ]; then
  echo "==> Gogai.app not found at $APP_PATH, skipping."
  exit 1
fi

# バージョン取得
VERSION=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleShortVersionString" "$CI_ARCHIVE_PATH/Info.plist")
BUILD=$(/usr/libexec/PlistBuddy -c "Print :ApplicationProperties:CFBundleVersion" "$CI_ARCHIVE_PATH/Info.plist")
TAG="mac-v${VERSION}-${BUILD}"
echo "==> Version: $VERSION ($BUILD), Tag: $TAG"

# DMG 作成
echo "==> Creating DMG..."
hdiutil create -volname "Gogai" \
  -srcfolder "$APP_PATH" \
  -ov -format UDZO \
  "$DMG_PATH"
echo "==> DMG created: $DMG_PATH"

# GITHUB_TOKEN チェック
if [ -z "$GITHUB_TOKEN" ]; then
  echo "==> GITHUB_TOKEN is not set. Skipping GitHub Releases upload."
  exit 0
fi

API="https://api.github.com/repos/${REPO}"
AUTH="Authorization: Bearer $GITHUB_TOKEN"

# 既存のリリースを確認（同タグがあれば再利用）
echo "==> Checking for existing release: $TAG"
RELEASE=$(curl -sf -H "$AUTH" "$API/releases/tags/$TAG" || true)

if [ -n "$RELEASE" ]; then
  RELEASE_ID=$(echo "$RELEASE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  echo "==> Using existing release (id=$RELEASE_ID)"
else
  # 新規リリース作成
  echo "==> Creating new release: $TAG"
  RELEASE=$(curl -sf -X POST -H "$AUTH" -H "Content-Type: application/json" \
    "$API/releases" \
    -d "{\"tag_name\":\"$TAG\",\"name\":\"Gogai $VERSION (macOS)\",\"draft\":false,\"prerelease\":false}")
  RELEASE_ID=$(echo "$RELEASE" | python3 -c "import sys,json; print(json.load(sys.stdin)['id'])")
  echo "==> Release created (id=$RELEASE_ID)"
fi

# DMG をアップロード
echo "==> Uploading Gogai.dmg..."
curl -sf -X POST \
  -H "$AUTH" \
  -H "Content-Type: application/octet-stream" \
  "https://uploads.github.com/repos/${REPO}/releases/${RELEASE_ID}/assets?name=Gogai.dmg" \
  --data-binary @"$DMG_PATH"

echo "==> Upload complete. https://github.com/${REPO}/releases/tag/${TAG}"

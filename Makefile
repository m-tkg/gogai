.PHONY: install dev dev-backend dev-frontend build test test-watch typecheck clean \
        docker-up docker-down docker-build docker-logs docker-clean \
        daemon-setup daemon-start daemon-stop daemon-restart daemon-status daemon-logs \
        restart-daemon ios-sync-icons ios-build ios-test ios-deploy \
        mac-archive mac-export mac-dmg mac-notarize mac-distribute release-tag

# ── ローカル開発 ──────────────────────────────────────────

# 両プロジェクトの依存関係をインストール
install:
	cd backend && npm install
	cd frontend && npm install

# バックエンド・フロントエンドを並列起動
dev:
	$(MAKE) -j2 dev-backend dev-frontend

# バックエンドのみ起動
dev-backend:
	cd backend && npm run dev

# フロントエンドのみ起動
dev-frontend:
	cd frontend && npm run dev

# 両プロジェクトをビルド
build:
	cd backend && npm run build
	cd frontend && npm run build

# バックエンド + フロントエンドのテストを実行
test:
	cd backend && npm test
	cd frontend && npm test

# バックエンドのテストをウォッチモードで実行
test-watch:
	cd backend && npm run test:watch

# 両プロジェクトの型チェック
typecheck:
	cd backend && npx tsc --noEmit
	cd frontend && npx tsc --noEmit

# クリーンアップ
clean:
	rm -rf backend/dist frontend/dist

# ── Docker ───────────────────────────────────────────────

# コンテナをビルドして起動（http://localhost:8080）
docker-up:
	docker compose up -d

# コンテナを停止
docker-down:
	docker compose down

# イメージを再ビルドして起動
docker-build:
	docker compose up -d --build

# ログを表示
docker-logs:
	docker compose logs -f

# コンテナ・イメージ・ボリュームをすべて削除
docker-clean:
	docker compose down -v --rmi all

# ── Daemon (systemd / Raspberry Pi) ──────────────────────
# サービスをインストールして自動起動を有効化
daemon-setup:
	bash daemon/setup.sh

# サービスを起動（cloudflare トンネルは daemon/.env 未設定なら未インストールのため対象外）
daemon-start:
	sudo systemctl start gogai-backend gogai-frontend
	-sudo systemctl start gogai-cloudflare

# サービスを停止
daemon-stop:
	sudo systemctl stop gogai-backend gogai-frontend
	-sudo systemctl stop gogai-cloudflare

# サービスを再起動（cloudflare トンネルは対象外: 再起動すると quick tunnel の URL が
# 変わってしまうため、コード更新時の「git pull して再起動」では触らない）
daemon-restart:
	sudo systemctl restart gogai-backend gogai-frontend

# サービスの状態確認
daemon-status:
	sudo systemctl status gogai-backend gogai-frontend
	-sudo systemctl status gogai-cloudflare

# ログをリアルタイム表示
daemon-logs:
	journalctl -u gogai-backend -u gogai-frontend -u gogai-cloudflare -f

# git pull して再起動（設定画面ボタンから呼ばれる）
restart-daemon: daemon-restart

# ── iOS ──────────────────────────────────────────────────────

# appiconset/ のアイコンを xcassets へ同期
ios-sync-icons:
	cp ios/appiconset/*.png ios/Gogai/Assets.xcassets/AppIcon.appiconset/
	cp ios/appiconset/Contents.json ios/Gogai/Assets.xcassets/AppIcon.appiconset/

# インストール済みシミュレーターは Xcode バージョンアップ等で入れ替わるため、
# 固定端末名をハードコードせず利用可能な iPhone シミュレーターを都度解決する
IOS_SIMULATOR_NAME := $(shell ios/Scripts/select-simulator.sh)

# 使用する Xcode の DEVELOPER_DIR を都度解決する(CI と共通のロジック、詳細は select-xcode.sh 参照)
IOS_DEVELOPER_DIR := $(shell ios/Scripts/select-xcode.sh)

# アイコン同期してビルド（シミュレーター）
ios-build: ios-sync-icons
	cd ios && xcodebuild build -project Gogai.xcodeproj -scheme Gogai \
		-destination "platform=iOS Simulator,name=$(IOS_SIMULATOR_NAME)" -quiet

# iOS ユニットテストを実行
ios-test:
	cd ios && DEVELOPER_DIR=$(IOS_DEVELOPER_DIR) \
		xcodebuild test -project Gogai.xcodeproj -scheme Gogai \
		-destination "platform=iOS Simulator,name=$(IOS_SIMULATOR_NAME)" -quiet

# Release ビルドして実機に転送して起動
DEVICE_ID    ?= 620080DD-019A-5477-8F2D-96E9E0C8C538
DERIVED_DATA  = ios/.build
BUNDLE_ID     = com.mtkg.gogai

ios-deploy: ios-sync-icons
	@echo "==> Checking device $(DEVICE_ID) is connected..."
	@DEVELOPER_DIR=$(IOS_DEVELOPER_DIR) ios/Scripts/check-device.sh $(DEVICE_ID)
	@echo "==> Building Release for device..."
	cd ios && DEVELOPER_DIR=$(IOS_DEVELOPER_DIR) \
		xcodebuild build \
		-project Gogai.xcodeproj \
		-scheme Gogai \
		-configuration Release \
		-destination "platform=iOS,id=$(DEVICE_ID)" \
		-derivedDataPath ../.build/ios \
		-allowProvisioningUpdates \
		-quiet
	@echo "==> Installing on device..."
	DEVELOPER_DIR=$(IOS_DEVELOPER_DIR) \
		xcrun devicectl device install app \
		--device $(DEVICE_ID) \
		".build/ios/Build/Products/Release-iphoneos/Gogai.app"
	@echo "==> Launching app..."
	DEVELOPER_DIR=$(IOS_DEVELOPER_DIR) \
		xcrun devicectl device process launch \
		--device $(DEVICE_ID) \
		$(BUNDLE_ID)

# ── Mac 配布 ──────────────────────────────────────────────────

# 必須: make mac-distribute APPLE_ID=you@example.com APPLE_APP_PASSWORD=xxxx-xxxx-xxxx-xxxx
APPLE_ID           ?=
APPLE_APP_PASSWORD ?=
MAC_TEAM_ID         = G72M73C546
MAC_BUILD_DIR       = .build/mac
MAC_ARCHIVE_PATH    = $(MAC_BUILD_DIR)/Gogai.xcarchive
MAC_EXPORT_PATH     = $(MAC_BUILD_DIR)/export
MAC_DMG_PATH        = $(MAC_BUILD_DIR)/Gogai.dmg

# Step 1: macOS (Mac Catalyst) 向けにアーカイブ
mac-archive: ios-sync-icons
	@echo "==> Archiving for macOS (Mac Catalyst)..."
	mkdir -p $(MAC_BUILD_DIR)
	cd ios && DEVELOPER_DIR=$(IOS_DEVELOPER_DIR) \
		xcodebuild archive \
		-project Gogai.xcodeproj \
		-scheme Gogai \
		-configuration Release \
		-destination "platform=macOS,variant=Mac Catalyst" \
		-archivePath ../$(MAC_ARCHIVE_PATH) \
		-allowProvisioningUpdates \
		-quiet
	@echo "==> Archive done: $(MAC_ARCHIVE_PATH)"

# Step 2: Developer ID で署名してエクスポート
mac-export: mac-archive
	@echo "==> Exporting with Developer ID..."
	rm -rf $(MAC_EXPORT_PATH)
	DEVELOPER_DIR=$(IOS_DEVELOPER_DIR) \
		xcodebuild -exportArchive \
		-archivePath $(MAC_ARCHIVE_PATH) \
		-exportPath $(MAC_EXPORT_PATH) \
		-exportOptionsPlist ios/ExportOptions-mac.plist \
		-allowProvisioningUpdates
	@echo "==> Export done: $(MAC_EXPORT_PATH)"

# Step 3: .dmg を作成(Applications へのショートカット同梱)
mac-dmg: mac-export
	@echo "==> Creating DMG..."
	bash ios/Scripts/make-dmg.sh "$(MAC_EXPORT_PATH)/Gogai.app" "Gogai" "$(MAC_DMG_PATH)"
	@echo "==> DMG created: $(MAC_DMG_PATH)"

# Step 4: Notarize + Staple
mac-notarize: mac-dmg
	@[ -n "$(APPLE_ID)" ] || (echo "ERROR: APPLE_ID が未設定です。make mac-notarize APPLE_ID=you@example.com APPLE_APP_PASSWORD=xxxx" && exit 1)
	@[ -n "$(APPLE_APP_PASSWORD)" ] || (echo "ERROR: APPLE_APP_PASSWORD が未設定です。" && exit 1)
	@echo "==> Submitting for notarization (this takes a few minutes)..."
	xcrun notarytool submit "$(MAC_DMG_PATH)" \
		--apple-id "$(APPLE_ID)" \
		--password "$(APPLE_APP_PASSWORD)" \
		--team-id $(MAC_TEAM_ID) \
		--wait
	@echo "==> Stapling notarization ticket..."
	xcrun stapler staple "$(MAC_DMG_PATH)"
	@echo "==> Notarization complete: $(MAC_DMG_PATH)"

# 全工程まとめて実行
mac-distribute: mac-notarize
	@echo ""
	@echo "========================================="
	@echo "  配布用 DMG: $(MAC_DMG_PATH)"
	@echo "========================================="

# ── リリース ──────────────────────────────────────────────────

# project.pbxproj の MARKETING_VERSION から v{version} タグを作成して push する
release-tag:
	@versions="$$(grep 'MARKETING_VERSION = ' ios/Gogai.xcodeproj/project.pbxproj | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | sort -u)"; \
	if [ -z "$$versions" ]; then \
		echo "error: MARKETING_VERSION が project.pbxproj から取得できません" >&2; \
		exit 1; \
	fi; \
	if [ "$$(echo "$$versions" | wc -l | tr -d ' ')" != "1" ]; then \
		echo "error: MARKETING_VERSION の値が一致していません:" >&2; \
		echo "$$versions" >&2; \
		exit 1; \
	fi; \
	tag="v$$versions"; \
	branch="$$(git rev-parse --abbrev-ref HEAD)"; \
	if [ "$$branch" != "main" ]; then \
		echo "error: main ブランチで実行してください (現在: $$branch)" >&2; \
		exit 1; \
	fi; \
	if [ -n "$$(git status --porcelain)" ]; then \
		echo "error: 作業ツリーに未コミットの変更があります" >&2; \
		exit 1; \
	fi; \
	git fetch origin main --quiet; \
	if [ "$$(git rev-parse HEAD)" != "$$(git rev-parse origin/main)" ]; then \
		echo "error: ローカルの main が origin/main と同期していません" >&2; \
		exit 1; \
	fi; \
	if git rev-parse "$$tag" >/dev/null 2>&1; then \
		echo "error: タグ $$tag は既に存在します" >&2; \
		exit 1; \
	fi; \
	git tag -a "$$tag" -m "Release $$tag"; \
	git push origin "$$tag"; \
	echo "タグ $$tag を push しました。リリースワークフローがビルド・公開します。"

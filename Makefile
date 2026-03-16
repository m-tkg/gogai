.PHONY: install dev dev-backend dev-frontend build test test-watch typecheck clean \
        docker-up docker-down docker-build docker-logs docker-clean

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

# バックエンドのテストを実行
test:
	cd backend && npm test

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

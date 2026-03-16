.PHONY: install dev dev-backend dev-frontend build test lint clean

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

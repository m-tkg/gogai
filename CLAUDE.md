# Gogai — Claude Code 向けプロジェクト情報

## プロジェクト構成

モノレポ構成。`backend/` と `frontend/` は独立した npm プロジェクト。

```
gogai/
├── backend/    Node.js + Hono + TypeScript（ポート 3040）
├── frontend/   React 19 + Vite + Tailwind CSS v4（ポート 5173）
├── daemon/     systemd サービスファイル（Raspberry Pi 用）
├── docker-compose.yml
└── Makefile
```

## 開発コマンド

```bash
make dev            # バックエンド + フロントエンドを並列起動
make test           # バックエンドのテストを実行（Vitest、92 件）
make test-watch     # テストをウォッチモードで実行
make typecheck      # 型チェック（backend + frontend）
make docker-up      # Docker で起動（http://localhost:8080）
make daemon-restart # Raspberry Pi でサービスを再起動
```

## バックエンド

- **エントリーポイント**: `backend/src/index.ts`
- **ルーター**: `backend/src/routes/` (groups / feeds / articles / settings / admin)
- **サービス層**: `backend/src/services/`
- **DB スキーマ**: `backend/src/db/schema.ts`
- **テスト**: `backend/src/__tests__/`（92 件）

### DB（SQLite）

- パス: `backend/data/rss.db`（環境変数 `DB_PATH` で変更可）
- WAL モード有効、外部キー制約有効
- テーブル: `groups` → `feeds` → `articles`、`settings`
- 新カラム追加は `initSchema` 内で `ALTER TABLE ... ADD COLUMN` + try/catch で移行

### AI プロバイダー

設定ファイル: `backend/ai.config.json`

```json
{ "provider": "claude" }   // claude | openai | gemini
```

- `claude`: `~/.local/bin/claude -p` を `spawn` で呼び出す
  - **stdin を `/dev/null` にしないと exit 143 になる**（TTY チェック回避）
  - バイナリパスは環境変数 `CLAUDE_PATH` で上書き可能
- `openai`: 環境変数 `OPENAI_API_KEY` が必要
- `gemini`: 環境変数 `GEMINI_API_KEY` が必要

実装: `backend/src/services/providers/`

### AI キャッシュ

- `articles.ai_summary` / `ai_translation` カラムに結果を保存
- `/api/articles/:id/claude` はキャッシュ済みなら即返却
- `{ force: true }` を付けるとキャッシュを無視して再実行
- AI に渡すテキストは `article.link` から本文を fetch して取得（`article-content.ts`）
  - fetch 失敗時は RSS の `content` / `summary` にフォールバック

### RSS フィード自動検出（`feed-discovery.ts`）

ドメイン URL を渡すと RSS URL を自動解決する。優先順位:

1. Content-Type が XML 系 → そのまま返す
2. HTML の `<link rel="alternate">` タグを解析
3. 候補パス（`/feed`, `/rss`, `/feed.xml` など）を順に試す

### 記事の自動削除

サーバー起動時と 24 時間ごとに実行。
`settings` テーブルの `retention_days`（デフォルト 180）を毎回読んで判定。
`COALESCE(published_at, created_at)` が閾値より古い記事を削除。

### Admin エンドポイント（`routes/admin.ts`）

`POST /api/admin/restart` — `git pull` 実行後、0.3 秒遅延で `make restart-daemon` をバックグラウンド実行。
バックエンド自身が再起動されるため、レスポンスを先に返してから restart する。

## フロントエンド

- **エントリーポイント**: `frontend/src/App.tsx`
- **コンポーネント**: `Sidebar` / `ArticleList` / `ArticleDetail` / `Settings`
- **API クライアント**: `frontend/src/api/client.ts`（axios + TanStack Query）

### Vite プロキシ

`vite.config.ts` で `/api` を `http://localhost:3040` にプロキシ。
API クライアントの `BASE_URL` は空文字（相対パス）にすることで、
どのホストからアクセスしても正常に動作する。

### Tailwind CSS v4 の注意点

`frontend/src/index.css` で `@import "tailwindcss"` を使う（v3 の `@tailwind base` 構文は使わない）。
ダークモードは `@custom-variant dark (&:is(.dark, .dark *))` でクラスベース実装。

### ダークモード

- `document.documentElement` の `dark` クラスで切り替え
- 初期値: localStorage → システム設定の優先順
- `localStorage` キー: `darkMode`

### 翻訳タブ

`openTranslationTab()` で新しいウィンドウを開き、`marked.parse()` で Markdown → HTML に変換して表示。

## テスト指針

- TDD（t-wada 推奨スタイル）
- テストを先に書き、失敗を確認してからコミット、その後実装
- テストフレームワーク: Vitest（ESM モード）
- `vi.mock` でクラスをモックする場合は注意（ESM では constructor mock が機能しない場合がある）
  - 代替: 実クラスをインスタンス化して `typeof provider.run === 'function'` を検証

## 環境変数

| 変数 | デフォルト | 説明 |
|-----|---------|------|
| `PORT` | `3040` | バックエンドのポート番号 |
| `DB_PATH` | `backend/data/rss.db` | SQLite ファイルパス |
| `AI_CONFIG_PATH` | `backend/ai.config.json` | AI 設定ファイルパス |
| `CLAUDE_PATH` | `~/.local/bin/claude` | Claude CLI バイナリパス |
| `OPENAI_API_KEY` | — | OpenAI 使用時に必要 |
| `GEMINI_API_KEY` | — | Gemini 使用時に必要 |

## Docker Compose

- `backend` サービス: ポート非公開、ヘルスチェックあり（`GET /health`）
- `frontend` サービス: nginx でホスト、`/api/*` をバックエンドへリバースプロキシ
- `db-data` 名前付きボリューム: SQLite を永続化
- 外部アクセス: `http://localhost:8080`（環境変数 `PORT` で変更可）

## Raspberry Pi（systemd）

- サービスファイル: `daemon/gogai-backend.service` / `gogai-frontend.service`
- セットアップ: `bash daemon/setup.sh`
- backend / frontend ともに `host: 0.0.0.0` でバインドして LAN からアクセス可能
- 設定画面の「git pull && 再起動」ボタンでブラウザから更新可能

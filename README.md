# RSS Reader

Web ベースの RSS リーダー。将来的な iOS アプリ版への拡張を前提とした REST API 設計。

## 機能

- RSS フィードの追加・削除・グループ管理
- ドメイン URL からの RSS フィード自動検出
- 記事一覧（favicon・タイトル・本文プレビュー・日時表示）
- 未読管理（青い丸インジケーター）
- AI による記事の要約・翻訳（Claude CLI / OpenAI / Gemini）
- ダークモード（手動切替 + localStorage 永続化）
- 180 日以上経過した記事の自動削除

## 技術スタック

| レイヤー | 技術 |
|---------|------|
| Backend | Node.js + Hono + TypeScript + better-sqlite3 |
| Frontend | React 19 + Vite 8 + TanStack Query + Tailwind CSS v4 |
| DB | SQLite（WAL モード） |
| Test | Vitest（バックエンドのみ） |
| Infra | Docker Compose + nginx リバースプロキシ |

## ディレクトリ構成

```
rss-reader/
├── backend/
│   ├── src/
│   │   ├── db/schema.ts          # DB 初期化・スキーマ定義
│   │   ├── routes/               # Hono ルーター
│   │   │   ├── articles.ts
│   │   │   ├── feeds.ts
│   │   │   └── groups.ts
│   │   ├── services/             # ビジネスロジック
│   │   │   ├── ai-config.ts      # AI 設定ファイル読み込み
│   │   │   ├── ai-provider.ts    # AI プロバイダーインターフェース
│   │   │   ├── articles.ts
│   │   │   ├── feed-discovery.ts # RSS URL 自動検出
│   │   │   ├── feeds.ts
│   │   │   ├── groups.ts
│   │   │   ├── rss-fetcher.ts
│   │   │   └── providers/
│   │   │       ├── claude-cli.ts  # Claude Code CLI
│   │   │       ├── gemini.ts      # Google Gemini API
│   │   │       └── openai.ts      # OpenAI API
│   │   └── index.ts              # サーバーエントリーポイント
│   ├── ai.config.json            # AI プロバイダー設定
│   └── data/                     # SQLite DB（.gitignore 済み）
├── frontend/
│   └── src/
│       ├── api/client.ts         # API クライアント
│       ├── components/
│       │   ├── ArticleDetail.tsx
│       │   ├── ArticleList.tsx
│       │   └── Sidebar.tsx
│       └── App.tsx
├── docker-compose.yml
├── Makefile
└── README.md
```

## セットアップ

### ローカル開発

```bash
# 依存関係インストール
make install

# バックエンド・フロントエンドを同時起動
make dev
# → Backend: http://localhost:3000
# → Frontend: http://localhost:5173
```

### Docker

```bash
# 起動（http://localhost:8080）
make docker-up

# イメージを再ビルドして起動
make docker-build

# ログ確認
make docker-logs

# 停止
make docker-down
```

## AI 設定

`backend/ai.config.json` でプロバイダーを切り替えます。

```json
{
  "provider": "claude",
  "openai": { "model": "gpt-4o-mini" },
  "gemini": { "model": "gemini-2.0-flash" }
}
```

| provider | 必要な設定 |
|---------|----------|
| `claude` | Claude Code CLI がインストール済みであること |
| `openai` | 環境変数 `OPENAI_API_KEY` |
| `gemini` | 環境変数 `GEMINI_API_KEY` |

Claude CLI のバイナリパスを変更する場合は環境変数 `CLAUDE_PATH` で指定できます（デフォルト: `~/.local/bin/claude`）。

## API エンドポイント

### Groups

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/groups` | グループ一覧 |
| POST | `/api/groups` | グループ作成 `{ name }` |
| PUT | `/api/groups/:id` | グループ更新 `{ name }` |
| DELETE | `/api/groups/:id` | グループ削除 |

### Feeds

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/feeds` | フィード一覧 |
| POST | `/api/feeds` | フィード追加 `{ url, groupId? }` ※ドメインURLも可 |
| PUT | `/api/feeds/:id` | フィード更新 `{ title?, groupId? }` |
| DELETE | `/api/feeds/:id` | フィード削除（記事も CASCADE 削除） |
| POST | `/api/feeds/:id/refresh` | 記事を手動更新 |

### Articles

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/articles` | 記事一覧 `?feedId=&groupId=&unreadOnly=&limit=&offset=` |
| GET | `/api/articles/:id` | 記事詳細 |
| POST | `/api/articles/:id/read` | 既読にする |
| POST | `/api/articles/:id/unread` | 未読にする |
| POST | `/api/articles/:id/claude` | AI 処理 `{ action: "summarize" \| "translate" }` |

## DB スキーマ

```sql
groups    (id, name, created_at)
feeds     (id, url, title, favicon_url, group_id→groups, last_fetched_at, created_at)
articles  (id, feed_id→feeds, guid, title, link, summary, content, published_at, is_read, created_at)
```

- `feeds.group_id` は `ON DELETE SET NULL`（グループ削除時にフィードは残る）
- `articles.feed_id` は `ON DELETE CASCADE`（フィード削除時に記事も削除）
- 記事の重複排除は `(feed_id, guid)` の UNIQUE 制約で管理

## Makefile コマンド一覧

| コマンド | 説明 |
|---------|------|
| `make install` | 両プロジェクトの依存関係をインストール |
| `make dev` | バックエンド・フロントエンドを並列起動 |
| `make dev-backend` | バックエンドのみ起動 |
| `make dev-frontend` | フロントエンドのみ起動 |
| `make build` | 両プロジェクトをビルド |
| `make test` | バックエンドのテストを実行 |
| `make test-watch` | テストをウォッチモードで実行 |
| `make typecheck` | 型チェックのみ実行 |
| `make clean` | dist を削除 |
| `make docker-up` | Docker コンテナを起動 |
| `make docker-down` | Docker コンテナを停止 |
| `make docker-build` | イメージを再ビルドして起動 |
| `make docker-logs` | ログを表示 |
| `make docker-clean` | コンテナ・イメージ・ボリュームをすべて削除 |

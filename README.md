# Gogai

Web + iOS の RSS リーダー。REST API を共有する Web フロントエンドと iOS ネイティブアプリ。

## 機能

- RSS フィードの追加・削除・グループ管理
- ドメイン URL からの RSS フィード自動検出
- 記事一覧（favicon・タイトル・本文プレビュー・日時表示・未読インジケーター）
- AI による記事の要約・翻訳（Claude CLI / OpenAI / Gemini）
  - 結果を DB にキャッシュ（再実行ボタンで再取得可）
  - 要約はカード内に表示、翻訳は新タブで Markdown レンダリング
  - 要約/翻訳済み記事には「要」「訳」バッジを表示
- ダークモード（手動切替 + localStorage 永続化）
- 設定画面（記事の保持期間を変更可能）
- アプリの更新（設定画面から git pull + ビルド + サービス再起動）
- 設定した日数以上経過した記事の自動削除（デフォルト 180 日）
- **iOS アプリ**（SwiftUI）
  - LAN IP または Cloudflare Tunnel URL（Gist 経由）でサーバーに接続
  - 起動時・バックグラウンド復帰時・5 分ごとに記事を自動更新
  - 右スワイプで既読/未読、左スワイプで AI 要約生成
- **Cloudflare Tunnel**（Raspberry Pi 用）
  - 起動時に Quick Tunnel URL を自動取得し GitHub Gist に書き込む
  - iOS アプリは Gist URL をサーバー URL として登録可能

## 技術スタック

| レイヤー | 技術 |
|---------|------|
| Backend | Node.js + Hono + TypeScript + better-sqlite3 |
| Frontend | React 19 + Vite 8 + TanStack Query + Tailwind CSS v4 |
| iOS | SwiftUI + Swift 6.0 + URLSession（iOS 17.0+） |
| DB | SQLite（WAL モード） |
| Test | Vitest（バックエンドのみ、92 件） / XCTest（iOS） |
| Infra | Docker Compose + nginx / systemd（Raspberry Pi） |

## ディレクトリ構成

```
gogai/
├── backend/
│   ├── src/
│   │   ├── db/schema.ts              # DB 初期化・スキーマ定義
│   │   ├── routes/                   # Hono ルーター
│   │   │   ├── admin.ts              # git pull + 再起動
│   │   │   ├── articles.ts
│   │   │   ├── feeds.ts
│   │   │   ├── groups.ts
│   │   │   └── settings.ts
│   │   ├── services/                 # ビジネスロジック
│   │   │   ├── ai-config.ts          # AI 設定ファイル読み込み
│   │   │   ├── ai-provider.ts        # AI プロバイダーインターフェース
│   │   │   ├── article-content.ts    # 記事リンクから本文取得
│   │   │   ├── articles.ts
│   │   │   ├── feed-discovery.ts     # RSS URL 自動検出
│   │   │   ├── feeds.ts
│   │   │   ├── groups.ts
│   │   │   ├── rss-fetcher.ts
│   │   │   ├── settings.ts
│   │   │   └── providers/
│   │   │       ├── claude-cli.ts     # Claude Code CLI
│   │   │       ├── gemini.ts         # Google Gemini API
│   │   │       └── openai.ts         # OpenAI API
│   │   └── index.ts                  # サーバーエントリーポイント
│   ├── ai.config.json                # AI プロバイダー設定
│   └── data/                         # SQLite DB（.gitignore 済み）
├── frontend/
│   └── src/
│       ├── api/client.ts             # API クライアント
│       ├── components/
│       │   ├── ArticleDetail.tsx
│       │   ├── ArticleList.tsx
│       │   ├── Settings.tsx
│       │   └── Sidebar.tsx
│       └── App.tsx
├── ios/                              # iOS アプリ（Xcode プロジェクト）
│   ├── Gogai.xcodeproj/
│   ├── Gogai/                        # アプリソース
│   └── GogaiTests/                   # XCTest ユニットテスト
├── daemon/                           # systemd サービスファイル（Raspberry Pi 用）
│   ├── gogai-backend.service
│   ├── gogai-frontend.service
│   ├── gogai-cloudflare.service      # Cloudflare Tunnel サービス
│   ├── cloudflare-tunnel.sh          # Tunnel 起動 + Gist 書き込みスクリプト
│   └── setup.sh
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
# → Backend:  http://localhost:3040
# → Frontend: http://localhost:5173
```

### Raspberry Pi（systemd デーモン）

```bash
git clone https://github.com/m-tkg/gogai.git
cd gogai
make install
bash daemon/setup.sh
# → http://<raspi-ip>:5173
```

以降は Makefile で管理：

```bash
make daemon-start    # 起動
make daemon-stop     # 停止
make daemon-restart  # 再起動
make daemon-status   # 状態確認
make daemon-logs     # ログ表示（リアルタイム）
```

または設定画面の「↻ git pull && 再起動」ボタンでブラウザから更新可能。

#### Cloudflare Tunnel（外部アクセス用）

外出先から iOS アプリで接続する場合、Cloudflare Tunnel を使って Raspberry Pi を外部公開できます。

```bash
# 1. daemon/.env を作成（GitHub Classic PAT で gist スコープが必要）
cat > daemon/.env << EOF
GITHUB_PAT=ghp_xxxxxxxxxxxxxxxxxx
EOF

# 2. cloudflare-tunnel サービスを起動
sudo systemctl enable gogai-cloudflare
sudo systemctl start gogai-cloudflare
```

起動すると以下が自動実行されます：
- Cloudflare Quick Tunnel を起動して `*.trycloudflare.com` URL を取得
- GitHub Gist に URL を書き込む
- iOS アプリはその Gist URL をサーバー URL として登録可能
  - 例: `https://gist.github.com/m-tkg/ae26d3342733622b70e9a2740d78cd47`
  - 起動するたびに Gist から最新 URL を取得するため、Pi 再起動後も自動で繋がる

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

Claude CLI のバイナリパスは環境変数 `CLAUDE_PATH` で指定できます（デフォルト: `~/.local/bin/claude`）。

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
| POST | `/api/feeds` | フィード追加 `{ url, groupId? }` ※ドメイン URL も可 |
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
| POST | `/api/articles/:id/claude` | AI 処理 `{ action: "summarize"\|"translate", force?: boolean }` |

### Settings

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/settings` | 設定を取得 |
| PUT | `/api/settings` | 設定を更新 `{ retention_days }` （3〜180） |

### Admin

| Method | Path | 説明 |
|--------|------|------|
| POST | `/api/admin/restart` | git pull + npm run build → レスポンス返却後に `process.exit(0)` で終了（systemd が自動再起動） |

## DB スキーマ

```sql
groups    (id, name, created_at)
feeds     (id, url, title, favicon_url, group_id→groups, last_fetched_at, created_at)
articles  (id, feed_id→feeds, guid, title, link, summary, content,
           published_at, is_read, ai_summary, ai_translation, created_at)
settings  (key, value)
```

- `feeds.group_id` は `ON DELETE SET NULL`（グループ削除時にフィードは残る）
- `articles.feed_id` は `ON DELETE CASCADE`（フィード削除時に記事も削除）
- `articles.ai_summary` / `ai_translation`: AI 結果のキャッシュ
- `settings`: key-value 形式（現在 `retention_days` のみ）

## 環境変数

| 変数 | デフォルト | 説明 |
|-----|---------|------|
| `PORT` | `3040` | バックエンドのポート番号 |
| `DB_PATH` | `backend/data/rss.db` | SQLite ファイルパス |
| `AI_CONFIG_PATH` | `backend/ai.config.json` | AI 設定ファイルパス |
| `CLAUDE_PATH` | `~/.local/bin/claude` | Claude CLI バイナリパス |
| `OPENAI_API_KEY` | — | OpenAI 使用時に必要 |
| `GEMINI_API_KEY` | — | Gemini 使用時に必要 |

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
| `make daemon-setup` | systemd サービスをインストール・自動起動設定 |
| `make daemon-start` | サービスを起動 |
| `make daemon-stop` | サービスを停止 |
| `make daemon-restart` | サービスを再起動 |
| `make daemon-status` | サービスの状態確認 |
| `make daemon-logs` | ログをリアルタイム表示 |
| `make ios-sync-icons` | `appiconset/` → xcassets へアイコンを同期 |
| `make ios-build` | アイコン同期 + シミュレータービルド |
| `make ios-deploy` | アイコン同期 + Release ビルド + 実機インストール + 起動 |

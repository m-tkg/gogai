# Gogai — Claude Code 向けプロジェクト情報

## プロジェクト構成

モノレポ構成。`backend/` と `frontend/` は独立した npm プロジェクト。`ios/` は Xcode プロジェクト。

```
gogai/
├── backend/    Node.js + Hono + TypeScript（ポート 3040）
├── frontend/   React 19 + Vite + Tailwind CSS v4（ポート 5173）
├── ios/        iOS アプリ（SwiftUI + Swift 6.0）
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

## iOS アプリ

- **Xcode プロジェクト**: `ios/Gogai.xcodeproj`
- **最低 OS**: iOS 17.0 / Swift 6.0
- **アーキテクチャ**: View → Store → Repository → APIClient → URLSession
- **状態管理**: `ObservableObject` + `@EnvironmentObject`（Store パターン）

### ディレクトリ構成

```
ios/
├── appiconset/               # アプリアイコン原本（変更はここで行う）
├── Gogai.xcodeproj/
├── Gogai/
│   ├── App/                  GogaiApp.swift（@main）/ RootView.swift
│   ├── Models/               Article / Feed / Group / Settings など（Codable + Sendable）
│   ├── Network/              APIClient / Endpoint / APIError
│   ├── Repositories/         Group / Feed / Article / Settings リポジトリ
│   ├── Stores/               GroupStore / FeedStore / ArticleStore / SettingsStore
│   ├── Views/
│   │   ├── FilterFooterView.swift   フィルター footer（全て/未読のみ/要約あり）
│   │   ├── Onboarding/      ServerSetupView（初回 URL 設定）
│   │   ├── Sidebar/         SidebarView / FeedRowView / GroupRowView / AddFeedView / AddGroupView
│   │   ├── Articles/        ArticleListView / ArticleRowView / ArticleDetailView
│   │   │                    HTMLContentView（WKWebView で HTML レンダリング）
│   │   │                    BrowserView（アプリ内ブラウザ）
│   │   ├── AI/              AISummaryView
│   │   └── Settings/        SettingsView / AdminView
│   ├── ViewModels/           ArticleListViewModel / ArticleDetailViewModel
│   └── Utilities/            ServerURLManager / DateFormatter+
└── GogaiTests/               XCTest ユニットテスト
```

### iOS make コマンド

```bash
make ios-sync-icons   # appiconset/ → xcassets へアイコンを同期
make ios-build        # アイコン同期 + シミュレータービルド
make ios-deploy       # アイコン同期 + Release ビルド + 実機インストール + 起動
```

`ios-deploy` は `DEVICE_ID` 変数で転送先を上書き可能:
```bash
make ios-deploy DEVICE_ID=<device-uuid>
```

### iOS シミュレーターの注意点

- 使用シミュレーター: iPhone 17 Pro（iOS 26）
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer` を xcodebuild に付与する
- iOS 26 ランタイムで dyld shared cache が未生成の場合:
  ```bash
  xcrun simctl runtime dyld_shared_cache update com.apple.CoreSimulator.SimRuntime.iOS-26-0
  ```
- SDK ビルドとランタイムビルドが異なる場合はマッチングを上書き:
  ```bash
  xcrun simctl runtime match set iphoneos26.0 <runtime-build>
  ```

### アプリアイコンの更新手順

1. `ios/appiconset/` 内の PNG を差し替える
2. `make ios-sync-icons` を実行（または `make ios-deploy`）
3. Xcode でビルドすると反映される

`AppIcon.appiconset/` 内のファイルは `appiconset/` からのコピー。
`appiconset/Contents.json` でサイズマッピングを管理している。

### Swift 6 対応の注意点

- Stores はクラスレベルの `@MainActor` を**付けない**（テストの `setUp()` で非 actor コンテキストから生成するため）
- メソッド単位で `@MainActor` を付ける
- `withTaskGroup` で Store を渡すと non-Sendable エラーになるため、sequential `await` を使う
- `Group` モデルと SwiftUI の `Group` ビューが衝突するため `SwiftUI.Group { }` と修飾する

### ArticleStore の主な仕様

- `unreadOnly: Bool` — `UserDefaults` で永続化（キー: `"unreadOnly"`）
- `summaryOnly: Bool` — `UserDefaults` で永続化（キー: `"summaryOnly"`）。クライアント側フィルター（`ai_summary != nil`）
- `summarizingIds: Set<Int>` — AI 要約生成中の記事 ID セット（ProgressView 表示用）
- `markAsRead` / `markAsUnread` — 楽観的更新（失敗時ロールバック）
- `markAllAsRead()` — 表示中の未読記事を並列 API 呼び出しで一括既読
- `summarize(id:)` — AI 要約を生成し `articles` の `ai_summary` を更新。`summarizingIds` で進捗管理

### 画面・インタラクション仕様

| 画面 | 機能 |
|------|------|
| SidebarView | タイトル "Feed list"。フィード名横に未読数 `(N)` 表示 |
| ArticleListView | タイトル = フィード名（フィード選択時）/ "すべての記事"（全件時）|
| ArticleListView | 右スワイプ: 既読/未読トグル（フルスワイプで即実行）|
| ArticleListView | 左スワイプ: AI 要約生成（フルスワイプで即実行）|
| ArticleListView | 要約済み記事行に ✦ アイコン、生成中はスピナー表示 |
| ArticleDetailView | 右上 Safari アイコン: デフォルトブラウザで開く |
| ArticleDetailView | 上スワイプ: アプリ内ブラウザ（BrowserView）を sheet で開く |
| FilterFooterView | 「全て」「未読のみ」「要約あり」ボタン（両画面共通）|
| BrowserView | WKWebView。戻る / 進む / リロード（読込中はキャンセル）ボタン |

### ナビゲーション構造

- **iPad**: `NavigationSplitView`（3カラム: Sidebar / ArticleList / ArticleDetail）
- **iPhone**: `NavigationStack(path: $navigationPath)`
  - `SidebarView` の各行に `onNavigate` コールバックを渡し、`ArticleDestination` を push
  - `ArticleListView` の各行に `onArticleSelected` コールバックを渡し、`Article` を push

### デバッガなしで実機実行（高速化）

Xcode の Scheme 設定で "Debug executable" のチェックを外すか、CLI の `make ios-deploy` を使う（どちらもデバッガなしで起動）。

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

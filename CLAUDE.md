# Gogai — Claude Code 向けプロジェクト情報

## プロジェクト構成

モノレポ構成。`backend/` と `frontend/` は独立した npm プロジェクト。`ios/` は Xcode プロジェクト。

```
gogai/
├── backend/    Node.js + Hono + TypeScript（ポート 3040）
├── frontend/   React 19 + Vite + Tailwind CSS v4（ポート 5173）
├── ios/        iOS / iPadOS / macOS(Mac Catalyst) アプリ（SwiftUI + Swift 6.0）+ 共有シート拡張
├── daemon/     systemd サービスファイル（Raspberry Pi 用）
├── .github/workflows/  GitHub Actions（CI: backend / frontend のテスト）
├── docker-compose.yml
└── Makefile
```

`git clone` 後は `.env` 不要（`PORT`/`DB_PATH` はデフォルト値で動作）。`make install && make dev` だけで動く。
`node_modules/`・`backend/data/`・`ios/build/` 等は `.gitignore` 対象でツールが自動生成する。

## 開発コマンド

```bash
make dev            # バックエンド + フロントエンドを並列起動
make test           # backend + frontend のテストを実行（Vitest）
make test-watch     # backend テストをウォッチモードで実行
make typecheck      # 型チェック（backend + frontend）
make docker-up      # Docker で起動（http://localhost:8080）
make daemon-restart # Raspberry Pi でサービスを再起動
make ios-build      # iOS シミュレータービルド
make ios-test       # iOS ユニットテストを実行
make ios-deploy     # iOS 実機インストール＆起動
```

## バックエンド

- **エントリーポイント**: `backend/src/index.ts`（起動・スケジューリングのみ）
- **ルーター**: `backend/src/routes/` (groups / feeds / articles / settings / admin / stocks / stock-categories)。パースとサービス呼び出しのみ。ビジネスロジックは置かない
- **サービス層**: `backend/src/services/`（`feed-registration.ts` がフィード登録・URL変更・再取得の共通フロー）
- **エラー処理**: `backend/src/errors.ts` の `AppError(message, status)` を throw し、各ルーターの `app.onError(errorHandler)` が `{ error: string }` に変換する。UNIQUE 制約違反は `isUniqueConstraintError()` で判定
- **定数**: `backend/src/config.ts`（retention_days のデフォルト/上下限）
- **DB スキーマ**: `backend/src/db/schema.ts`
- **テスト**: `backend/src/__tests__/`。`routes/` 配下はルーターを `router.request()` で叩く HTTP 契約テスト（エラー形式 `{ error: string }` とステータスコードを固定）。`setDb()` で in-memory DB に差し替える

### DB（SQLite）

- パス: `backend/data/rss.db`（環境変数 `DB_PATH` で変更可）
- WAL モード有効、外部キー制約有効
- テーブル: `groups` → `feeds` → `articles`、`settings`、`stock_categories` → `stocks` → `stock_translations`
- スキーマ変更は `schema.ts` の `MIGRATIONS` 配列の**末尾に冪等なマイグレーションを追加**する（名前付き、何度実行しても安全な実装にする）

### favicon

`GET /api/feeds` レスポンス時に Google favicon サービス URL を動的に生成して返す。
DB には保存せず、レスポンス変換で差し替えているため DB マイグレーション不要。

```typescript
// routes/feeds.ts
function withGoogleFavicon(feed: Feed): Feed {
  return { ...feed, favicon_url: getFaviconUrl(feed.url) }
}
```

iOS の `AsyncImage` は ICO 非対応のため、**必ず Google favicon サービス（PNG）を使うこと**。
DuckDuckGo favicon は ICO を返すため使用禁止。

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

**`GET /api/admin/update-check`** — `git fetch origin main` でリモートを取得後、
`git rev-parse` でローカルとリモートの SHA を比較して返す。
GitHub API は使用しない（private repo でも動作する）。

**`POST /api/admin/restart`** — 以下の順序で実行:
1. `git pull`（`GIT_SSH_COMMAND` で非対話モード）
2. `npm run build`（**現プロセスの PATH を引き継ぐ**ため systemd の PATH 制限を回避）
3. レスポンスを返す
4. 500ms 後に `process.exit(0)`

systemd の `Restart=always` により自動再起動。`ExecStartPre=-npm run build`（`-` = 失敗しても無視）は
ビルド済み `dist/` があれば即起動できるようにするセーフティネット。

## フロントエンド

- **エントリーポイント**: `frontend/src/App.tsx`（UI 状態は hooks に集約: `useSelectionState` / `useDarkMode` / `useLocalStorageBool`）
- **コンポーネント**: `Sidebar`（`components/sidebar/` の GroupSection / FeedList / FeedItem / AddForms で構成）/ `ArticleList` + `articles/ArticleCard` / `ArticleDetail` / `Settings`
- **API クライアント**: `frontend/src/api/client.ts`（axios）。型は `api/types.ts`、エラーメッセージ抽出は `api/errors.ts` の `getApiErrorMessage`
- **TanStack Query**: キャッシュキーは必ず `api/queryKeys.ts` 経由（文字列リテラル直書き禁止）。invalidate は `invalidateFeedsAndArticles` 等のヘルパーを使う
- **hooks**: `useFeedMutations` / `useGroupMutations`（mutation 集約）、`useDragReorder`（D&D 並び替え、グループ・フィード共用）
- **テスト**: Vitest + Testing Library（`npm test`）。設定は `vite.config.ts` の `test` ブロック + `src/test/setup.ts`（localStorage / matchMedia の stub あり）

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
│   ├── Models/               Article（updating() ヘルパーあり）/ Feed / Group / Settings / Stock など（Codable + Sendable）
│   ├── Network/              APIClient / Endpoint / APIError
│   ├── Repositories/         Group / Feed / Article / Settings / Stock リポジトリ
│   ├── Stores/               GroupStore / FeedStore / ArticleStore / SettingsStore / StockStore
│   │                         ArticleCollection（全記事キャッシュのマージ規則を持つ値型）
│   ├── Views/
│   │   ├── FilterFooterView.swift   フィルター footer（ストック/全て/未読のみ）
│   │   ├── FormSheet.swift          追加・編集フォームの共通シェル + GroupPickerSection
│   │   ├── UnreadCountBadge.swift   未読数バッジ
│   │   ├── Onboarding/      ServerSetupView（初回 URL 設定）
│   │   ├── Sidebar/         SidebarView / FeedRowView / GroupRowView / AddFeedView / AddGroupView
│   │   │                    EditFeedView（フィードタイトル・グループ編集）
│   │   ├── Articles/        ArticleListView / ArticleRowView / ArticleDetailView
│   │   │                    HTMLContentView（WKWebView で HTML レンダリング）
│   │   │                    BrowserView（アプリ内ブラウザ）
│   │   ├── Stocks/          StockCategoryListView / StockListView / StockRowView / StockDetailView
│   │   │                    AddStockView / EditStockView（ストック機能。旧お気に入りの後継）
│   │   └── Settings/        SettingsView / AdminView
│   ├── AI/                   ローカル AI（要約・翻訳）
│   │                         LocalArticleAI（プロンプト整形）/ FoundationModelTextGenerator
│   │                         LocalAIResultSheet（結果表示）/ LocalAIOverlay（右下ボタン群）
│   │                         TranslatedPageView+Model（システム翻訳、レイアウト保持のページ内翻訳）
│   │                         FMPageTranslator/FMTranslatedPageView（基盤モデルによるレイアウト保持翻訳）
│   │                         StockSummarizer/StockSummary（ストック要約の map-reduce パイプライン）
│   │                         ArticleContentFetcher（記事 URL から本文抽出）
│   └── Utilities/            ServerURLManager / DefaultsKeys / HorizontalSwipe / DateFormatter+ / AppGroup
├── GogaiShareExtension/       iOS/iPadOS 共有シート拡張（ShareViewController / ShareStockView）
│                              共有された URL をストックに追加する（App Group 経由で本体アプリと通信）
└── GogaiTests/               XCTest ユニットテスト
```

- UserDefaults のキーは `Utilities/DefaultsKeys.swift` に追加する（直書き禁止）
- 追加・編集フォームは `FormSheet` を使う（送信状態・エラー表示・dismiss を共通化済み）

### iOS make コマンド

```bash
make ios-sync-icons   # appiconset/ → xcassets へアイコンを同期
make ios-build        # アイコン同期 + シミュレータービルド
make ios-test         # ユニットテスト（iPhone 17 Pro シミュレーター）
make ios-deploy       # アイコン同期 + Release ビルド + 実機インストール + 起動
```

新しい Swift ファイルを追加したら `Gogai.xcodeproj/project.pbxproj` への登録が必要
（PBXBuildFile / PBXFileReference / グループ children / Sources phase の4箇所）。

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

### ServerURLManager の仕様

- `serverURL`: UserDefaults に保存した生の URL（Gist URL の場合もある）
- `resolvedURL`: 実際に API クライアントが使う URL（Gist URL なら解決済み）
- `resolve()`: `gist.github.com` URL の場合は GitHub Gist API 経由でコンテンツを取得し実 URL を解決
- Gist URL を保存することで Pi 再起動後も最新トンネル URL を自動取得できる

```swift
// 入力例: https://gist.github.com/<your-username>/<your-gist-id>
// → GitHub API で Gist のコンテンツ（トンネル URL）を取得
// → resolvedURL = https://xxxx.trycloudflare.com
```

### ArticleStore の主な仕様

- `articles`: 現在表示中フィードの記事（フィルター後）
- `allCollection: ArticleCollection`: 全フィードの記事キャッシュ（**未読バッジ計算に使用**、`allArticles` は互換用の computed property）
  - マージ規則は `ArticleCollection.merge(_:isFullFetch:)` が所有: 全件取得なら全置換、特定フィード/グループなら該当フィード分のみ差し替え
- **記事の更新は必ず `mutateBoth()` / `optimisticUpdate()` 経由**で行う（`articles` とコレクションを同一変換で同期し、手動二重更新による不整合を防ぐ）
  - `optimisticUpdate()` は API 失敗時に自動ロールバック。URLError 時の挙動は `URLErrorPolicy`（既読系は pending キューへ）
- `toggleRead(_:)` — View 側で既読の分岐を書かない
- `unreadOnly: Bool` — `UserDefaults`（`DefaultsKeys`）で永続化
- `markAllAsRead()` — 表示中の未読記事を sequential API 呼び出しで一括既読
- シークレットフィード判定は `GroupStore.secretFeedIds(in:)` を使う

### ストック機能の仕様（旧お気に入りの後継）

- Instapaper 的な保存機能。サーバー側に URL・タイトル・カテゴリ・要約を保存する（お気に入りの後継として統合済み、`is_favorite` カラムは削除済み）
- 追加経路: 記事一覧の左スワイプ（ストック元は所属グループ名）/ iOS・iPadOS の共有シート（`GogaiShareExtension`）
- 要約はストック追加時に自動生成せず、**ボタン起点**で明示的に生成する（`StockSummarizer` が map-reduce でオンデバイス生成し `PUT /api/stocks/:id/summary` で保存）
- 翻訳はレイアウト保持のページ内翻訳を基盤モデルで行う（`FMPageTranslator`/`FMTranslatedPageView`）。結果は `stock_translations` に保存し再翻訳可能
- 編集可能なのはタイトル・カテゴリのみ。カテゴリは並び替え可能（`PATCH /api/stock-categories/reorder`）
- `StockListView` の行を長押しすると、詳細ページのフッターと同じ操作（元記事・翻訳・要約を生成・編集・削除）をコンテキストメニューで実行できる
- シークレットフィード判定と同様、`StockStore` が一覧・作成・更新・削除を保持する

### ローカル AI（要約・翻訳、iOS/iPadOS 27 以上）

- ゲート: `LocalAI.isAvailable`（iOS 27 以上 + `SystemLanguageModel` が available）。条件を満たさない端末ではボタン非表示
- 記事ページ（BrowserView）右下に `.localAIOverlay(for:)` でボタンを表示。結果はサーバーに保存しない
- **要約**: 常にオンデバイス基盤モデル（Foundation Models）。`TextGenerating` プロトコルが provider 差し替えの seam
- **翻訳**: 設定の `TranslationEngine` で切り替え
  - システム翻訳（デフォルト外）→ `TranslatedPageView`: WKWebView でテキストノードだけ翻訳し、レイアウト・画像を保持
  - ローカル AI（基盤モデル）→ 訳文テキストを sheet 表示
- AI への入力は `ArticleContentFetcher` が記事 URL から本文抽出（失敗時は RSS 本文にフォールバック）。4096 トークン制限のため 3,000 字に切り詰め
  - 文字数からトークン数を正確に見積もれない（特に日本語）ため、`exceededContextWindowSize` 系のエラーを検知したら
    プロンプトを縮小して自動リトライする（`FoundationModelTextGenerator.shrinkPromptIfContextExceeded`）。
    型ではなくエラー文言のキーワードで判定している（Xcode/SDK バージョンによって型が存在しないことがあるため）
- Translation framework はシミュレーター不可（実機で確認）。Foundation Models は iOS 27 シミュレーターで動作確認可能

### GogaiApp の自動更新

- **起動時**: `resolvedURL` 確定後に `configureStores()` → `fetchArticles()`
- **バックグラウンド復帰時**: `scenePhase == .active` を検知して `articleStore.refresh()`
- **5 分ごと**: `.task(id: resolvedURL)` でループし `articleStore.refresh()`（バックグラウンド中は iOS がタスクを停止）

### ページ名称

| ページ名 | View | 説明 |
|----------|------|------|
| **フィードページ** | `SidebarView` | 起動直後に表示。フィード・グループ一覧 |
| **記事一覧ページ** | `ArticleListView` | フィード/グループ選択後の記事一覧 |
| **概要ページ** | `ArticleDetailView` | 記事タイトル・要約を表示 |
| **記事ページ** | `BrowserView`（SFSafariViewController）| 記事本文を Safari で表示 |
| **ストック一覧ページ** | `StockCategoryListView` / `StockListView` | カテゴリ別のストック一覧 |
| **ストック詳細ページ** | `StockDetailView` | ストックのタイトル・要約・翻訳を表示 |

### 画面・インタラクション仕様

| ページ | 機能 |
|--------|------|
| フィードページ（SidebarView） | タイトル "Feed list"。フィード名横にアクセントカラーの丸バッジで未読数表示 |
| フィードページ（SidebarView） | フィードのコンテキストメニュー: 編集（EditFeedView sheet）/ 削除 |
| 記事一覧ページ（ArticleListView） | タイトル = フィード名（フィード選択時）/ "すべての記事"（全件時）|
| 記事一覧ページ（ArticleListView） | 右スワイプ 12.5% でボタン表示、25% で確定: 既読/未読トグル |
| 記事一覧ページ（ArticleListView） | 左スワイプ 12.5% でボタン表示、25% で確定: ストックに入れる（ストック元は所属グループ名） |
| 概要ページ（ArticleDetailView） | 右上 Safari アイコン: デフォルトブラウザで開く |
| 概要ページ（ArticleDetailView） | 左スワイプ: 記事ページ（BrowserView）を push 遷移（右から左）で開く |
| FilterFooterView | 「全て」「未読のみ」「ストック」ボタン（フィードページ・記事一覧ページ共通、ストックは一番右端）|
| 記事ページ（BrowserView） | SFSafariViewController。Safari 拡張・広告ブロックが有効 |
| 記事ページ（BrowserView） | 右スワイプ または 右下の閉じるボタンで閉じる |
| ストック一覧ページ（StockListView） | 行を長押し: 詳細ページのフッターと同じ操作（元記事/翻訳/要約を生成/編集/削除）をコンテキストメニューで実行 |
| AdminView | サーバー（Raspberry Pi）のアップデート確認 + 「git pull して再起動」ボタン（再起動中はポーリングして自動再接続）|

### ナビゲーション構造

- **iPad**: `NavigationSplitView`（3カラム: フィードページ / 記事一覧ページ / 概要ページ）
- **iPhone**: `NavigationStack(path: $navigationPath)`
  - フィードページ（SidebarView）の各行に `onNavigate` コールバックを渡し、`ArticleDestination` を push
  - 記事一覧ページ（ArticleListView）の各行に `onArticleSelected` コールバックを渡し、`Article` を push

### デバッガなしで実機実行（高速化）

Xcode の Scheme 設定で "Debug executable" のチェックを外すか、CLI の `make ios-deploy` を使う（どちらもデバッガなしで起動）。

### macOS（Mac Catalyst）版について

- **配布は廃止済み**（2026-07）。Mac では iPad 版アプリを使う方針のため、CI リリースワークフロー・
  GitHub Releases の配布バイナリ・アプリ内自動更新（`Update/`）・`make mac-*` / `release-tag` ターゲットを削除した
- バージョンは `v*` タグのみで管理し、**GitHub Release は作成しない**（過去のタグ v1.0.0〜 も履歴として残存）。
  `MARKETING_VERSION` は `xx.xx.xx` 形式のまま管理を継続する

## テスト指針

- TDD（t-wada 推奨スタイル）
- テストを先に書き、失敗を確認してからコミット、その後実装
- 既存挙動のリファクタリング時は、先に特性テスト（characterization test）で挙動を固定してから変更する
- backend / frontend: Vitest（ESM モード）。frontend は Testing Library を併用
- backend のルートテストは `router.request()` + `setDb()`（in-memory SQLite）で HTTP 契約を検証する
- iOS: XCTest（`make ios-test`）。Store / Repository / Network / Utilities をカバー
- `vi.mock` でクラスをモックする場合は注意（ESM では constructor mock が機能しない場合がある）

## 環境変数

| 変数 | デフォルト | 説明 |
|-----|---------|------|
| `PORT` | `3040` | バックエンドのポート番号 |
| `DB_PATH` | `backend/data/rss.db` | SQLite ファイルパス |

## Docker Compose

- `backend` サービス: ポート非公開、ヘルスチェックあり（`GET /health`）
- `frontend` サービス: nginx でホスト、`/api/*` をバックエンドへリバースプロキシ
- `db-data` 名前付きボリューム: SQLite を永続化
- 外部アクセス: `http://localhost:8080`（環境変数 `PORT` で変更可）

## Raspberry Pi（systemd）

- サービスファイル: `daemon/gogai-backend.service` / `gogai-frontend.service` / `gogai-cloudflare.service`
- セットアップ: `bash daemon/setup.sh`
- backend / frontend ともに `host: 0.0.0.0` でバインドして LAN からアクセス可能
- 設定画面の「git pull して再起動」ボタンでブラウザ・iOS アプリから更新可能

### gogai-backend.service の注意点

- `Restart=always` — `process.exit(0)` でも再起動するために必要（`on-failure` は終了コード 0 で再起動しない）
- `ExecStartPre=-npm run build` — `-` プレフィックスで失敗しても無視（restart エンドポイントが事前にビルド済みのため）

### Cloudflare トンネル（gogai-cloudflare.service）

起動時に `cloudflared` でクイックトンネルを作成し、割り当て URL を GitHub Gist に書き込む。

```bash
# daemon/.env に GitHub classic PAT（gist スコープ必須）を設定
echo "GITHUB_PAT=ghp_xxxx" > daemon/.env
chmod 600 daemon/.env

# サービスをインストール
sudo cp daemon/gogai-cloudflare.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now gogai-cloudflare
```

- `~/.cloudflared/config.yml` に名前付きトンネルの設定がある場合、`--config` に空の一時ファイルを渡してクイックトンネルとして起動する（既存設定の ingress ルールが干渉するため）
- Gist URL: `https://gist.github.com/<your-username>/<your-gist-id>`
- iOS アプリの「サーバー URL」にこの Gist URL を入力すると、起動時に最新トンネル URL を自動解決して接続する

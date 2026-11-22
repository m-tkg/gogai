# Gogai

Web + iOS + Android の RSS リーダー。REST API を共有する Web フロントエンドとモバイルネイティブアプリ。

## 機能

- RSS フィードの追加・削除・グループ管理（並び替え対応）
- ドメイン URL からの RSS フィード自動検出
- 記事一覧（favicon・タイトル・本文プレビュー・日時表示・未読インジケーター）
- ダークモード（手動切替 + localStorage 永続化）
- 設定画面（記事の保持期間を変更可能）
- アプリの更新（設定画面から git pull + ビルド + サービス再起動）
- 設定した日数以上経過した記事の自動削除（デフォルト 180 日。評価した記事は対象外）
- **like / dislike**（記事に「これは好み」「これは好みでない」を手動で付ける排他フラグ。
  外部のキュレーション AI に正例・負例として渡すシグナル）
- **ストック**（Instapaper 的な保存機能。旧お気に入り機能の後継）
  - サーバーに URL・タイトル・要約を保存し、カテゴリで分類・並び替え可能
  - iOS/iPadOS/macOS の Foundation Models（オンデバイス AI）で要約・翻訳を生成し結果をサーバーに保存
- **iOS / iPadOS / macOS（Mac Catalyst）アプリ**（SwiftUI）
  - LAN IP または Tailscale（tailnet 内アドレス）などの利用者指定 URL でサーバーに接続
  - 起動時・バックグラウンド復帰時・5 分ごとに記事を自動更新
  - 右スワイプで既読/未読、左スワイプでストックに追加
  - iOS/iPadOS の共有シートから任意ページをストックに追加可能
- **Android アプリ**（Kotlin + Jetpack Compose、iOS 版と同じ使い勝手の移植）
  - フィード/グループ/記事/ストック/設定/Admin まで iOS 版と同等の機能
  - 要約・翻訳はリモート AI（OpenAI / Gemini / Claude、API キー設定時のみ）
  - 記事ページは Chrome Custom Tabs、他アプリの共有からストック追加可能
  - タブレットは 3 ペイン表示（iPad 相当）
- **リモートアクセス**: Tailscale 経由（サーバーをインターネットへ公開しない）

## 技術スタック

| レイヤー | 技術 |
|---------|------|
| Backend | Node.js + Hono + TypeScript + better-sqlite3 |
| Frontend | React 19 + Vite + TanStack Query + Tailwind CSS v4 |
| iOS/iPadOS/macOS | SwiftUI + Swift 6.0 + URLSession（iOS 17.0+ / Mac Catalyst） |
| Android | Kotlin 2.1 + Jetpack Compose + OkHttp（Android 13+） |
| DB | SQLite（WAL モード） |
| Test | Vitest（backend + frontend） / XCTest（iOS/iPadOS/macOS） / JUnit4（Android） |
| Infra | Docker Compose + nginx / systemd（Raspberry Pi）/ GitHub Actions（CI） |

## ディレクトリ構成

```
gogai/
├── backend/
│   ├── src/
│   │   ├── db/schema.ts              # DB 初期化・スキーマ定義（マイグレーション管理）
│   │   ├── routes/                   # Hono ルーター（パース + サービス呼び出しのみ）
│   │   │   ├── admin.ts              # 更新確認 + git pull + 再起動
│   │   │   ├── articles.ts
│   │   │   ├── feeds.ts
│   │   │   ├── groups.ts
│   │   │   ├── settings.ts
│   │   │   ├── stocks.ts
│   │   │   └── stock-categories.ts
│   │   ├── services/                 # ビジネスロジック
│   │   │   ├── articles.ts
│   │   │   ├── feed-discovery.ts     # RSS URL 自動検出
│   │   │   ├── feed-refresher.ts     # フィード再取得
│   │   │   ├── feed-registration.ts  # フィード登録・URL変更・再取得の共通フロー
│   │   │   ├── feeds.ts
│   │   │   ├── groups.ts
│   │   │   ├── rss-fetcher.ts
│   │   │   ├── settings.ts
│   │   │   ├── stocks.ts
│   │   │   └── stock-categories.ts
│   │   └── index.ts                  # サーバーエントリーポイント（起動・スケジューリング）
│   └── data/                         # SQLite DB（.gitignore 済み）
├── frontend/
│   └── src/
│       ├── api/                      # client.ts / types.ts / queryKeys.ts / errors.ts
│       ├── components/
│       │   ├── articles/             # ArticleCard など
│       │   ├── sidebar/              # GroupSection / FeedList / FeedItem / AddForms
│       │   ├── ui/
│       │   ├── ArticleDetail.tsx
│       │   ├── ArticleList.tsx
│       │   ├── Settings.tsx
│       │   └── Sidebar.tsx
│       ├── hooks/                    # useFeedMutations / useGroupMutations / useDragReorder など
│       └── App.tsx
├── ios/                              # iOS / iPadOS / macOS(Mac Catalyst) アプリ（Xcode プロジェクト）
│   ├── Gogai.xcodeproj/
│   ├── Gogai/                        # アプリ本体（詳細は CLAUDE.md 参照）
│   ├── GogaiShareExtension/          # 共有シート拡張（URL をストックに追加）
│   └── GogaiTests/                   # XCTest ユニットテスト
├── android/                          # Android アプリ（Gradle プロジェクト）
│   └── app/src/main/kotlin/com/mtkg/gogai/   # 本体（詳細は CLAUDE.md 参照）
├── daemon/                           # systemd サービスファイル（Raspberry Pi 用）
│   ├── gogai-backend.service
│   ├── gogai-frontend.service
│   └── setup.sh
├── .github/workflows/
│   └── ci.yml                        # CI（backend / frontend / android のテスト）
├── docker-compose.yml
├── Makefile
└── README.md
```

## セットアップ

### ローカル開発

`git clone` 後は以下だけで動きます。`.env` は不要（`PORT`/`DB_PATH` はデフォルト値で動作）。
`node_modules/`・`backend/data/`（SQLite DB）・`ios/build/` などはすべて `.gitignore` 対象で、
コマンド実行時や Xcode のビルド時に自動生成されるため、手動で用意するものはありません。

```bash
git clone git@github.com:m-tkg/gogai.git
cd gogai

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

または iOS / Android アプリの管理画面から更新可能（`ADMIN_SECRET` の設定が必要。下記参照）。

#### 既存環境の移行（旧トンネル構成から更新する場合）

アプリの「git pull して再起動」や `make restart-daemon` は backend / frontend しか再起動しないため、
旧トンネル用サービスは止まらない。更新後に次を行う。

```bash
bash daemon/setup.sh   # 旧サービスの停止・削除と backend の unit 更新（または: sudo systemctl disable --now gogai-cloudflare）
```

- 旧構成の `daemon/.env` に置いていたトークン（`GITHUB_PAT`）は不要になる。`daemon/.env` から削除し、発行元でトークンを失効する。
  backend は `daemon/.env` を読まない（`daemon/backend.env` のみ読む）。

#### リモートアクセス（Tailscale）

外出先から接続する場合は、サーバーを公開せず [Tailscale](https://tailscale.com/) の tailnet 経由で接続する。
サーバーとクライアント端末の両方を同じ tailnet に参加させ、アプリの「サーバー URL」に tailnet 内のアドレスを指定する。

- 例: `http://<サーバーの tailnet ホスト名または IP>:3040`（バックエンド直）
- 記事・フィード API には共通の認証が無いため、**インターネットへ直接公開しない**こと

#### 管理 API の保護（ADMIN_SECRET）

`/api/admin/*`（更新確認・git pull して再起動）は、サーバーに環境変数 `ADMIN_SECRET` が設定されている場合だけ使える。
未設定・空文字・空白のみの間は全リクエストを 403 で拒否する。設定済みでも `X-Admin-Secret` ヘッダーが一致しなければ 401。

```bash
# daemon/backend.env（git 管理外・backend 専用）に書く。作成時から所有者のみ読めるようにする
(umask 077; printf 'ADMIN_SECRET=%s\n' "$(openssl rand -hex 32)" >> daemon/backend.env)
sudo systemctl restart gogai-backend
```

`make dev` など systemd 以外で動かす場合は、起動前に `ADMIN_SECRET=<...>` を環境変数に渡す。
iOS / Android アプリは、設定画面の「管理シークレット」に同じ値を入力する（値は `cat daemon/backend.env` で確認できる）。
Web 版の設定画面は秘密を送信しないため、管理 API を使えない（更新はアプリか `make restart-daemon` で行う）。

### iOS / iPadOS / macOS アプリ

自分の Apple アカウントでビルドする場合は、署名設定（Team ID / Bundle ID）を
`ios/Config/Local.xcconfig` で上書きする必要がある。詳細は
[`ios/README.md`](ios/README.md#自分のアカウントでビルドする) を参照。

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

## API エンドポイント

要約・翻訳は iOS/iPadOS/macOS 側のオンデバイス AI（Foundation Models）で生成するため、
サーバー側に AI プロバイダー設定は存在しません（生成結果をストックに保存するのみ）。

### Groups

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/groups` | グループ一覧 |
| POST | `/api/groups` | グループ作成 `{ name }` |
| PUT | `/api/groups/:id` | グループ更新 `{ name }` |
| DELETE | `/api/groups/:id` | グループ削除 |
| PATCH | `/api/groups/reorder` | グループの並び替え `{ ids: number[] }` |
| POST | `/api/groups/:id/refresh` | グループ配下のフィードを一括更新 |

### Feeds

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/feeds` | フィード一覧 |
| POST | `/api/feeds` | フィード追加 `{ url, groupId? }` ※ドメイン URL も可 |
| PUT | `/api/feeds/:id` | フィード更新 `{ title?, groupId? }` |
| DELETE | `/api/feeds/:id` | フィード削除（記事も CASCADE 削除） |
| PATCH | `/api/feeds/reorder` | フィードの並び替え `{ ids: number[] }` |
| POST | `/api/feeds/refresh-all` | 全フィードを一括更新 |
| POST | `/api/feeds/:id/refresh` | 記事を手動更新 |

### Articles

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/articles` | 記事一覧 `?feedId=&groupId=&unreadOnly=&likedOnly=&dislikedOnly=&limit=&offset=` |
| GET | `/api/articles/counts` | フィードごとの記事数・未読数・like 数・dislike 数 |
| GET | `/api/articles/:id` | 記事詳細 |
| POST | `/api/articles/:id/read` | 既読にする |
| POST | `/api/articles/:id/unread` | 未読にする |
| POST | `/api/articles/:id/like` | like する（ユーザーの好みとして記録） |
| POST | `/api/articles/:id/unlike` | like を外す |
| POST | `/api/articles/:id/dislike` | dislike する（好みでないとして記録） |
| POST | `/api/articles/:id/undislike` | dislike を外す |

`likedOnly=true` / `dislikedOnly=true` を指定すると評価済みの記事だけを、評価した日時
（`liked_at` / `disliked_at`）の降順（`sortBy` より優先）で返す。
外部のキュレーション AI に正例・負例を渡すための取得口として使う。

**like と dislike は排他**。一方を付けるともう一方は自動的に外れる（サーバー側で保証）。
評価された記事は保持期間（`retention_days`）を過ぎても自動削除されない。

### Stocks

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/stocks` | ストック一覧 `?category_id=` |
| POST | `/api/stocks` | ストック追加 `{ url, title?, source?, category? }` |
| PUT | `/api/stocks/:id` | タイトル・カテゴリ更新 `{ title, category }` |
| DELETE | `/api/stocks/:id` | ストック削除 |
| PUT | `/api/stocks/:id/summary` | 要約を保存（端末側でオンデバイス生成した結果） `{ summary }` |
| GET | `/api/stocks/:id/translation` | 翻訳結果を取得 |
| PUT | `/api/stocks/:id/translation` | 翻訳結果を保存 `{ segments }` |
| DELETE | `/api/stocks/:id/translation` | 翻訳結果を削除（再翻訳用） |

### Stock Categories

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/stock-categories` | カテゴリ一覧 |
| PATCH | `/api/stock-categories/reorder` | カテゴリの並び替え `{ ids: number[] }` |

### Settings

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/settings` | 設定を取得 |
| PUT | `/api/settings` | 設定を更新 `{ retention_days }` （3〜180） |

### Admin

| Method | Path | 説明 |
|--------|------|------|
| GET | `/api/admin/update-check` | `git fetch` でリモートと比較し更新の有無を返す（要 `X-Admin-Secret`） |
| POST | `/api/admin/restart` | git pull + npm run build → レスポンス返却後に `process.exit(0)` で終了（systemd が自動再起動）（要 `X-Admin-Secret`） |

## DB スキーマ

```sql
groups    (id, name, is_secret, display_order, created_at)
feeds     (id, url, title, favicon_url, group_id→groups, last_fetched_at, display_order, created_at)
articles  (id, feed_id→feeds, guid, title, link, summary, content,
           published_at, is_read, read_at, liked_at, disliked_at, created_at)
settings  (key, value)

stock_categories   (id, name, display_order, created_at)
stocks              (id, url, title, source, category_id→stock_categories,
                     summary, stocked_at, created_at)
stock_translations  (stock_id→stocks, segments, translated_at)
```

- `feeds.group_id` は `ON DELETE SET NULL`（グループ削除時にフィードは残る）
- `articles.feed_id` は `ON DELETE CASCADE`（フィード削除時に記事も削除）
- `articles.liked_at` / `articles.disliked_at`: NULL = 未評価。両者は排他（一方を付けると他方が NULL になる）。
  評価された記事は保持期間を過ぎても自動削除されない
- `stocks.category_id` は `stock_categories` への必須参照（旧お気に入り機能をストックへ統合した後継）
- `stock_translations.stock_id` は `ON DELETE CASCADE`（ストック削除時に翻訳も削除）
- `settings`: key-value 形式（現在 `retention_days` のみ）
- 要約・翻訳は iOS/iPadOS/macOS 側のオンデバイス AI（Foundation Models）で生成し、結果をサーバーに保存する（サーバー側に AI 機能は無い）

## 環境変数

| 変数 | デフォルト | 説明 |
|-----|---------|------|
| `PORT` | `3040` | バックエンドのポート番号 |
| `DB_PATH` | `backend/data/rss.db` | SQLite ファイルパス |

## Makefile コマンド一覧

| コマンド | 説明 |
|---------|------|
| `make install` | 両プロジェクトの依存関係をインストール |
| `make dev` | バックエンド・フロントエンドを並列起動 |
| `make dev-backend` | バックエンドのみ起動 |
| `make dev-frontend` | フロントエンドのみ起動 |
| `make build` | 両プロジェクトをビルド |
| `make test` | backend + frontend のテストを実行 |
| `make test-watch` | backend テストをウォッチモードで実行 |
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
| `make ios-test` | iOS ユニットテストを実行（iPhone 17 Pro シミュレーター） |
| `make ios-deploy` | アイコン同期 + Release ビルド + 実機インストール + 起動 |

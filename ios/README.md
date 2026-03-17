# Gogai iOS アプリ

gogai RSS リーダーの iOS クライアントアプリ。

## 要件

- Xcode 26 beta 以上（`/Applications/Xcode-beta.app`）
- iOS 17.0 以上（実機・シミュレーター）
- バックエンドサーバー（`make dev` または Raspberry Pi 上で稼働）

---

## ビルド

### Makefile（推奨）

```bash
# シミュレーター向けビルド（アイコン同期込み）
make ios-build

# Release ビルド → 実機インストール → 起動（デバッガなし）
make ios-deploy
```

### Xcode でビルド

```bash
open ios/Gogai.xcodeproj
```

Xcode が開いたら `Cmd+B` でビルド。

### コマンドラインでビルド

```bash
cd ios

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild build \
  -project Gogai.xcodeproj \
  -scheme Gogai \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```

---

## テスト

### Xcode でテスト

`Cmd+U` で全テストを実行。

### コマンドラインでテスト

```bash
cd ios

DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project Gogai.xcodeproj \
  -scheme Gogai \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"
```

特定のテストクラスだけ実行する場合：

```bash
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild test \
  -project Gogai.xcodeproj \
  -scheme Gogai \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing GogaiTests/ArticleStoreTests
```

---

## シミュレーターで実行

1. Xcode でシミュレーターを選択（iPhone 17 Pro）
2. `Cmd+R` でビルド＆起動
3. 初回起動時に URL 入力画面が表示される
4. バックエンドの URL を入力（例: `http://localhost:3040`）して接続確認

---

## 実機（iPhone）への転送

### CLI で転送（デバッガなし・高速）

```bash
make ios-deploy
```

内部動作：Release ビルド → `xcrun devicectl device install app` でインストール → `xcrun devicectl device process launch` で起動

デバイス UUID を変更する場合：

```bash
make ios-deploy DEVICE_ID=<device-uuid>

# 接続中のデバイス一覧を確認
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun devicectl list devices
```

### Xcode から転送（デバッガなしで起動）

デバッガがアタッチされると起動が遅くなる。無効化する手順：

1. `Product → Scheme → Edit Scheme → Run → Info`
2. "Debug executable" のチェックを外す
3. `Cmd+R` で転送

### 初回セットアップ

- Apple ID を Xcode に追加済みであること（Xcode > Settings > Accounts）
- 無料の Apple Developer アカウントで実機インストール可能（7日間の証明書有効期限あり）
- `Signing & Capabilities` タブで Team と Bundle Identifier を設定

### LAN 上の Raspberry Pi に接続する場合

アプリ起動後の URL 設定画面で Raspberry Pi の LAN IP を入力：

```
http://192.168.x.x:3040
```

`Info.plist` に `NSAllowsLocalNetworking = YES` が設定済みのため、
LAN 内の HTTP サーバーへの接続は追加設定なしで動作する。

### Cloudflare Tunnel 経由で外出先から接続する場合

Raspberry Pi 側で `gogai-cloudflare` サービスを起動すると、Quick Tunnel URL が GitHub Gist に書き込まれる。
アプリの URL 設定画面で Gist の URL を入力すると、起動するたびに最新のトンネル URL を自動取得する：

```
https://gist.github.com/m-tkg/ae26d3342733622b70e9a2740d78cd47
```

- `gist.github.com` のドメインを検出すると自動で Gist API を呼び出し実際のサーバー URL を解決する
- Pi を再起動してトンネル URL が変わっても、アプリ側の設定変更は不要

---

## アプリアイコンの更新

アイコンの原本は `ios/appiconset/` で管理。差し替え後に同期コマンドを実行する：

```bash
make ios-sync-icons   # appiconset/ → xcassets へコピー
# 次回ビルドで反映される
```

---

## プロジェクト構成

```
ios/
├── appiconset/               アプリアイコン原本（PNG + Contents.json）
├── Gogai.xcodeproj/
├── Gogai/
│   ├── App/                  GogaiApp.swift / RootView.swift
│   ├── Models/               Article / Feed / Group / Settings（Codable）
│   ├── Network/              APIClient / Endpoint / APIError
│   ├── Repositories/         API 呼び出しラッパー
│   ├── Stores/               ObservableObject 状態管理
│   ├── Views/
│   │   ├── FilterFooterView.swift   全て / 未読のみ / 要約あり フィルター
│   │   ├── Onboarding/      ServerSetupView（初回 URL 設定）
│   │   ├── Sidebar/         SidebarView / FeedRowView / GroupRowView / Add*View
│   │   ├── Articles/        ArticleListView / ArticleRowView / ArticleDetailView
│   │   │                    HTMLContentView（WKWebView HTML レンダリング）
│   │   │                    BrowserView（アプリ内ブラウザ）
│   │   ├── AI/              AISummaryView（要約 / 翻訳）
│   │   └── Settings/        SettingsView / AdminView
│   ├── ViewModels/
│   └── Utilities/            ServerURLManager / DateFormatter+
└── GogaiTests/               XCTest ユニットテスト（34 件）
    ├── Network/
    ├── Repositories/
    └── Stores/
```

---

## 主な操作

| 操作 | 動作 |
|------|------|
| 記事一覧 右スワイプ | 既読/未読トグル（フルスワイプで即実行） |
| 記事一覧 左スワイプ | AI 要約生成（フルスワイプで即実行） |
| 記事詳細 上スワイプ | アプリ内ブラウザで記事を開く |
| 記事詳細 右上アイコン | デフォルトブラウザで記事を開く |
| フッター「要約あり」 | AI 要約済みの記事のみ表示 |
| リスト下スワイプ | フィード更新（Pull to Refresh） |

## 自動更新

以下のタイミングで記事一覧を自動更新する：

- **起動時**: サーバー URL が設定済みであれば即時取得
- **バックグラウンド復帰時**: フォアグラウンドに戻ったタイミングで最新記事を取得
- **5 分ごと**: アプリ起動中（フォアグラウンド・バックグラウンド問わず）に定期取得

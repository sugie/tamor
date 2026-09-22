# データ取扱い一覧と根拠

2026-09-22。プライバシーポリシー本文（`/apps/tamor/privacy`）の各記述について、
アプリ実装のどこを根拠にしたか、外部の一次資料は何をいつ確認したかを記録します。

## 1. アプリ本体（端末内、外部送信なし）

| データ | 実際の保存先 | 外部送信 | 根拠（Tamor リポジトリ） |
| --- | --- | --- | --- |
| 宝石（種類・カラット・入手日時・結果ID） | `Application Support/Tamor/save-v1.json` と `save-v1.backup.json` | なし | `Sources/Core/JewelSave.swift`（`JewelSaveFiles.standard` / `write`）、`Sources/Core/CaratCollection.swift`（`GemInstance`） |
| 深度ごとの結果（深度・評価・所要時間・日時・ルール版・枚数・弱点命中・得点） | 同上 | なし | `Sources/Core/CaratCollection.swift`（`DepthOutcome`） |
| プレイ記録（ゲーム種別・盤面サイズ・ミス数・ヒビ数・勝敗・日時・端末ID） | 同上（`journal`） | なし | `Sources/Core/PlayerProgress.swift`（`GameResultEvent`、`verification="localOnly"`） |
| 称号・自己ベスト・リングの回転／枠配置 | 同上 | なし | `Sources/Core/JewelSave.swift`、`Sources/Core/PlayerProgress.swift` |
| 中断した Crusher の途中経過 | `Application Support/Tamor/crusher-timed-checkpoint.json` | なし | `docs/crusher-weakpoint-update.md`、`Sources/App/JewelSceneState.swift` |
| 描画設定（窓の光・レイトレーシング・品質） | UserDefaults | なし | `Sources/App/JewelSceneState.swift`、`Sources/App/JewelRingApp.swift`（設定画面） |
| 端末内のランダム識別子 `tamor.deviceID` | UserDefaults | **なし（1.0 では送信しない）** | `Sources/App/JewelSceneState.swift:77-78`（`UUID().uuidString` を生成して保存）。利用箇所は `Sources/App/JewelMiniSession.swift:25` のローカル記録のみ |

再確認した事実：

- `Sources/PrivacyInfo.xcprivacy` は `NSPrivacyTracking=false`、`NSPrivacyCollectedDataTypes` は空。
  Required Reason API は UserDefaults（CA92.1）と SystemBootTime（35F9.1）。
- CloudKit はビルド対象外。`project.yml` の `sources.excludes` に `Core/CollectionCloudStore.swift` があり、
  `entitlements` の指定もないため `Tamor.entitlements`（CloudKit 記載あり）はビルドに使われていません。
- 書き出しは `ShareLink`（`Sources/App/JewelRingApp.swift:136`）で保存ファイルそのものを共有。送信先は利用者が選びます。
- 取り込みは `Button("保存データを取り込む").disabled(!state.save.gems.isEmpty)`（同 :137）。
  **コレクションが空のときだけ有効**という FAQ の記述の根拠です。
- 広告SDK・解析SDKは依存関係にありません（`project.yml` の `packages` は RevenueCat のみ）。

## 2. アプリ内課金（Apple / RevenueCat）

`Sources/App/PurchaseStore.swift` が使う RevenueCat API は
`Purchases.configure(withAPIKey:)` / `customerInfo()` / `offerings()` / `purchase(package:)` /
`restorePurchases()` / `customerInfoStream` のみ。カスタム App User ID の指定、属性設定、
アトリビューション、`collectDeviceIdentifiers()` の呼び出しはありません（2026-09-22 時点の `main` 派生ブランチで再確認）。

通信が発生する契機（`Sources/App/JewelRingApp.swift`）:

- 起動時 `.task { await purchases.refresh() }`
- フォアグラウンド復帰時 `.onChange(of: phase)` → `refresh()`
- 購入画面表示時 `.task { await store.refresh() }`
- 購入・復元の実行時
- `customerInfoStream` の監視中

→ **無料範囲だけを遊ぶ場合でも通信が発生する**という本文の記述の根拠。オフラインでは通信せず、ゲームは動作します。

| データ | 送信先 | 目的 | 根拠 |
| --- | --- | --- | --- |
| App Store レシート、商品ID、購入・復元の状態、最終利用日時 | RevenueCat | 検証・解放判定・復元 | RevenueCat プライバシーポリシー（下記 S7）、SDK Privacy Manifest（S6） |
| 匿名 App User ID | RevenueCat | 購入状態の管理 | S8（カスタムIDを設定しない場合は SDK が匿名IDを生成） |
| IDFV（`X-Apple-Device-Identifier` ヘッダ） | RevenueCat | 課金基盤の運用 | S5（`HTTPClient.swift` タグ 5.90.2 を 2026-09-22 に再取得して確認） |
| 機種・OS・アプリ版数・ビルド番号・Bundle ID・優先言語・ストアフロント・SDK版数・サンドボックス判定 | RevenueCat | 運用・互換性・障害調査 | S5（同上のヘッダ一覧） |
| IPアドレス | RevenueCat | 通信の成立 | 通信に伴う受信。S7 |
| 支払情報（カード番号等） | **Apple のみ。当方・RevenueCat は取得しない** | 決済 | S1・S7 |

- IDFA は取得・送信しません（`collectDeviceIdentifiers()` を呼んでいないため）。
- RevenueCat は処理者（Data Processor）で、データは米国の AWS に保存されると同社が説明（S7）。
- 保存期間：「当方のアカウントが存続するあいだ＋その後6年」と同社が説明（S7）。
- SDK バージョンは `Tamor.xcodeproj/.../Package.resolved` で 5.90.2（revision `4faa17c4…`）を確認。

## 3. サポートサイト・問い合わせフォーム

根拠はサイトリポジトリの `app/Http/Controllers/ContactController.php`。

| データ | 処理 | 根拠（行） |
| --- | --- | --- |
| 名前・メール・件名・本文 | 検証のうえ、窓口宛メールと自動返信メールを送信 | `validate()`、`Mail::to(config('company.contact_email'))`、`Mail::to($validated['email'])` |
| IPアドレス、User-Agent（先頭200文字） | 迷惑送信として拒否した場合にログへ記録 | `logRejected()` |
| 暗号化されたフォーム表示時刻トークン `_form_time` | 送信までの経過時間の検証 | `show()` の `encrypt(time())`、`submittedTooFast()` |
| 隠しフィールド `inquiry_ref`（ハニーポット） | 自動送信の検出 | `send()` の冒頭 |
| Turnstile トークン・IPアドレス | **設定で有効なときのみ** Cloudflare へ送信 | `verifyTurnstile()`。既定は `TURNSTILE_ENABLED=false` |
| セッション／CSRF の Cookie | フォームのセキュリティ | Laravel 標準 |

- アクセス解析ツール・広告タグ・外部トラッキングは導入されていません（既存の `/privacy` の記述と一致）。
- **ログの保存期間・サーバーのリージョン・バックアップ期間は未確認**のため本文に数値を書いていません。
  `TAMOR_LOG_RETENTION` / `TAMOR_LOG_RETENTION_EN` を設定したときだけ表示されます。
- 本文の Turnstile 記述は `config('services.contact_form.turnstile.enabled')` に追従します
  （使っていない対策を「使っている」と書かないため）。

## 4. TestFlight

| データ | 処理主体 | 開発者が見えるもの | 根拠 |
| --- | --- | --- | --- |
| テスターの招待メール・TestFlight 上の氏名 | Apple | テスター一覧とテスト状況（App Store Connect） | S3 |
| フィードバック本文・スクリーンショット・端末／OS／アプリ版数 | Apple 経由 | App Store Connect の Feedback | S3 |
| クラッシュ情報、セッション数・クラッシュ数の指標 | Apple 経由 | App Store Connect の指標 | S3 |
| ベータ版のアプリ内課金 | Apple（サンドボックス） | 実際の支払いは発生しない | S4 |

## 出典（一次資料。括弧内は確認日）

| # | 資料 | URL | 確認日 | この文書で使った事実 |
| --- | --- | --- | --- | --- |
| S1 | Apple Licensed Application End User License Agreement（標準EULA） | https://www.apple.com/legal/internet-services/itunes/dev/stdeula/ | 2026-09-22 | 標準EULAの存在、独自EULAで置き換えられること、"AS IS" と責任制限の条項 |
| S2 | TestFlight（Apple Developer） | https://developer.apple.com/testflight/ | 2026-09-22 | 外部テスター上限 10,000名、内部100名、TestFlight アプリの利用、スクリーンショットからのフィードバックとクラッシュレポート |
| S3 | TestFlight overview（App Store Connect ヘルプ） | https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/ | 2026-09-22 | 「Your build becomes unavailable for testers after 90 days.」、初回ビルドはベータ審査が必要、フィードバックとセッション／クラッシュ指標の確認 |
| S4 | Testing subscriptions and In-App Purchases in TestFlight | https://developer.apple.com/help/app-store-connect/test-a-beta-version/testing-subscriptions-and-in-app-purchases-in-testflight | 2026-09-22 | 「Apps downloaded from TestFlight will automatically operate in a sandbox environment.」 |
| S5 | purchases-ios 5.90.2 `HTTPClient.swift` | https://raw.githubusercontent.com/RevenueCat/purchases-ios/5.90.2/Sources/Networking/HTTPClient/HTTPClient.swift | 2026-09-22 | 既定ヘッダ一覧。`X-Apple-Device-Identifier`（IDFV）、`X-Platform-Device`、`X-Client-Version`、`X-Client-Bundle-ID`、`X-Preferred-Locales`、`X-Storefront`、サンドボックス判定等 |
| S6 | purchases-ios 5.90.2 Privacy Manifest | https://raw.githubusercontent.com/RevenueCat/purchases-ios/5.90.2/Sources/PrivacyInfo.xcprivacy | 2026-09-21（前タスク）※本タスクでは再取得していない | 収集データ型は Purchase History のみ（非リンク・非トラッキング・App Functionality） |
| S7 | RevenueCat Privacy Policy | https://www.revenuecat.com/privacy | 2026-09-22 | 「We are not the Data Controllers of this data and act as Data Processors.」、米国 AWS に保存、保存期間「アカウント存続中＋6年」、収集項目（端末種別・OS、最終利用日時、Apple レシート） |
| S8 | RevenueCat Restoring Purchases | https://www.revenuecat.com/docs/getting-started/restoring-purchases | 2026-09-22 | 復元は「同じストアアカウント（Apple）」が条件。匿名App User ID の扱い |
| S9 | Apple: Request a refund for apps or content | https://support.apple.com/118223 | 2026-09-22 | 返金は reportaproblem.apple.com から利用者が申請 |
| S10 | Apple Privacy Policy | https://www.apple.com/legal/privacy/ | 未取得（URLのみ本文から参照） | 参照リンクとしてのみ使用 |
| S11 | App privacy details on the App Store | https://developer.apple.com/app-store/app-privacy-details/ | 2026-09-21（前タスク）※本タスクでは再取得していない | 「収集」の定義、第三者SDKの収集も開発者の申告責任 |
| S12 | RevenueCat Apple App Privacy ガイド | https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy | 2026-09-21（前タスク）※本タスクでは再取得していない | Purchase History の申告が必須、匿名IDなら「リンクなし」を選べる |

S6・S11・S12 は前タスク（`docs/release/claude/sources.md`、2026-09-21）の記録をそのまま引き継いでいます。
App Store Connect へ実際に回答する前に再取得してください。

---

# 内部レビュー資料：App Store Connect「Appのプライバシー」回答案

**この節は公開ページの本文ではありません。**App Store Connect へ入力する前の検討用です。
本タスクでは**回答の送信も App Store Connect への入力も行っていません。**

Apple の定義では、第三者SDKが端末外へ送信して保持するデータも「収集」に当たり、申告は開発者の責任です（S11）。
したがって、アプリ本体の Privacy Manifest が「収集なし」であっても、
**「データを収集していません」は選べない**と判断しています。

| データ型 | 回答案 | 目的 | ユーザーにリンク | トラッキング | 判断の根拠 |
| --- | --- | --- | --- | --- | --- |
| Purchases > Purchase History | **収集する** | App Functionality（RevenueCat 管理画面で売上集計を見るなら Analytics も） | いいえ | いいえ | S6・S12。SDK 同梱 Manifest は App Functionality のみ、公式ガイドは Analytics も挙げる |
| Identifiers > User ID | 申告不要の可能性が高い | — | — | — | カスタム App User ID を使わず SDK 生成の匿名IDのみ（S12） |
| Identifiers > Device ID | **要判断（安全側は「収集する」）** | App Functionality | いいえ | いいえ | SDK が IDFV をヘッダで送信（S5）。RevenueCat の Manifest・公式ガイドには記載がない |
| Diagnostics / Usage Data | 要判断 | — | — | — | 機種・OS・版数等のヘッダ送信はある（S5）が、公式ガイドは申告対象に挙げていない |
| その他（位置情報・連絡先・写真・健康等） | 収集しない | — | — | — | アプリが要求していない |

関連する決定事項：

- アプリ本体の `Sources/PrivacyInfo.xcprivacy` の `NSPrivacyCollectedDataTypes` に
  Purchase History（および判断により Device ID）を追記するかは**未決定**です。本タスクでは Manifest を編集していません。
- ゲームの進行データは端末外へ送信しないため「収集」に当たりません。将来 CloudKit 等を追加する場合は再評価が必要です。
- App Store Connect の Privacy Policy URL には、[README.md](README.md) の候補URLを使います（公開後）。

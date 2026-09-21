# Tamor 0.4.0 接続・リリース手順

2026-09-21。ローカル実装済みの機能を実サービスへ接続するための手順。ストア商品登録、外部設定変更、App Store審査提出は未実施。

## RevenueCat / App Store Connect

1. Bundle ID `com.marcottlab.tamor` のアプリに、非消耗型商品 `com.marcottlab.tamor.world1.depth` を作成。日本の希望価格は回答D03の¥400。各国価格はApp Store Connectで確認する。
2. RevenueCatのAppleアプリに商品を登録し、Entitlement `world1_full_depth` と関連付ける。現在のOfferingへ、この商品を持つPackageを追加する。既存の商品IDを使う場合は `PurchaseStore.productID` も合わせる。
3. 必要なAppleサービス認証情報をRevenueCatの管理画面に設定する。p8秘密鍵はアプリ・Git・チャットへ入れない。
4. RevenueCatの**公開iOS SDKキー（appl_…）**をXcodeのTamorターゲットのUser-Defined Build Setting `TAMOR_REVENUECAT_API_KEY` に設定する。Info.plistの `RevenueCatAPIKey` に展開される。プロジェクト再生成を行う場合は、ローカルxcconfigまたはビルド引数で値を保持する。未設定では購入不能となる。
5. Sandboxで購入成功、キャンセル、保留、復元、アプリ再起動、通信断、商品取得失敗、返金・権利取消後の新規深度制限を確認する。所持宝石は権利取消後も削除しない。再インストールでは購入復元とCloudKitの宝石復元を別々に確認する。

アプリはローカライズ価格を商品から取得し、設定・購入画面に復元を用意。購入は深度4〜6への挑戦権であり、20ctそのものやWorld 2を含まない。前深度クリアとS3連続の技能条件は購入後も必要。

公式資料：[iOS SDK](https://www.revenuecat.com/docs/getting-started/installation/ios)、[購入](https://www.revenuecat.com/docs/getting-started/making-purchases)、[商品表示](https://www.revenuecat.com/docs/getting-started/displaying-products)。

## CloudKit と実機署名

コンテナ案は `iCloud.com.marcottlab.tamor`。アプリのEntitlementsと `CollectionCloudStore` に設定済み。既存コンテナを使用する場合は両方を同じIDに変更する。

1. Apple DeveloperのApp ID `com.marcottlab.tamor` でiCloud/CloudKitを有効化し、このコンテナを関連付ける。XcodeのSigning & Capabilitiesでも正しいチーム・コンテナを選択する。
2. 開発用プロビジョニングプロファイルを更新・取得する。今回の実機署名ビルドは「プロファイルがicloud-container-identifiersに一致しない」で停止した。端末への新バージョンのインストールは未実施。
3. Development環境のプライベートDBで、レコード型 `TamorCollection`、フィールド `payload`（Asset）と `schemaVersion`（Int64）を確認する。固定レコード名は `collection-v3`。開発環境で初回書き込みを確認してからProductionへスキーマをデプロイする。
4. 同じApple Accountの2台で、片方の取得→もう片方の復元、両方のオフライン取得→再接続、競合時の再試行、通信エラー、未ログイン、空の新端末、旧保存データ移行を確認する。端末のリング角度は同期で変更されないことを確認する。
5. TestFlight/配布ビルドはProductionを使用するので、開発環境のデータだけで成功と判断しない。実機で再インストール後の宝石復元を確認する。

同期は起動・復帰・プレイ終了後・設定の手動操作で実行。未ログイン・通信断でも端末保存を保持。競合は不変の個体ID・結果IDの和集合で解決し、同IDの内容が違えば上書きせずエラーにする。異なるApple Accountを端末で切り替えた場合の所持分離やゲーム独自ログインは未実装で、現版は端末の所持品と現在のiCloudを併合する。公開リング共有は未接続。

公式資料：[CloudKitレコード保存](https://developer.apple.com/documentation/cloudkit/ckdatabase/save(_:)-1j6fq)。

## 実機・公開前に残る確認

- iPhone 12 miniでCrusherを10分連続実行し、フレーム時間・発熱・メモリ・破片の残留を計測。0.1ctの操作性、20ctの配置、窓格子の屈折も確認する。
- 最高深度の難度とS3連続の到達性をプレイ評価。初期数値は回答済み案であり、ゲーム間で同等の難しさを実証したものではない。
- VoiceOver・大きな文字・iPadを実機で確認。Crusherにはラベルと状態を付けたが、VoiceOver固有のゲーム操作は未検証。
- Releaseでは開発用プレビューを除外。World 2は回答D17によりComing soonのみ。商品特典には含めない。
- サポート/プライバシーURL、ストア用説明・画像、連絡先、年齢区分、プライバシー申告、素材権利と配信地域を確定する。回答D22は参加資格の確認完了を示していない。
- アプリと初回IAPの審査情報を準備してから提出する。希望提出日は9/21だが、現段階で本番接続と実機検証は完了していない。

既存Privacy Manifestの使用API理由とRevenueCat同梱Manifestを確認した。App Storeのプライバシー回答は実際のクラウド・購入データ利用に合わせて別途申告する。単調増加時計の生値はクラウドへ送らず、成績の経過時間を送る。[AppleのRequired Reason API説明](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitypereasons?language=objc)。

## iPhone 12 mini用の端末保存確認版

2026-09-21：自動署名更新後もCloudKitコンテナの許可一覧が空だったため、実機プレイ確認用にDebugだけの `TAMOR_LOCAL_DEVICE` コンパイル条件を追加。この条件ではCloudKitを生成せず、端末内保存を使用する。通常ビルドのCloudKit設定は維持。RevenueCatの未設定状態も変更しない。

再現するビルド指定：Debug構成、`DEVELOPMENT_TEAM=PP7EWEKNZZ`、`CODE_SIGN_ENTITLEMENTS=`、`SWIFT_ACTIVE_COMPILATION_CONDITIONS=DEBUG TAMOR TAMOR_LOCAL_DEVICE`。同じBundle IDで上書きし、既存アプリはアンインストールしない。これはiCloud復元の検証用でもApp Store提出用でもない。コンテナを関連付けたら、上記の2つの上書き設定を外して通常ビルドに戻す。

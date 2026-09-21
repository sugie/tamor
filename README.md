# Tamor

SwiftUI + Metalのジュエル収集ゲーム。iOS 17以降、iPhone / iPad。Bundle IDは `com.marcottlab.tamor`。回答済み `docs/jewel-decisions-v4.xlsx` を反映し、追加指示でCrusherとRubyを更新し、日英対応・端末保存のみの1.0（ビルド5）へ公開準備中です。

## 起動

`Tamor.xcodeproj` をXcodeで開き、Scheme **Tamor** とiPhoneシミュレーターを選んで実行します。初回はRevenueCat Swift Packageの取得に通信が必要です。`Package.resolved` は5.90.2を記録しています。プロジェクト定義は `project.yml`。追加ファイルがある場合は `xcodegen generate` で再生成します。

初回は所持0個。「ミニゲーム・深度を選ぶ」から始めるか、空き台座をタップします。リングはスワイプ回転、宝石はシングルタップで情報、ダブルタップでゲーム。拡大・内部・原子表示は廃止しました。開発ビルドだけに所持を変更しない4種のプレビューがあります。

| World 1の宝石 | ミニゲーム |
| --- | --- |
| ダイヤモンド | Glass Break：自動開始後、赤い点を期限内にタップ |
| ルビー | Glass Trace：十字と縦横ガイドを使って緑の点を追跡、ヒビ3本で失敗 |
| サファイア | クルクルワールド：自動開始、同じ回転方向のペアをタップ |
| 黒曜石 | Crusher Room：10秒で何枚割れるかに挑戦、1枚3タップ、弱点命中で加点 |

宝石別に深度1〜6へ進行。無料範囲は深度1〜3、最大3.00ct。深度4〜6には買い切りの購入権利も必要です。報酬は成績から決定し、深度6で同じ宝石のS評価3連続により20.00ct。体力・サブスクリプション・ランダム抽選はありません。World 2はComing soon表示だけです。

リングは種類ごとの最大個体を12固定枠へ表示します。同重量なら先に入手した個体を優先。小さい個体も「宝石箱」に残り、種類・重量・入手順で探せます。幅375ptで1ctの表示幅17pt、幅はctの立方根に比例するゲーム用の尺度です。実物のmmを再現するものではありません。宝石箱は軽量な模式アイコンで相対サイズを示します。

## 保存と復元

端末内 `Application Support/Tamor/save-v1.json`。ファイル名は互換性のため維持、内容の `schemaVersion` は3。原子的置換と `save-v1.backup.json` を使用し、未知の将来スキーマは上書きしません。旧サイズは3乗をctへ換算し、旧履歴と最大所持を移行します。ブラックオニキスとエメラルドは「旧コレクション」に残ります。報酬は結果IDで重複排除し、書き込み成功後に画面へ反映します。

Crusherの未完了進行は同じフォルダの `crusher-timed-checkpoint.json` へ保存。再起動後は中断時の深度を先に再開します。明示的な退出ではその10秒チャレンジの未完了分を破棄し、確定済み報酬を保持します。

初回公開版ではCloudKitを使用しません。同期呼出し・同期UI・iCloud署名を除外し、既存の同期ソースとEntitlementsファイルは将来用に保持しています。宝石は端末保存とJSON書き出し・取り込みで保管します。RevenueCatによる購入復元はWorld 1の解放権利が対象で、宝石は復元しません。

旧JewelRingからのJSON取り込みはコレクションが空の時だけ可能。既存Tamorの保存は自動移行します。

## 課金の接続と公開準備

Tamor専用のRevenueCat公開SDKキーを `project.yml` に登録し、`Config/Info.plist` を介してアプリへ渡します。秘密キーではありません。Apple商品 `com.marcottlab.tamor.world1.depth`、Entitlement `world1_full_depth`、既定Offering `default` のLifetimeパッケージを接続済みです。日本400円・米国1.99ドル、商品の配信地域は日本・米国。画面の価格はストアから取得して表示します。

購入状態は購入・復元・フォアグラウンド復帰に加え、RevenueCatのCustomerInfo更新でも反映します。Debugの `--ui-test` だけSDK通信を無効化し、UI検証データを分離します。実購入の試験ではこの引数を付けません。

**実購入・復元・コード引換は未検証、App Storeの審査には未提出です。** 最新状況は[1.0公開準備の検証記録](docs/release/verification-1.0.md)を参照してください。旧v4接続手順のCloudKit有効化は初回公開版には適用しません。

## 描画

宝石種ごとの屈折率・RGB吸収と光の窓格子を利用します。RGB吸収は美術用近似です。サファイアと黒曜石の材質を追加しました。RTは対応GPUで選択中の宝石1個へ適用し、通常描画へフォールバックします。シミュレーターではRT無効。互換Metal APIを使用し、Metal 4専用機能・A20固有最適化はありません。

Crusherの破片生成は150msの予算または低品質判定で粗い形状へ切り替えます。CPU/GPU時間・温度・省電力状態から描画品質を調整しますが、期限と報酬条件は変えません。実機の継続性能・発熱は別途測定が必要です。

## 構成と検証

- `Sources/Core`：保存、カラット・深度・報酬、Crusher判定、CloudKit。
- `Sources/App`：リング、宝石箱、各ゲーム、購入画面。
- `Sources/Rendering`：Metal描画、入力、宝石光学。
- `Sources/Features/Glass`：亀裂・破片エンジン。
- `Tests`：移行・保存・ルール・GPU描画・UI。

基本ロジックは `bash scripts/test-core.sh`。iOSテストは `xcodebuild -project Tamor.xcodeproj -scheme Tamor -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test CODE_SIGNING_ALLOWED=NO`。

[採用回答](docs/accepted-decisions-v4.md)・[検証記録](docs/verification-v4.md)・[旧版の検証記録](docs/verification.md)。旧版文書と相違する箇所は、回答済み第4版とこのREADMEが現在の仕様です。

最新の変更は[Crusher 10秒・Weak Point / Rubyガイド](docs/crusher-weakpoint-update.md)を参照。

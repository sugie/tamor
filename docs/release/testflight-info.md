# Tamor 1.0 TestFlight入力用メモ

2026-09-22。App Store一般公開とは別のベータ配布。下記文案は準備済みであり、管理画面へ保存・審査提出したことを示すものではない。

## ベータ版の説明（日本語）

Tamorは、4つのミニゲームで宝石を集めるゲームです。ルビーの追跡、サファイアの回転ペア、ダイヤモンドのタイミングタップ、黒曜石の10秒Crusherに挑戦できます。獲得した宝石はリングと宝石箱に残ります。

無料は深度1〜3。World 1の買い切り解放で深度4〜6に挑戦できますが、前深度のクリアなどの条件は残ります。World 2は予告表示のみです。宝石・プレイ記録は端末内に保存され、購入の復元では戻りません。

## Beta App Description (English)

Tamor is a gem-collecting game with four mini-games: trace a target for rubies, match rotating pairs for sapphires, tap timed targets for diamonds, and take on the 10-second Crusher challenge for obsidian. Keep your gems in the ring and Gem Box.

Depths 1–3 are free. The one-time World 1 unlock grants access to Depths 4–6; progression and skill requirements still apply. World 2 is a preview only. Gems and play records are saved on this device and are separate from restored purchase entitlements.

## テストしてほしいこと

- 初回起動から4種のミニゲームを開始できるか。
- 判定、ゲームの難しさ、説明で分かりにくい箇所。
- 結果画面からリングへ戻り、宝石箱に獲得した宝石が残るか。
- 一時停止・バックグラウンド復帰・アプリ再起動後の動作。
- iPhone／iPadで文字やボタンの見切れ、タップ位置のずれがないか。
- 数分間のプレイで発熱・電池消費・カクつきが気になるか。
- 日本語／英語の自然さと未翻訳箇所。
- 購入テストを行う場合はTestFlight版であることを確認し、World 1解放と復元の結果を報告。宝石データの復元とは別です。

報告時は端末名、OS、アプリのバージョンとビルド、操作手順、期待した結果、実際の結果、可能ならスクリーンショットを添えてください。既存データを持つ場合はアプリ削除前に設定から書き出してください。

## What to Test

Please try all four mini-games, reward collection, the Gem Box, pause/resume, and relaunching the app. Check for clipped text or inaccurate tap targets on iPhone and iPad, unclear instructions, difficulty, heat, battery use, and frame drops. Report Japanese or English wording issues. If testing purchases, confirm you are using the TestFlight build and distinguish the World 1 entitlement from locally saved gems.

Include the device, OS, app version/build, steps, expected and actual results, and a screenshot when possible. Export existing save data before deleting the app.

## ベータ審査向け情報（文案）

- アカウント登録・ログインは不要。
- ホームの「宝石と深度を選ぶ」から4種類の深度1をプレイ可能。
- World 1の深度4〜6は非消耗型商品 `com.marcottlab.tamor.world1.depth`、RevenueCatの `world1_full_depth` に対応。
- 購入しても前深度のクリア条件を省略しない。宝石を直接販売せず、無料範囲で4種類の基本ゲームを試せる。
- 設定に「購入を復元」、宝石データの書き出し・取り込みあり。
- CloudKit同期なし。World 2はComing soonのみで購入特典には含まれない。
- 実購入・復元の成功を未確認のまま「検証済み」と記入しない。

## 入力前に確定が必要なもの

- ベータフィードバック用メール。
- ベータ審査連絡先（姓・名・電話・メール）。公開サイトの窓口や別アプリの連絡先から無断で転用しない。
- Tamor専用プライバシーポリシーURL。`/apps/tamor/privacy` はClaudeへの提案で、まだ公開済みURLではない。
- 招待リンクかメール招待か、テスター人数の上限。
- 暗号化／輸出コンプライアンスの回答。

参考：
- [外部テスターの招待](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)
- [テスト情報の入力](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information/)

初回の外部テストにはAppleのベータ審査が必要。ビルドのアップロード完了、Appleの処理完了、外部テスト承認、招待リンク有効化は別々の状態として記録する。

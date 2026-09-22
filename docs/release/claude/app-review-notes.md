# Tamor 1.0 App Store 審査メモ(草稿) / App Review Notes (DRAFT)

> 2026-09-21、Claude作成。提出・App Store Connect への入力は行っていません。`【要確認】`/`[TO CONFIRM]` を埋めてから使用してください。前提: CloudKit なし・端末内保存のみ・RevenueCat 経由の非消耗型1商品・World 2 は Coming soon。

## A. 「App Review に関する情報 > メモ」欄に貼る英文案(4,000 バイト以内)

```
Tamor is a single-player gem-collecting game designed for iPhone running iOS 26.0 or later. No account or login is required, so no demo account is provided.

HOW TO PLAY
- Launch the app. From the ring screen, tap "Choose Gem & Depth" (or tap an empty named pedestal) and pick a gem and Depth 1.
- Each of the four gems has its own mini-game: Diamond = Glass Break (tap red dots in time), Ruby = Glass Trace (follow the green dot), Sapphire = Kurukuru World (tap pairs spinning the same way), Obsidian = Crusher Room (break as many glass plates as possible in 10 seconds).
- Clearing a depth awards a gem whose carat weight depends on the result, and opens the next depth for that gem.
- Tap a collected gem on the ring to bring it into a central spotlight at the same scale. Swipe to rotate it. Single-tap the gem (or tap "Back to Ring") to animate it back to its original ring position.
- Tilt the device to tilt the ring. This effect can be disabled in Settings and is disabled when Reduce Motion is on. Motion data is processed on-device only and is never stored or transmitted.

IN-APP PURCHASE
- One non-consumable: "[TO CONFIRM: IAP display name]" (product ID com.marcottlab.tamor.world1.depth).
- Free play covers Depths 1-3 (gems up to 3.00 ct). The purchase unlocks access to Depths 4-6 of World 1 for all four gems.
- The purchase does NOT grant any gem directly. The 20.00 ct gem still requires skill: clearing the previous depths and earning three consecutive S grades at Depth 6. This is stated on the purchase screen.
- Where to find it: ring screen > "Unlock World 1 Depths 4-6", or choose a locked Depth 4-6 in "Choose Gem & Depth". Depths 4-6 also require clearing the previous depth first, so the purchase screen is the quickest way to reach the product.
- Restore: "Restore Purchases" is available on the purchase screen and in Settings (slider icon, top right) > Purchases.
- There are no subscriptions, consumables, stamina systems, random rewards or loot boxes. Rewards are determined only by play results.
- Purchases are processed by Apple In-App Purchase. We use the RevenueCat SDK to validate and restore the entitlement.

DATA STORAGE
- Game progress and the gem collection are stored only on the device. Version 1.0 has no cloud sync and no account. "Restore Purchases" restores the unlock only; it does not restore gems. This is explained in the app. [TO CONFIRM: final in-app wording]

WORLD 2
- The "WORLD 2" page reached with the right arrow shows a "Coming soon" notice only. It contains no playable content, is not sold, and is not part of the World 1 unlock. It is not mentioned as an available feature in the store listing. [TO CONFIRM: see note C-1 below]

OTHER
- No ads, no third-party analytics, no tracking. The privacy policy is linked in Settings > Support & Legal > Privacy Policy. [TO CONFIRM: App Store Connect metadata and final publication of the policy]
- The app is portrait-only and designed for iPhone running iOS 26.0 or later. Operation in iPad compatibility mode is not guaranteed. Ray tracing is an optional visual setting on supported GPUs and is off by default.
- Contact: [TO CONFIRM: name, email, phone for App Review]
```

## B. 日本語での説明(社内確認用。上の英文と同内容)

- アカウント不要のためデモアカウントなし。
- iOS 26.0 以上の iPhone 向け・縦向き専用。iPad の互換モードでの動作は保証しません。
- 遊び方: リング画面 →「宝石と深度を選ぶ」→ 宝石と深度1を選択。4種の宝石それぞれにミニゲーム。
- 獲得済み宝石をタップすると同じ倍率で中央へ移動し、スポットライトで単体表示。スワイプで回転し、宝石のシングルタップまたは「リングに戻る」で逆の演出を経て復帰。端末を傾けるとリングも傾く（設定で無効化可）。モーション情報は端末内の表示にのみ使用し、保存・送信しない。
- IAP: 非消耗型1点(`com.marcottlab.tamor.world1.depth`)。無料は深度1〜3・最大3.00ct。購入で World 1 の深度4〜6に挑戦可能になる。**宝石そのものは付与されない。20.00ct は前深度のクリアと深度6でのS評価3連続という技能条件が残る**(購入画面に明記済み)。
- 到達方法: リング画面の「World 1の深度4〜6を解放」。復元は購入画面と設定>購入。
- サブスク・消耗型・体力・ランダム報酬・ルートボックスなし。
- 保存: 端末内のみ。1.0 はクラウド同期なし。「購入を復元」で戻るのは解放の権利だけで、宝石は戻らない。
- World 2 は Coming soon 表示のみ、販売対象外。

## C. 審査上のリスクと提出前チェック(ガイドライン番号は出典5)

1. **World 2 の「Coming soon」表示(2.1(a)、2.3.1(a))。** 2.1(a) は提出物からプレースホルダや一時的コンテンツを除くよう求め、2.3.1(a) は実際に提供していないコンテンツの宣伝を禁じています。アプリ内の予告ページがこれに当たると判断されるかは審査次第で、Claude には断定できません。リスクを下げるなら (a) 1.0 では World 2 ページを非表示にする、(b) 残す場合はストア掲載文・スクリーンショットで World 2 に触れず、審査メモで「販売対象外の予告のみ」と明記する、のいずれか。**判断は人間/Codex 側でお願いします(ゲーム仕様のため Claude は変更していません)。**
2. **IAP が審査員から見えて機能すること(2.1(b))。** RevenueCat の本番 API キー、App Store Connect の商品、Offering/Package/Entitlement(`world1_full_depth`)の接続が済み、Sandbox で購入・キャンセル・復元が通ること。キー未設定のビルドでは購入ボタンが無効のままになり、リジェクト要因になります。
3. **初回 IAP はアプリの新バージョンと同時提出**(出典9)。IAP の審査用スクリーンショット(購入画面)と審査メモが必要(出典8)。
4. **購入が必要な範囲の明示(2.3.2)。** 掲載文に「深度4〜6はアプリ内課金が必要」と記載(`store-listing.md` に反映済み)。
5. **価格をスクリーンショット・名前・サブタイトルに入れない(2.3.7)。** 購入画面のスクリーンショットをストア画像に使う場合は価格表示に注意。
6. **復元手段(3.1.1)。** 実装済み(購入画面・設定)。
7. **プライバシーポリシーをメタデータとアプリ内の両方に(5.1.1(i))。** 設定 > サポートと規約 に日英のプライバシーポリシーへのリンクを追加済み（2026-09-22、Mac側）。App Store ConnectへのURL入力と、リンク先の草案表示解除は残る。
8. **iCloud 記述の除去。** 現在の設定画面・購入画面・README に iCloud 同期の説明が残っています(「iCloudと宝石の復元」「宝石の復元は設定のiCloud同期から」等)。1.0 で同期しないなら、UI 文言・Entitlements(`Tamor.entitlements` に CloudKit)・審査メモ・掲載文を一致させてください。Codex が対応中と理解しています。
9. **輸出コンプライアンス。** 通信は HTTPS(OS 標準の暗号)のみと見られ、Apple の説明では免除対象に当たる可能性が高いですが、`ITSAppUsesNonExemptEncryption` の設定と App Store Connect の質問への回答は人間が行ってください(出典11, 12)。
10. **年齢区分。** ギャンブル・疑似ギャンブル・ルートボックスはいずれも「なし」に該当する内容です(ランダム報酬なし)。新しい質問票への回答は人間が行ってください(出典13)。
11. **アイコン。** `AppIcon.png` にアルファチャンネルあり。また旧4種の宝石配色のままです(`asset-rights-inventory.md` 参照)。
12. **対応端末。** iPhone 専用・iOS 26.0 以上。iPad 用スクリーンショットは不要。iPad での互換モード動作を排除する設定ではありませんが、その動作は保証しません。iPhone 17 世代の実機は未検証。iPad 第8世代（iPadOS 26.7）は互換モードでUIテストと通常起動を確認済み（[検証記録](../ipad-verification-2026-09-22.md)）。iPhone 12 mini の検証状況は `handoff.md` の最新追記を参照。
13. **サポートURL**は実際の連絡先に到達できるページが必須(出典7)。未確定。

## D. App Privacy(「Appのプライバシー」)回答案 — 人間が確定してください

Apple の定義では、第三者 SDK が端末外へ送信して保持するデータも「収集」に当たり、申告は開発者の責任です(出典1, 2)。**アプリ本体の Privacy Manifest が「収集なし」でも、App Store Connect で「データを収集していません」は選べないと考えます。**

| データ型 | 回答案 | 根拠 |
| --- | --- | --- |
| Purchases > Purchase History | **収集する。** 目的: App Functionality。Analytics も選ぶかは要判断(RevenueCat 公式ガイドは Analytics と App Functionality の両方を挙げる一方、SDK 同梱 Manifest は App Functionality のみ。RevenueCat のダッシュボードで売上集計を見るなら Analytics も選ぶのが安全側) | 出典18, 19 |
| Identifiers > User ID | 申告不要の可能性が高い(カスタム App User ID を使わず、SDK 生成の匿名IDのみ)。RevenueCat 公式ガイドの条件に沿った判断 | 出典18, 22 |
| Identifiers > Device ID | **要判断。** SDK 5.90.2 は IDFV をリクエストヘッダで送信している(出典20)が、RevenueCat の Manifest と公式ガイドには記載がない。安全側は「収集する・App Functionality・トラッキングなし」。RevenueCat サポートへの確認を推奨 | 出典1, 20 |
| Usage Data / Diagnostics | 機種・OS・アプリ版数等のヘッダ送信はあるが、RevenueCat 公式ガイドは申告対象に挙げていない。要判断 | 出典18, 20 |
| ユーザーにリンク | 匿名IDのみで個人を特定できないなら「いいえ」を選べる、というのが RevenueCat 公式ガイドの説明。Device ID を申告する場合のリンク有無は要判断 | 出典1, 18 |
| トラッキング | **なし**(広告・データブローカー連携なし、IDFA 不使用) | 出典1 |

※ ゲームの進行データは端末内のみで送信しないため「収集」に当たりません。CloudKit を将来追加する場合は再評価が必要です(利用者自身の iCloud プライベートDBでも、Apple の定義に照らした検討が要ります)。

## E. 米国価格

¥400 に対応する米ドル額を Apple は公表しておらず、App Store Connect で日本を基準ストアフロントにして商品を作成した時点で表示される額が正です(出典14)。**掲載文・審査メモにドル額を書いていません。**

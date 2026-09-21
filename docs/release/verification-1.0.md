# Tamor 1.0 公開準備の検証記録

2026-09-22追記：実機1.0／5への更新、アイコンのアルファ除去、署名付きアーカイブ・IPA書き出しまで進行。[実機更新とTestFlight準備](device-testflight-2026-09-22.md)を参照。以下は9月21日時点の記録。

2026-09-21。前タスクで中断した公開準備を継続。未コミット差分を保持し、コミット・リセット・審査提出は実施していない。

## 実装

- 1.0、ビルド5、iPhone/iPad対応を維持。
- CloudKit同期呼出し・状態・UI・署名を除外。CollectionCloudStore.swiftはビルド対象から除外して保持。既存クラウドデータとコンテナは変更しない。
- 宝石は既存JSON保存・書き出し・取り込み。購入復元との違いを日英で説明。
- CustomerInfoストリームを監視し、購入状態を更新。現在のOfferingから商品を照合し、取得失敗時は古い商品価格を破棄。
- 公開SDKキーはConfig/Info.plistへ明示登録。独自INFOPLIST_KEYだけでは生成アプリに入らない問題を修正し、最終Releaseの値一致を検証。
- Claudeの英語化を統合。動的な宝石名・結果・エラー・購入文言、VoiceOverラベル、日英String Catalogを含む。保存ID・称号比較・ゲーム判定は翻訳しない。
- クルクルワールドの盤面を利用可能な幅・高さと上限480ptの範囲で正方形に維持。iPadでセルの位置とタップ判定がずれる不具合を修正。既存の英語UIテストへ盤面の縦横寸法チェックを追加。
- 購入画面をスクロール対応に変更。英語見出しの末尾省略をスクリーンショットで発見し、折り返しを修正。
- UIテストはDebugの--ui-testで課金通信を無効化。英語の文字列検査は単一のUIスナップショットを使い、自動結果画面の消失と競合しないよう修正。小型画面の設定確認はスクロールに対応。

## 外部設定（保存・画面確認済み）

- [App Store Connect Tamor](https://appstoreconnect.apple.com/apps/6814390528/distribution)：App ID 6814390528、iOS 1.0、主言語日本語、SKU tamor-ios。アクセス制限ありで本人を選択。
- [World 1 Full Depth](https://appstoreconnect.apple.com/apps/6814390528/distribution/iaps/6814390656)：Apple ID 6814390656、非消耗型、商品ID com.marcottlab.tamor.world1.depth。日本400円を基準に米国1.99ドル。商品の配信は日本・米国の2地域。日英の商品名・説明を保存。審査用スクリーンショット等は未登録。
- [RevenueCat Tamor](https://app.revenuecat.com/projects/dff763eb/apps/app45c907c83a)：Project dff763eb、App app45c907c83a。同じAppleチームの既存購入キー／App Store Connect APIキーの利用をユーザーが明示承認した後に保存。AppleのTamor登録後、両キーがValid credentialsであることを確認。
- Apple商品を取り込み（prodfe1cbc3f2d）、world1_full_depth（entl438f1330b8）へ関連付け。
- default Offering（ofrng483bd6ceaf）を作成。LifetimeパッケージでTamorのApple商品を割り当て。既定Offeringになっていることを画面確認。
- 「はたらきろく」の商品・価格・Entitlement・Offeringは変更していない。秘密鍵ファイルの新規アップロードもしていない。

## 検証

- Coreスクリプト：4,341＋508＝4,849チェック成功。
- Xcodeセッション／保存等：37テスト成功。
- iPhone 17 Pro：既存日本語UI 5テスト成功、英語UI 3テスト成功（初回の自動画面消失によるテスト競合を修正後）。
- 購入画面のスクロール修正後、iPhone 17 Proの英語購入・設定テスト再成功。見出しが折り返されることを目視確認。
- iPad盤面修正後の最終Release Simulatorビルド成功。Info.plistの1.0／5、Tamor公開キー、en.lproj／ja.lprojを確認。
- iPhone 12 mini：英語UI 3テスト成功。結果／宝石箱／Crusherは初回成功、購入・設定は画面スクロールを考慮したテスト修正後に成功。購入画面の折り返しを目視確認。
- iPad Pro 13-inch（M5）：英語UI 3テスト成功。購入・設定とCrusher結果は成功。報酬・宝石箱で盤面が480×818ptになり、アクセシビリティのセル位置とタップ判定がずれる不具合を検出し、正方形に修正。最終コードで盤面の縦横寸法チェック、16セルのタップ、報酬保存、宝石箱への反映を含むテストが再成功（45.891秒、失敗0）。
- 日英String Catalog：182キーすべてにja/enあり。Release起動後のホームに開発用ボタンが出ないことを目視確認。
- 確認済み画像：`docs/screenshots/release-1.0/`。UIテストの購入画面は通信無効の検証用で、ストア掲載用素材ではない。
- iPad最終回帰テスト：`/private/tmp/tamor-release-resume/ipad-board-regression.xcresult`。Releaseビルドログ：`/private/tmp/tamor-release-resume/build-release-ipad-fixed.log`。`git diff --check`も成功。
- テスト出力：/private/tmp/tamor-release-resume/。テストデータは実購入確認ではない。

## 公開前に残る作業

1. SandboxまたはTestFlightで購入・復元・キャンセル・オフライン・コード引換を検証。UIテストの課金無効構成では代替できない。
2. App Storeのアプリ配信地域と無料価格、日英メタデータ、年齢制限、プライバシー回答、審査連絡先、スクリーンショット、初回IAP添付を完成させる。商品側の配信地域は設定済み、アプリ側とは別。
3. プライバシーポリシーの公開URL・運営者連絡先を確定し、アプリ内リンクを追加。Claudeの日英草稿と素材権利一覧はdocs/release/claude/。
4. アイコンは1024×1024だがアルファチャンネルあり（sipsで確認）。入稿用の不透明画像への変換が必要。SDKライセンス表示、素材の生成サービス・利用条件も確認する。
5. 署名済み実機Release／アーカイブ／TestFlight、持続性能、実機VoiceOver、審査・公開、Shipatonの素材・応募は未完了。

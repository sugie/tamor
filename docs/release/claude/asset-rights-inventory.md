# Tamor 1.0 素材権利一覧 / Asset Rights Inventory(草稿 / DRAFT)

> 2026-09-21、Claude作成。**権利の保証書ではありません。** リポジトリを調べて分かった事実と、ユーザー申告、未確認事項を分けて記載します。「確認済み」と書いていない項目は確認されていません。
> Prepared by Claude on 2026-09-21. **This is not a warranty of rights.** It separates what the repository shows, what the owner has stated, and what is unverified.

## 1. 調査方法 / Method

- リポジトリ内の画像・音声・フォント・3Dモデル等のファイルを検索(`docs/screenshots` を除く)。見つかったバンドル素材は `Assets.xcassets/AppIcon.appiconset/AppIcon.png` の1点のみ。音声ファイル、カスタムフォント、テクスチャ画像、3Dモデルファイルは**リポジトリ内に見つかりませんでした**。
- 宝石・ガラス・亀裂・破片はコード(Swift/Metal)で手続き的に生成されています(`Sources/Rendering/JewelGeometry.swift`、`Sources/Features/Glass/*`)。
- The only bundled media file found is the app icon. No audio, custom fonts, textures or model files were found. Gems, glass, cracks and shards are generated procedurally in Swift/Metal code.

## 2. 一覧 / Inventory

| # | 素材 / Asset | 所在 / Location | 出所(判明分) / Origin (as far as known) | 状態 / Status | 確認事項 / To confirm |
| --- | --- | --- | --- | --- | --- |
| 1 | アプリアイコン(1024×1024、濃紺背景に金色の二重円と4つの菱形の宝石) / App icon | `Assets.xcassets/AppIcon.appiconset/AppIcon.png` | Git 履歴では 2026-09-20 のコミット c8e0527 で追加。作成手段はリポジトリから判別不能。**ユーザー申告: AI生成の一般的な素材** | **未確認 / Unverified** | 生成サービス名とプラン、生成日、当時の利用規約(商用利用可否・出力の権利帰属・表示義務)、プロンプト/制作履歴の保存、人手による加工の有無。既存のアプリ・ブランドのアイコンや商標との類似調査。 |
| 2 | 宝石のカット形状(ブリリアンカット風の多面体) / Gem cut geometry | `Sources/Rendering/JewelGeometry.swift`(コード生成) | コードによる手続き生成。ブリリアンカットは一般的な宝石のカット様式。**ユーザー申告: AI生成の一般的なブリリアンカット等** | **未確認 / Unverified** | コード自体の作成経緯(AIコーディング支援の利用有無・その規約)。特定ブランドの登録意匠・特許カット(固有名称を持つ独自カット)を模していないこと。 |
| 3 | 宝石の色・光学パラメータ(屈折率、RGB吸収) / Optical parameters | `Sources/Rendering/*`, `JewelCatalog.swift` | README に「RGB吸収は美術用近似」と記載。屈折率等は一般的な物性値 | 事実情報のため権利上の懸念は低いと思われるが未確認 / Likely low risk, unverified | 数値の出典を記録するか検討。 |
| 4 | ガラス・亀裂・破片の描画とアルゴリズム / Glass, crack and shard rendering | `Sources/Features/Glass/*` | `docs/PROVENANCE.md`: 実験リポジトリ break-grass のコミット d703b58 から取り込み | **未確認 / Unverified** | break-grass の全コードが本人著作であること、第三者コード・論文実装の移植やライセンス付きスニペットの有無。 |
| 5 | Metal シェーダ / Shaders | `*.metal` | リポジトリ内の自作コードとみられる | **未確認 / Unverified** | 第三者シェーダ(Shadertoy 等)由来の部分の有無とライセンス。 |
| 6 | UI アイコン(SF Symbols: sparkles, water.waves, chevron, xmark, pause, lock, shippingbox, crown.fill 等) | SwiftUI `Image(systemName:)` | Apple 提供のシステムシンボル | Apple の利用条件に従う必要あり / Subject to Apple's terms | アプリ内 UI での利用を想定した素材。アプリアイコン・ロゴ・商標的な用途への使用は制限されていると Claude は理解していますが、**今回の調査では該当する公式の条文を取得できず未確認**です(https://developer.apple.com/sf-symbols/ には記載が見当たらず)。SF Symbols アプリ同梱のライセンスと Human Interface Guidelines を確認するまで、アイコンやストア用画像へ転用しないでください。 |
| 7 | フォント / Fonts | システムフォントのみ(`.system`, `.serif` design) | Apple システムフォント | アプリ内表示は問題になりにくい / Low risk in-app | ストア用スクリーンショットに文字を後から合成する場合、使用フォントのライセンスを別途確認(San Francisco フォントには Apple の利用条件があります。**条文は今回未確認**)。 |
| 8 | 音声 / Audio | なし / None found | — | — | 1.0 に音を追加する場合は別途記録。 |
| 9 | サードパーティコード: RevenueCat purchases-ios 5.90.2 | Swift Package(`Package.resolved`) | RevenueCat, Inc. | MIT License(Copyright (c) 2024 RevenueCat, Inc.。タグ 5.90.2 の LICENSE を取得して確認) / MIT, verified at tag 5.90.2 | MIT は著作権表示と許諾文の同梱を条件とするため、アプリ内(設定画面等)または付属文書へのライセンス表記の追加要否を判断。1.0 の UI には現在ライセンス表示画面がありません。 |
| 10 | 名称「Tamor」 / The name "Tamor" | 表示名・ストア名 | ユーザー決定(R06) | **未確認 / Unverified** | 日本・米国での商標調査(J-PlatPat、USPTO)、App Store 上の同名/類似名アプリの有無。ガイドライン 4.1 (模倣)、2.3.7(メタデータ)の観点。 |
| 11 | ゲーム名「Glass Break」「Glass Trace」「クルクルワールド / Kurukuru World」「Crusher Room」 | UI 文言 | 自作の名称とみられる | **未確認 / Unverified** | 既存ゲーム・商標との衝突調査。 |
| 12 | ストア用スクリーンショット・プレビュー(今後作成) | 未作成 / Not yet created | — | — | 実機/シミュレーターの実画面から作成(ガイドライン 2.3.3)。価格を画像に入れない(2.3.7)。他社端末の画像や無関係な情報を入れない(2.3.10)。 |
| 13 | 旧コレクション用の宝石(ブラックオニキス、エメラルド) | コード内の定義のみ | 同 #2 | 同 #2 | 1.0 のアイコン(#1)は緑・紫の宝石を含み、現行 World 1 の4種(ダイヤモンド・サファイア・黒曜石・ルビー)と一致しません。権利問題ではありませんが、掲載情報の正確性の観点で差し替え要否を判断してください。 |

## 3. 技術面の気付き(権利とは別) / Technical note

- `AppIcon.png` は PNG カラータイプ 6(RGBA、アルファチャンネルあり)です。実際に透明な画素があるかは未確認ですが、App Store 用アイコンはアルファ/透明を含めない必要があるため、書き出し直しを推奨します。
- `AppIcon.png` is RGBA (has an alpha channel). App Store icons must not contain transparency; consider re-exporting without alpha.

## 4. AI生成素材についての注意 / Notes on AI-generated material

- 「AIで生成した」という事実だけでは、(a) 第三者の著作物・商標・意匠に類似していないこと、(b) 生成サービスの規約が商用利用と再配布を認めていること、(c) 利用者が出力について主張できる権利の範囲、のいずれも保証されません。国や時期によって、AI生成物に著作権が発生するかどうかの扱いも異なります。
- App Store Review Guidelines には AI 生成素材そのものを対象とした条項は見当たりませんでした(2026-09-21 時点の取得範囲。5.2 節は今回の調査で本文を取得できず**未確認**)。一般則として、権利を持たない第三者の素材を含めないことが求められます。
- "AI-generated" alone does not establish non-infringement, commercial-use permission under the generator's terms, or the scope of rights you can claim. Section 5.2 of the Review Guidelines could not be retrieved in this review and is **unverified**.

## 5. ユーザーに確認したい項目(回答用) / Questions for the owner

1. アイコン(#1)の生成に使ったサービス名・プラン・生成日は?
2. そのサービスの当時の利用規約で、商用利用・アプリアイコンとしての配布は認められていますか?(規約の URL と取得日を記録)
3. プロンプト、生成結果の原本、加工履歴は残っていますか?
4. 宝石形状やシェーダのコードに、第三者のコード・チュートリアル・論文実装を写した部分はありますか?
5. break-grass リポジトリのコードはすべてご本人(および利用規約上問題のない AI 支援)によるものですか?
6. 「Tamor」の商標調査は実施済みですか?

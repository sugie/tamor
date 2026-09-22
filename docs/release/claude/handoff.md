# 英語UI対応 引き継ぎメモ(Claude → Codex / ユーザー)

2026-09-21、Claude作成。**ビルド・テストは一切実行できていません(未検証)。** Claude の作業環境は Mac 上の Linux VM で、`xcodebuild`・Simulator・`swiftc` がなく、Swift ツールチェーンの取得もネットワーク制限で不可でした。

## 1. 方針

- String Catalog `Sources/Localizable.xcstrings` を新規追加。**キー=既存の日本語文字列**、各キーに `ja`(キーと同一)と `en` を明示。`sourceLanguage` は `en`(pbxproj の `developmentRegion = en` に合わせた。日英以外の言語の端末では英語にフォールバックする)。
- SwiftUI のリテラル(`Text("…")`、`Button("…")`、`Toggle`、`Section`、`Picker`、`Label`、`navigationTitle`、`confirmationDialog`、`ProgressView`、`ContentUnavailableView`、補間つき `Text("深度 \(n)")` → キー `深度 %lld`)は**コード変更なしで**カタログから引かれます。6ファイル内のリテラルもカタログに登録済みです。
- `String` として組み立てられる動的文字列(エラー、結果、購入メッセージ、宝石名、ゲーム名、評価、アクセシビリティ)は、表示直前に `L(_:)`(`Bundle.main.localizedString` の薄いラッパー)で引きます。キーが無い/カタログ未登録なら**日本語がそのまま表示**されるので、日本語UIは現状と同一です。
- **Core は無変更。** 保存値(`GemGrade` の rawValue「失敗」、称号「一閃の破砕」等、gemID、resultID)、商品ID、Entitlement、成績・報酬・判定ロジック、`accessibilityIdentifier`、Crusher の `accessibilityValue`(テスト用の状態文字列)は変更していません。翻訳は表示側だけです。
- 数値・カラット: `GemScale.label`(`%.2f ct`)と秒数表示は Core/既存書式のまま(小数点は常に「.」)。日英とも「.」のため表示は正しいですが、英語+欧州地域設定でも「.」固定です。日時は既存の `Text(date, style:.date)` がロケールに従います。

## 2. Claude が変更・追加したファイル

| ファイル | 内容 |
| --- | --- |
| `Sources/Localizable.xcstrings`(新規、181キー) | 日英カタログ。`%lld 個` のみ英語の単複変化つき。**まだ Xcode プロジェクトに未登録**(下記 3-1) |
| `Sources/App/MiniGameScreen.swift` | 宝石名・ゲーム名・評価・失敗理由・保存メッセージ・カウントダウン説明を `L()` 経由に。ファイル末尾付近に `func L(_:)` を定義(新規 Swift ファイルにすると pbxproj 登録までビルドが壊れるため、登録済みファイル内に置いた。後で `Localization.swift` 等へ移して構いません) |
| `Sources/App/CrusherScreen.swift` | 残り秒数、TIME UP 行の評価、報酬メッセージ(`String(format:L("黒曜石 %@ を保存しました"),…)`)、中断記録エラー、`accessibilityLabel`「ガラス」 |
| `Sources/Rendering/JewelMetalView.swift` | リング上の台座ラベル、アクセシビリティのラベル/ヒント |
| `Sources/Rendering/MiniGameMetalView.swift` | 「緑の点/赤い点」、セルのラベル(宝石名)と値(時計回り/反時計回り) |
| `Sources/Rendering/JewelRenderer.swift` | `rayStatus` と描画エラー文言(表示側が 6 ファイル内の `Text(state.rayStatus)` のため、設定元でローカライズ) |
| `Sources/Features/Glass/GlassStudyRenderer.swift` | `accessibilityLabel` 1行 |
| `Tests/UI/JewelRingUITests.swift` | 既存テストの起動引数に `-AppleLanguages (ja) -AppleLocale ja_JP` を追加(日本語文言を検証しているため、Simulator の言語に依存しないよう固定)。英語起動の `TamorEnglishUITests` を同ファイル末尾に追加(新規ファイルにしなかった理由は上と同じ)。カタログが未登録の間は `XCTSkip` します |
| `docs/release/claude/*` | 文書一式と本メモ、`english-ui-claude.patch`(Claude の変更だけを抜き出した差分。作業前のコピーとの diff) |

指定の6ファイル(`JewelSceneState.swift`、`JewelRingApp.swift`、`PurchaseStore.swift`、`project.yml`、`project.pbxproj`、`Tamor.entitlements`)、`docs/app-store-shipaton-execution-plan.html`、`docs/release-decisions-2026-09-21.md` は**編集していません**(読み取りのみ)。

## 3. Codex 側でお願いしたい作業

### 3-1. プロジェクト登録
- `Sources/Localizable.xcstrings` を Tamor ターゲットの Resources に追加(`project.yml` は `Sources` を丸ごと含むので `xcodegen generate` で拾われるはずです。手動なら PBXFileReference `lastKnownFileType = text.json.xcstrings`、PBXBuildFile、Resources フェーズ、Sources グループに追加)。
- `knownRegions` に `ja` を追加(`project.yml` なら `options: knownRegions` 相当、または Xcode の Project > Info > Localizations で Japanese を追加)。`developmentRegion` は `en` のままを想定。`ja` に変える場合はカタログの `sourceLanguage` も合わせて検討してください。
- ビルド後、アプリバンドルに `en.lproj` と `ja.lproj`(`Localizable.strings` / `.stringsdict`)ができていることを確認。
- Xcode でカタログを開くと、抽出状態の再計算で「Stale」表示になるキーが出る可能性があります(`L()` 経由の実行時キーは自動抽出されないため、全キーを `extractionState: manual` にしてあります)。削除しないでください。

### 3-2. 6ファイル内の動的文字列(カタログには登録済み。コード側の置換だけ必要)

`JewelRingApp.swift`
- `Text(state.kind.name)` → `Text(L(state.kind.name))`。宝石箱の `Text(kind.name)`、Picker の `Text($0.name)`、DEBUG の `Toggle(j.name,…)` → `L(...)`。
- `Text(state.kind.composition)` → `Text(L(state.kind.composition))`(「火山ガラス」)。
- `goldButton("\(state.kind.game.title)をプレイ",…)` → `goldButton(String(format:L("%@をプレイ"),L(state.kind.game.title)),…)`
- `goldButton("宝石と深度を選ぶ",…)` → `goldButton(L("宝石と深度を選ぶ"),…)`
- `goldButton("宝石箱 · \(state.collectionCount) 個",…)` → `goldButton(String(format:L("宝石箱 · %lld 個"),state.collectionCount),…)`
- `Section(jewel.name+" · "+jewel.game.title)` → `Section(L(jewel.name)+" · "+L(jewel.game.title))`
- `Text(depth==6 ? "最大20.00ct":GemScale.label(…))` → `Text(depth==6 ? L("最大20.00ct"):GemScale.label(…))`(片方が String のため全体が String になりローカライズされない)
- `?? "開発プレビュー"` → `?? L("開発プレビュー")`
- `Text($0.title)`(品質 Picker) → `Text(L($0.title))`
- `Text("合計 "+…)` / `Text("最大 "+…)` → `Text(L("合計 ")+…)` / `Text(L("最大 ")+…)`
- `if let error=state.error {Text(error)…}`、`Text(message)`(saveMessage, purchases.message) → `L(...)` で包むと、完全一致するメッセージは英訳されます。
- iCloud 関連の文言(「iCloudと宝石の復元」ほか)は R04 で除去予定と理解し、**英訳を用意していません**。残す文言があれば連絡ください。
- 「購入権利と宝石は別々に復元されます。」は端末内保存のみの 1.0 では誤解を招くため、差し替え案をカタログに登録済み: 「購入の復元で戻るのは解放の権利だけです。宝石はこの端末内に保存され、購入の復元の対象ではありません。」
- プライバシーポリシーへのリンクが設定画面にありません(ガイドライン 5.1.1(i))。URL 確定後に追加が必要です。追加する文言のキーは未登録です。

`PurchaseStore.swift`
- `message="…"` の各行 → `message=L("…")`。連結している3箇所は `L("購入情報を更新できません：")+error.localizedDescription` の形(キーは「：」まで)。
- `goldButton(store.price.map{"\($0)で解放"} ?? "商品を確認中",…)` → `goldButton(store.price.map{String(format:L("%@で解放"),$0)} ?? L("商品を確認中"),…)`
- 「購入の復元はRevenueCat、宝石の復元は設定のiCloud同期から行えます。」の差し替え案(登録済み): 「「購入を復元する」で戻るのは購入した解放の権利だけです。宝石はこの端末内にのみ保存されます。」

`JewelSceneState.swift`
- `rayStatus="端末のMetal機能を確認中"`、`saveMessage="バックアップから復元しました。"`、取り込み関連の3メッセージ → `L("…")`。
- `"保存できませんでした：\(error.localizedDescription)"` → `L("保存できませんでした：")+L(error.localizedDescription)`、`"報酬を保存できません。再試行してください："+…` → `L("報酬を保存できません。再試行してください：")+L(error.localizedDescription)`、`"取り込めませんでした："+…` も同様(`SaveFailure` の2文言はカタログ登録済みなので `L()` で英訳されます)。
- `actualQuality="標準"` は表示箇所が見当たらず未対応。
- `decoratedSlots` 内の「一閃の破砕」「傷なき軌跡」は保存値との照合なので**変更しないでください**。

### 3-3. 検証(すべて未実施)
1. `bash scripts/test-core.sh`(Core 無変更のため影響なしの想定)。
2. `xcodebuild … test`。既存の日本語 UI テスト5件が `-AppleLanguages (ja)` 固定で従来どおり通ること。
3. `TamorEnglishUITests` 3件。6ファイル側の置換が済むまでは、購入ステータス文言などが日本語のまま表示されます(テストは literal 由来の文言だけを検証するようにしてあります)。
4. 英語起動で購入画面・結果・設定のスクリーンショットを iPhone 12 mini 相当(幅375pt。現行 Simulator に 12 mini が無ければ iPhone 13 mini / SE 等)と iPad で目視確認。特に長くなる英文: 購入画面の3行説明、Crusher の説明行(`.footnote`)、`goldButton` の「Unlock World 1 Depths 4–6」、リングの台座ラベル(幅110pt・2行・9pt: "Kurukuru World" / "Crusher Room")、ミニゲームのヘッダ統計行(11pt 等幅: "Weak point 0 HIT" 等)。
5. VoiceOver の英語読み上げ(リングの宝石、ミニゲームの的、クルクルのセル値)。

## 4. Claude が実行できた検査

- カタログの JSON 妥当性、全キーで ja/en の書式指定子(`%lld`/`%@`/`%.1f` 等)の種類と順序が一致することをスクリプトで検証。
- `Sources/**/*.swift` の日本語リテラルをスクリプトで抽出し、カタログ未登録のものを列挙。残りは (a) iCloud 関連(意図的に未訳)、(b) 保存値の称号、(c) 画面に出ない旧機能の文字列(`ObservationLevel`、`subtitle`、亀裂密度、`backend` 等)、(d) `GlassBreakGeometry` の内部失敗理由(捕捉されて簡略破片に切り替わり、表示されない)、(e) 補間つきの診断文 1 件(`\(name)が見つかりません。`)。
- 変更した Swift ファイルの括弧・引用符の増減が釣り合っていること、置換が各1箇所だけに当たったことを確認。**コンパイル確認ではありません。**
- 掲載文の文字数検査(`store-listing.md`)。

## 5. 作業中の出来事

- 最初の `git status` が `.git/index.lock`(0バイト)を残しました(この環境は削除不可のため git が自分のロックを消せなかった)。`.git/claude-stale-index.lock.removeme` にリネームして解消済みです。中身は空で、削除して構いません。以降は `GIT_OPTIONAL_LOCKS=0` で読み取りのみ行っています。commit / add / reset / stash / checkout は行っていません。

---

## 6. 追記(第2回、2026-09-21): 3ファイルの英語化と三項演算子の修正

Codex の依頼により、CloudKit 除去・`customerInfoStream` 監視・`offerings.current` 参照などを含む**最新の内容を読み直したうえで**、表示文字列だけを変更しました。上の 3-2 節の置換は本追記で実施済みです(3-1 のプロジェクト登録は引き続き Codex 専任で、Claude は `project.yml` / `project.pbxproj` / `Tamor.entitlements` を編集していません)。**ビルド・テストは今回も未実行(未検証)です。**

### 変更ファイル(第2回分の差分は `english-ui-claude-round2.patch`)

| ファイル | 内容 |
| --- | --- |
| `Sources/App/PurchaseStore.swift` | `message` の全設定箇所を `L()` 経由に(連結3箇所は `L("…：")+error.localizedDescription`)。購入ボタンを `String(format:L("%@で解放"),price)` / `L("商品を確認中")` に。`Text(L(message))`。`productID`・`entitlementID`・`apply(_:)`・`observeUpdates()`・購入/復元の流れは無変更 |
| `Sources/App/JewelSceneState.swift` | `rayStatus` 初期値、`saveMessage` の7箇所(読込失敗時の `error.localizedDescription` も `L()` を通し、`SaveFailure` の2文言が英訳されるように)。`decoratedSlots` の称号比較(「一閃の破砕」「傷なき軌跡」「・」)、UserDefaults キー、保存処理は無変更 |
| `Sources/App/JewelRingApp.swift` | 宝石名・組成・ゲーム名・品質名・`rayStatus`・エラー/保存/購入メッセージの表示、`goldButton` 3箇所、深度ピッカーの Section 見出しと「最大20.00ct」、宝石箱の「合計 」「最大 」、DEBUG の Toggle/Button。リテラルのままで自動ローカライズされる `Text("…")` 等は触っていません |
| `Sources/App/MiniGameScreen.swift`、`Sources/App/CrusherScreen.swift` | 下記の三項演算子の修正 |
| `Sources/Localizable.xcstrings` | 182キー。Codex が追加した端末保存の説明4文と「宝石の保存と復元」「保存データを取り込む」を日英で追加。使われなくなった4キー(旧「購入権利と宝石は別々に…」、Claude の差し替え案2件、「旧保存データを取り込む」)を削除 |
| `Tests/UI/JewelRingUITests.swift` | 英語テストの `XCTSkip` を廃止し、カタログ未登録なら**失敗**するように変更。画面上の全ラベルに仮名・漢字が残っていないことを検査する `assertNoJapanese(_:)` を追加し、ホーム・購入画面・設定(上下)・深度ピッカー・結果・宝石箱・Crusher 結果で呼び出し。設定の `save.localNotice` が英語であることも検証 |

### 三項演算子について(ご指摘の件)

`Text(cond ? "一時停止" : "\(n)")` のように両辺がリテラルの場合、Claude の理解では `LocalizedStringKey` 側の初期化子が選ばれますが(`StringProtocol` 版は不利な候補として宣言されているため)、**コンパイラで確認できない**ので、型推論に依存しない書き方に統一しました。いずれも結果は明示的に `String` です。

- 一時停止/カウントダウン(MiniGame・Crusher): `Text(phase == .paused ? L("一時停止"):"\(countdown)")`
- `reward.title`: `Text(session.preview ? L("練習クリア"):String(format:L("%@を獲得！"),L(session.kind.name)))`
- `mini.count`: `String(format:L("ヒビ %lld / 3"),cracks)` と素の `"\(hits) / \(required) HIT"`
- プレイ中の説明、`reward.saved`、`accessibilityValue`(破砕完了/ガラスあり): `L(三項)` で包む
- Crusher の `TIME UP` 行: `String(format:L("TIME UP · %lld 枚 · %@"),plates,L(grade.rawValue))`
- JewelRingApp の `Text(world==1 ? …)`、`Label(解放済み ? …)`、DEBUG `Button(… ? …)` も同様に `L()` で明示

日本語 UI テストが検証している文言(「緑の点を追いかけてください。」「収集 1 / 4 種類」「1 個」「まだ宝石がありません」「閉じる」、報酬の「保存しました」)は、日本語起動では従来と同じ文字列になります。

### 実行した検査(第2回)

- 置換はすべて「ちょうど1箇所に一致」を条件に適用。括弧・引用符の増減の釣り合いを確認。
- 差分に `productID` / `entitlementID` / 称号文字列の行が含まれないことを確認。
- `Sources/**/*.swift` の日本語リテラルとカタログの突き合わせ: App 側の未登録は 0 件。残りは Core の保存値(称号)、ビルドから除外された `CollectionCloudStore.swift`、画面に出ない文字列(3章 4節の (c)〜(e))。逆方向(カタログにあってソースに無いキー)も 0 件。
- ja/en の書式指定子の一致を再検証。

### 未検証・注意点

1. コンパイル、既存の日本語 UI テスト、英語 UI テスト、iPhone 12 mini 相当と iPad の英語レイアウト、VoiceOver。すべて Mac 側でお願いします。
2. `assertNoJapanese` は見えている要素の `label`/`value` を総当たりするため、要素数の多い画面ではやや時間がかかります。RevenueCat のエラー文(`error.localizedDescription`)は SDK/OS 側の言語に従うので、英語起動では英語になる想定ですが未確認です。
3. 英語テストの `purchase.buy` 無効の検証は、既存の日本語テストと同じく「API キー未設定の UI テスト構成」を前提にしています。キーを設定した構成で UI テストを回す場合は両方とも見直しが必要です。
4. `String(format:)` は `Locale` を渡していないため、数値は常に「.」小数点・桁区切りなしです(日英とも表示上は正しい)。
5. 設定画面のプライバシーポリシーへのリンクは未追加のままです(URL 未確定)。追加時は文言をカタログへ登録してください。
6. 文書側: `privacy-policy.*.md` と `store-listing.md` は「保存データを書き出す」機能が 1.0 に残る前提の `【要確認】` を含みます。今回の設定画面に書き出し/取り込みが残っていることは確認しましたが、文書の空欄は人間の確定待ちのため埋めていません。

---

## 7. 追記（2026-09-22、Codex）：案 B の実装・実機検証

`device-support-plan.html` を読み、ユーザー指定の案 B を実装。案 C（`iphone-performance-gaming-tier`）は追加していません。追加指示でローカルの実機ビルド・インストール・テストまで許可されました。アーカイブ、IPA書き出し、アップロード、審査提出、ストア設定変更は実施していません。

### 今回の変更

| ファイル | 内容 |
| --- | --- |
| `project.yml` | 最低 iOS 26.0、iPhone 専用、iPad 向け画面方向設定削除、必要機能 `[arm64, metal]`。XcodeGen のターゲット既定値 `1,2` がプロジェクト設定を上書きするため、アプリ・単体テスト・UIテストの各ターゲットにも `TARGETED_DEVICE_FAMILY: '1'` を明示。既存の署名チーム設定を再生成後も保持するため、同じ DEVELOPMENT_TEAM を生成元にも記載 |
| `Tamor.xcodeproj/project.pbxproj` | XcodeGen で再生成。プロジェクトと全ターゲットの Debug/Release で family=1。作業前から存在したアプリ・Privacy Manifest のファイル型メタデータ変更と署名チームを保持 |
| `Config/Info.plist` | XcodeGen が arm64 / metal を生成したことを確認 |
| `Sources/Rendering/MiniGameMetalView.swift` | Metal 初期化失敗を保存データのエラーから Metal 用 NSError に変更。2箇所の深度状態と3個のバッファ確保を guard/throw に変更 |
| `Sources/Features/Glass/GlassFragmentEngine.swift` | シェーダ関数取得の強制アンラップを guard/throw に変更。既存の失敗通知経路を利用 |
| `Sources/Localizable.xcstrings` | 初期化・深度設定・GPUメモリ・破片シェーダの案内4件を日英追加。作業前の全キーと値を保持していることを JSON 比較で確認 |
| `Tests/UI/JewelRingUITests.swift` | 既存UIテストが直接カバーしていなかったダイヤモンドの描画準備完了・Metalエラーなしを確認するテスト1件を追加 |
| `docs/release/claude/store-listing.md` | 日英で iPhone / iOS 26以上、iPad互換モードの動作保証なし、iPad画像不要に更新 |
| `docs/release/claude/app-review-notes.md` | 同じ対応範囲に更新。iPhone 17世代・iPadは未検証と記載 |
| `docs/release/testflight-info.md` | 次回ビルド用の文案として対応範囲と検証端末を更新。既存アップロード済み 1.0(5) の要件が変わったという意味ではないことを明記 |
| `docs/release/claude/handoff.md` | 本追記 |

保存ID、商品ID、Entitlement、ゲームロジックは変更していません。バージョンは従来の 1.0(5) を維持（今回のビルドはローカル検証用）。`Sources` の `#available` / `@available` / iOS 17 向け記述を検索し、今回削除する分岐はありませんでした。Metal のソフトウェア経路は削除していません。未コミット変更の reset / clean / stash / commit / ブランチ切替は実施していません。

### 完了した検査

- iPhone 12 mini は [Apple の iOS 26 対応一覧](https://support.apple.com/guide/iphone/iphe3fa5df43/26/ios/26)に記載。USB接続した実機は **iOS 26.6.1 (23G83)**、Developer Mode有効で、ユーザーからも同じOSとロック解除を確認。OS更新は不要でした。
- `bash scripts/test-core.sh` 成功：4,341 checks と 508 assertions、合計 **4,849**。
- XcodeGen生成、plist構文検査、`git diff --check`、既存翻訳キー/値の保持、案C未導入、強制アンラップ除去の静的検査に成功。
- **生成された実機用 Tamor.app** の Info.plist を確認：`MinimumOSVersion=26.0`、`UIDeviceFamily=[1]`、`UIRequiredDeviceCapabilities=[arm64, metal]`、iPad画面方向キーなし。アプリ内の日英 Localizable.strings に新しいMetal案内が含まれることも確認。
- 実機向け Debug ビルド・署名・インストール成功。iPhone 12 mini上の既存単体テスト **37件成功**。
- 最初のビルドでターゲット既定値により生成アプリが `[1,2]` となることを検出し、自分が開始したビルドだけを中断。各ターゲットに family=1 を明示し、再生成後のアプリでは `[1]` と確認しました。

### メモリーと実行条件

既存の `~/Library/Developer/Xcode/DerivedData/Tamor-bamxjxkpqeavuiekjjsgenvblcdy` と既存パッケージキャッシュを利用。DerivedData削除、clean、インデックス再構築操作はしていません。`-jobs 1 -parallel-testing-enabled NO -maximum-concurrent-test-device-destinations 1 COMPILER_INDEX_STORE_ENABLE=NO` を指定し、実機のUDIDを destination に指定しました。Simulatorは起動・操作・テストしていません（作業開始時点で別のSimulatorプロセスは存在していました）。

3秒ごとにXcode・ビルド/Swift/Metal関連プロセスのRSS合計とシステムスワップを記録。RSS合計8 GiB超またはスワップ2 GiB超で、この作業のビルドプロセス群のみ中断する監視を付けました。最初の実行で最大 **1,523.0 MiB**、設定修正後の実行で最大 **1,360.7 MiB**、スワップはともに **0 MiB**。これはサンプリングしたRSSであり、Activity Monitorの「メモリ」と同じ指標ではありません。前回の184GB問題の根本原因解消を示すものではありません。

ログと監視スクリプトは `build/device-support-20260922/`（Git対象外）、詳細テスト結果は `/tmp/tamor-device-support/device-tests-final.xcresult` に保存。

### UI検証の状態・未決事項

- UIテストの初回実行は Runner 初期化中に `Timed out while enabling automation mode` で停止。テスト結果全体は Failed、内訳は単体テスト37件成功・UI Runnerの開始エラー1件です。UIテストのアサーションが失敗したものではありません。
- **09:02 追記：実機側の暗証番号入力をユーザーが完了した後、`test-without-building -only-testing:TamorUITests` で再ビルドせず再実行。日本語6件・英語3件、合計9件すべて成功（約202秒、終了コード0）。** ダイヤモンド描画、サファイア獲得・再起動後の保存、ルビーのガイドと操作、黒曜石のプレイ・報酬、ホーム・宝石箱、購入画面・設定、英語文言を確認しました。これで今回の実機単体37件＋UI9件の計46件が成功です。
- iPhone 17世代、iPad互換モード、iOS 26.0ちょうどでの動作は未検証。iPhone専用設定はiPadへの互換インストールを禁止するものではなく、その動作を保証しません。
- 実購入・復元は未検証。既存UIテストは `--ui-test` で課金サービスを接続しない構成の画面検証で、決済成功の証拠にはなりません。
- nilを返すMetal機能を実機で故意に発生させる障害注入は未実施。日英案内のバンドルとguard/throw経路は確認済みです。
- 既存の `UIRequiresFullScreen` についてiOS 26での非推奨警告、および単体テスト起動中にSwiftUIのview更新中の状態発行に関する警告がありました。本作業でゲームロジック変更や無関係の整理はしていません。
- 今後アップロードする際はビルド番号を別途増やし、App Store Connect上で対応範囲を確認する必要があります。今回ストア側の変更はしていません。

### UIテスト再開後の記録（09:02）

- 認証待ちは、ユーザーがiPhone上で暗証番号を入力して解消しました。追加のコード変更・再ビルドはありません。
- 再実行の監視対象RSS最大値は **1,214.7 MiB**、システムスワップ **0 MiB**。しきい値による中断なし。
- ログ・メモリー計測・スクリーンショットを含む `.xcresult` を `build/device-support-20260922/device-ui-retry*` に保存（Git対象外、ローカルのみ）。
- テスト終了時に devicectl の診断収集だけがエラーになりましたが、UIテスト9件は全件成功で、xcodebuild は `TEST EXECUTE SUCCEEDED`・終了コード0です。診断収集エラーはUIテストの不合格と区別しています。
- 残る未検証事項は上記の通り：他機種・iPad、iOS 26.0ちょうど、実決済/復元、Metalの障害注入、長時間の負荷。アーカイブ・アップロード・公開操作はしていません。


## 8. 追記（2026-09-22 11:18、Codex）：iPad実機検証完了

iPad第8世代／iPadOS 26.7のiPhone互換モードで、UIテスト日本語6件・英語3件は再実行分を含めて全項目成功。9件実行は8件成功・1件失敗、テスト操作の修正後に残る深度2の1件が成功しました。テスト引数なしの通常起動も成功し、Xcodeの実機スクリーンショットでホームとMetal描画を確認しました。白画面は今回再現せず、以前の原因は未確定です。

詳細と証跡は[検証記録](../ipad-verification-2026-09-22.md)を参照。上記7節の「iPad未検証」は本追記で更新します。iPadの動作保証範囲、実購入・復元、長時間負荷についての制限は残ります。

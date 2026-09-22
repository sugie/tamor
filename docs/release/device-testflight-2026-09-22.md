# 実機更新とTestFlight準備（2026-09-22）

## コードと実機

- PR #1はマージ済み。`origin/main` の `33837635b8d9c9b3caa8924181239607d3f4db3a` から `codex/testflight-preparation` を作成。
- iPhone 12 mini（端末名i18m）のTamorを0.4.1／ビルド4から、1.0／ビルド5の署名付きRelease版へ上書きインストール。devicectlでインストール済みバージョンと起動成功を確認。
- 更新前の `Application Support/Tamor` を退避。更新後との比較で、schemaVersion 3、宝石12個、深度記録15件、journal 4件、旧inventory 2件が一致。初期化・アンインストールはしていない。
- セーブの退避先：`build/testflight-20260922/device-save-backup/`。Git対象外。第三者への配布物には含めない。

## TestFlight向けのビルド

- アイコンは1024×1024、アルファ値が全画素255であることを確認。RGBAからRGBへエンコードを変更し、復号後のRGBA画素が変換前と完全一致することを検証。見た目を変更せずアルファチャンネルを除去。
- アイコン修正後の署名付きReleaseアーカイブ成功。
- `app-store-connect`、自動署名、外部テスト可能（`testFlightInternalTestingOnly=false`）としてIPAの書き出し成功。
- IPA内のBundle ID `com.marcottlab.tamor`、1.0／5、プライバシーマニフェストを確認。アーカイブのTamor用公開SDKキーも確認。
- TestFlightアップロード：2026-09-22 06:16 JSTに成功。Xcodeは `Upload succeeded`、`Uploaded package is processing`、`EXPORT SUCCEEDED` を返した。Apple側の処理完了・外部テスト承認は未確認。
- アップロード時にApple側の予期しないエラーによる検証スキップ警告あり。アップロードは成功扱いだが、管理画面で処理結果を確認する必要がある。
- アーカイブ：`build/testflight-20260922/Tamor.xcarchive`
- IPA：`build/testflight-20260922/export/Tamor.ipa`
- エクスポート設定：`build/testflight-20260922/ExportOptions.plist`
- これらのビルド成果物はGit対象外。一般向けApp Store審査提出・公開はしていない。

## 文書用プロンプト

- [Claudeへ渡すプロンプト](../prompts/claude-tamor-support-legal-site.md)を作成。プロンプトのファイル保存のみで、Claudeへの送信やサイトの変更・デプロイはしていない。
- FAQ・利用規約・プライバシーポリシーの日英6文書と、既存Laravelサイトへの掲載実装・検証・公開手順を依頼する内容。
- `https://marcottlab.com/` とBitbucketの `fyhealth/marcottlab-site` をブラウザで確認。会社情報の正本、既存Blade・日英導線・問い合わせを再利用する方針。
- `/apps/tamor/` と `/en/apps/tamor/` 以下は提案URLであり、まだ公開されたURLではない。
- サイトは「MarcottLab株式会社」と「2026年設立予定」を併記していたため、契約主体・法人情報はClaudeに推測させず確認事項としている。
- [TestFlight入力用文案](testflight-info.md)も作成。説明・テスト項目・ベータ審査メモは文案で、管理画面へ保存済みではない。

## 外部テスターへ渡すまでに必要な作業

1. App Store Connectに再ログイン（ブラウザの認証期限切れを確認済み）。
2. ビルドのアップロード結果とApple側の処理完了を確認し、暗号化／輸出コンプライアンスの回答を完了。
3. ベータのフィードバックメールと審査連絡先を確定。必要なプライバシーURL等を公開実態に合わせて設定。
4. 招待リンクかメール招待かを確定し、外部テスターグループへビルドを追加。
5. 初回の外部ベータ審査へ提出し、承認後に招待を有効化。

初回外部配布に審査が必要であることは[Appleの案内](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers)で確認。ビルドのアップロード成功だけで、外部の人がプレイできる状態とは扱わない。

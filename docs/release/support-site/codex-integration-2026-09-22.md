# Mac側の取り込み・アプリ接続（2026-09-22）

## Git取り込み

- 対象: `sugie/tamor` / `codex/testflight-preparation`
- `315672b` → `2308cd6` を `git pull --ff-only origin codex/testflight-preparation` で取り込み済み。
- 手元の23ファイル（未コミット・未追跡を含む）を `/tmp/tamor-before-pull-20260922-151933/` に原本・パッチ・SHA-256付き一覧として保存。
- 重複する `Config/Info.plist` と `project.yml` は共通祖先・手元・リモートの3者マージで統合。その他21ファイルはバックアップとのハッシュ一致を確認。
- 単体宝石の往復アニメーション、スポットライト、傾き入力、日本語/英語対応、iPhone専用設定を保持。

## 引き継ぎ後に進めた作業

- C8: 設定画面に「プライバシーポリシー」「利用規約」「サポート・お問い合わせ」を追加。アプリが日本語なら日本語ページ、それ以外は英語ページを開く。
- URLは引き継ぎで確定した `https://marcottlab.com/apps/tamor/` と `/en/apps/tamor/` 配下。
- C6: `ITSAppUsesNonExemptEncryption=false` を既存のモーション用途説明・端末要件と統合。
- `xcodegen generate --spec project.yml` を実行。生成で変わった既存のファイル種別宣言2箇所を保持し、`.xcodeproj` の不要な差分を残していない。
- Debug成果物で輸出フラグfalse、iPhone専用、最低iOS26.0、モーション用途説明、PrivacyInfo.xcprivacy、日英のリンク文言を確認。
- これらの変更は、ユーザー指示による2026-09-22のローカルチェックポイントコミットに含める。push・App Store Connectへの送信は未実施。アップロード済みbuild 5は更新されない。

## サイト実測と残る作業

2026-09-22、日英の規約・プライバシー・案内トップ計6URLをHTTPSで読み取り確認し、すべてHTTP 200。

- 現在は「公開前の草案です」「Draft — not published yet.」の表示が残る。
- プライバシーポリシーには、今回追加した端末の傾き利用の説明がまだない。追記する日本語/英語の文章は [機能メモ](../ring-inspection-motion-2026-09-22.md) を参照。
- 個人名義へのサイト全体の統一（G4/G5）、公開ゲートの切替、静的HTML再生成・デプロイはサイトリポジトリ側の作業。今回のTamorリポジトリのpullでは変更されない。
- 法務ページはまだ草案であるため、アプリ内リンクが完成しても公開準備完了とは扱わない。
- 購入・復元の実検証、新しい申請用ビルド、App Store Connectの未入力項目は継続して残る。

## 資料の優先順位

`open-questions.md` の未確定表示には、同日に後から確定した内容が未反映の箇所がある。運営者名・連絡先などは `handoff-codex-2026-09-22.md` の「11. 決定ログ」を最新の引き継ぎ情報として参照する。本書は、その後のMac側の作業状況。

## 実機検証

- iPad第8世代・iPadOS26.7で英語ホーム・購入画面・設定のUIテスト1件合格（45.4秒、失敗0）。設定下部の3リンクの英語表示を画像で確認。
- UIテストでは購入SDKを無効化しているため、購入・復元成功の検証ではない。
- pull前のバックアップ、実機画像、ログ・メモリ記録を `build/pull-support-20260922/` に保存（Git管理外）。
- Releaseビルド成功。成果物にも輸出フラグfalse、iPhone専用設定、Privacy Manifestを確認。最大RSS約3.30 GiB、スワップ0。
- 最新Release版を接続済みiPadへインストールし、通常起動に成功。

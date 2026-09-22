# Tamor サポート／法務ページ（納品物の索引）

2026-09-22 作成。`docs/prompts/claude-tamor-support-legal-site.md` への回答。

FAQ・利用規約・プライバシーポリシーの日英6文書を作成し、既存の MarcottLab サイト
（Laravel 12 / Blade）へ Tamor 専用の掲載場所を実装しました。**本番へのデプロイ・DNS変更・
サービス再起動・メール送信・App Store の送信は行っていません。**

2026-09-22 追記：配信方式を**静的HTML**へ変更しました。本文は引き続き Blade で書き、
`php artisan tamor:export` で `public/` 配下へ書き出したファイルを配信します。
これに伴い公開URLが `.html` 付きに変わっています（下記「全URL対応表」）。

| 文書 | 内容 |
| --- | --- |
| このファイル | 実装の要約、変更差分、全URL対応表 |
| [data-handling.md](data-handling.md) | データ取扱い一覧、根拠となる実装箇所、公式資料のURLと確認日、App Store Connect 用の内部レビュー資料 |
| [open-questions.md](open-questions.md) | 公開前に確定が必要な事項のチェックリスト |
| [verification-and-deploy.md](verification-and-deploy.md) | 実施した検証、未実施の検証、デプロイ案・公開後確認・ロールバック手順 |

本文の正本は**サイト側の Blade ビュー**です。このフォルダには本文を複製していません
（二重管理を避けるため）。本文を直すときはサイトリポジトリのビューだけを直します。

## 対象リポジトリ

| 用途 | 場所 |
| --- | --- |
| アプリ | `github.com/sugie/tamor`（ローカル `C:\Users\ringo\opt\tamor`、ブランチ `codex/testflight-preparation`） |
| サイト | `bitbucket.org/fyhealth/marcottlab-site`（ローカル `C:\Users\ringo\opt\marcottlab\marcottlab-corporate-site`、ブランチ `feature/minimal-corporate-site`） |

Tamor 側のゲームコード・課金コード・プロジェクト設定は変更していません。本タスクで
Tamor リポジトリに追加したのは `docs/release/support-site/` 配下の4文書のみです。

## サイト側の変更差分

| 種別 | ファイル | 内容 |
| --- | --- | --- |
| 追加 | `config/tamor.php` | Tamor ページ用の単一の情報源。運営者名・施行日・App Store URL・公開ゲート |
| 追加 | `app/Support/TamorPages.php` | 公開URLと静的HTMLの出力先の単一の情報源。Blade・ルート・テストはここを参照する |
| 追加 | `app/Console/Commands/ExportTamorPages.php` | `php artisan tamor:export`。8ページを `public/` 配下へ書き出す（`--check` で差分確認） |
| 追加 | `public/apps/tamor/*.html`・`public/en/apps/tamor/*.html` | **書き出した実体（配信されるファイル）**。Blade を直したら書き出し直してコミットする |
| 追加 | `server.php` | `php artisan serve` 用ルーター。静的ファイル→`index.html`→Laravel の順に解決し、`SCRIPT_NAME` を正規化する |
| 追加 | `app/Http/Controllers/TamorController.php` | 8アクション（日英 × 4ページ）。canonical / hreflang / robots を渡す |
| 追加 | `resources/views/apps/tamor/index.blade.php` | 案内トップ（3文書＋Tamor 専用メール窓口への導線） |
| 追加 | `resources/views/apps/tamor/faq.blade.php` | FAQ 本文（日英） |
| 追加 | `resources/views/apps/tamor/terms.blade.php` | 利用規約 本文（日英） |
| 追加 | `resources/views/apps/tamor/privacy.blade.php` | プライバシーポリシー 本文（日英） |
| 追加 | `resources/views/apps/tamor/partials/nav.blade.php` | 草案バナー＋4ページのサブナビ |
| 追加 | `resources/views/apps/tamor/partials/meta.blade.php` | 対象アプリ・運営者・施行日・窓口のブロック |
| 追加 | `resources/views/apps/tamor/partials/styles.blade.php` | Tamor ページ用の最小限のCSS（既存の Bootstrap 5 CDN に追従） |
| 追加 | `resources/views/layouts/tamor.blade.php` | **Tamor 専用レイアウト。** 運営者が個人のため、法人名・本店所在地・会社サイトのナビを出さない |
| 追加 | `tests/Feature/TamorPagesTest.php` | 41テスト（本文・公開ゲート・ルート・301転送） |
| 追加 | `tests/Feature/TamorStaticExportTest.php` | 9テスト（書き出したファイルの検証、`public/` の鮮度確認） |
| 変更 | `routes/web.php` | Tamor の8ルート（書き出し前の確認用・代替）と、拡張子なし旧パスからの301転送6本 |
| 変更 | `public/.htaccess` | `DirectoryIndex index.html index.php` と、`/en`・`/apps` を Laravel に逃がすリライトを追加 |
| 変更 | `resources/views/layouts/corporate.blade.php` | `$robots` 変数（既定は従来どおり `index, follow`）、公開後だけ出るフッターリンク |
| 変更 | `resources/views/corporate/home.blade.php` | 公開後だけ出る「アプリ」セクション |
| 変更 | `resources/views/corporate/privacy.blade.php` | 公開後だけ出る、Tamor ポリシーとの相互参照（**本文は上書きしていません**） |
| 変更 | `.env.example` | `TAMOR_*` の設定項目と注意書き |

新しい SPA・別CMS・新しいビルド依存は追加していません。`public/sitemap.xml` は未変更です
（未公開のURLを sitemap に載せないため。公開時の追記手順は verification-and-deploy.md にあります）。

### 公開ゲート（未確定のまま本番公開しない仕組み）

`config('tamor.published')` が true になるまで、次のようにふるまいます。

- 4ページとも `<meta name="robots" content="noindex, nofollow">`
- ページ上部に「公開前の草案です」バナーを表示し、**何が未確定かを具体的に列挙**
- 運営者名・施行日の欄は「確認中」と表示（もっともらしい社名・日付を入れない）
- 会社サイト側（フッター・トップ・`/privacy`）に Tamor への導線を出さない

`TAMOR_PAGES_PUBLISHED=true` にしても、運営者名（日英）と3つの日付がすべて設定されるまで
公開扱いになりません。したがって**コードを本番へ反映しても、表示は何も変わりません**。

さらに静的配信なので、**`.env` を直しただけでも公開ページは変わりません。**
`php artisan tamor:export` を実行して `public/` 配下を書き出し直し、その差分を
コミット・デプロイして初めて反映されます（公開を二段階で確認できる利点でもあり、
戻すときに書き出し直しを忘れやすい落とし穴でもあります）。

## 配信方式（静的HTML）

```
resources/views/apps/tamor/*.blade.php   ← 本文の正本（ここだけを直す）
        │  php artisan tamor:export
        ▼
public/apps/tamor/{index,faq,terms,privacy}.html      ← 配信される実体
public/en/apps/tamor/{index,faq,terms,privacy}.html
```

| コマンド | 用途 |
| --- | --- |
| `php artisan tamor:export` | 8ページを `public/` 配下へ書き出す |
| `php artisan tamor:export --check` | 書き出さず、既存ファイルが Blade と一致するか確認（CI・テスト用） |
| `php artisan tamor:export --base=http://localhost:8124` | ローカル確認用の絶対URLで書き出す |

`.html` 付きにしたのは、**本番 Web サーバーの `DirectoryIndex` 設定に依存させない**ためです
（本番構成は未確認。[open-questions.md](open-questions.md) D1）。案内トップだけは
`index.html` をディレクトリ索引として使うため末尾スラッシュ付きです。

書き出したHTMLはサイトリポジトリにコミットします。Blade を直したら書き出し直す必要があり、
忘れると公開ページだけ古いまま残ります（`TamorStaticExportTest` が検出します）。

## 全URL対応表

`https://marcottlab.com` 配下。日本語は接頭辞なし・英語は `/en` という既存サイトの規約に合わせています。

| 用途 | 日本語 | 英語 | 状態 |
| --- | --- | --- | --- |
| 案内トップ（サポート） | `/apps/tamor/` | `/en/apps/tamor/` | **予定**（ローカル実装済み・未デプロイ） |
| FAQ | `/apps/tamor/faq.html` | `/en/apps/tamor/faq.html` | **予定** |
| 利用規約 | `/apps/tamor/terms.html` | `/en/apps/tamor/terms.html` | **予定** |
| プライバシーポリシー | `/apps/tamor/privacy.html` | `/en/apps/tamor/privacy.html` | **予定** |
| お問い合わせ | `tamor@sapp.sakura.ne.jp`（`mailto:` リンク） | 同左 | 会社サイトの問い合わせフォームは使わない |
| 会社サイトのプライバシーポリシー | `/privacy` | `/en/privacy` | 既存・公開済み（**Tamor 用に上書きしていません**） |

既存ルートとの衝突はありません。`/apps/...` は総称ルート `/{locale}/...` より前に定義しており、
`/apps/profile`・`/apps/other` が 404 になることをテストで確認しています。
拡張子なしの旧パス（`/apps/tamor/privacy` など）は 301 で `.html` へ転送します。

**静的ファイルを置いたことによる既存URLへの影響（対処済み）**

`public/en/` と `public/apps/` が実在ディレクトリになるため、そのままでは Laravel が
配信している **`/en`（英語トップ）が 403 / 404 になります**。次の2点で回避しています。

| ファイル | 対応 |
| --- | --- |
| `public/.htaccess` | `DirectoryIndex index.html index.php`・`DirectorySlash Off`・`^(en\|apps\|en/apps)/?$` の逃がし・`/apps/tamor` → `/apps/tamor/` の転送・`AddDefaultCharset UTF-8` |
| `server.php`（新規） | `php artisan serve` 用ルーター。実ファイル→`index.html`→Laravel の順に解決し、`SCRIPT_NAME` を `/index.php` に正規化する |

`server.php` の正規化が無いと、PHP ビルトインサーバーが `/apps/tamor/privacy` を
`SCRIPT_NAME=/apps/tamor` ＋ `PATH_INFO=/privacy` と切り出し、**会社サイトの `/privacy` が
表示されてしまいます**（ローカル確認で実際に再現し、対処しました）。

**Apache では使い捨てコンテナ（`php:8.4-apache`）で全URLの応答を実測し、既存URLが
すべて従来どおりであることを確認済みです**（[verification-and-deploy.md](verification-and-deploy.md) 1.2.2）。
本番が nginx の場合は同等の設定が別途必要です（[open-questions.md](open-questions.md) D4）。

### App Store Connect の入力欄への候補

いずれも**公開（デプロイ＋公開ゲートを開く）まで実在しません**。実在確認前に管理画面へ入力しないでください。

| 入力欄 | 候補URL | 備考 |
| --- | --- | --- |
| Privacy Policy URL（App情報） | `https://marcottlab.com/apps/tamor/privacy.html` | 主言語=日本語のため日本語URLを主とする |
| Privacy Policy URL（英語ローカライズ） | `https://marcottlab.com/en/apps/tamor/privacy.html` | |
| Support URL（バージョン情報） | `https://marcottlab.com/apps/tamor/` | FAQ と Tamor 専用のメール窓口に到達できる |
| Support URL（英語ローカライズ） | `https://marcottlab.com/en/apps/tamor/` | |
| Marketing URL（任意） | `https://marcottlab.com/apps/tamor/` | 未設定でも可 |
| License Agreement（EULA） | **設定しない** | Apple 標準EULAのまま。理由は下記 |
| TestFlight の Privacy Policy URL | `https://marcottlab.com/apps/tamor/privacy.html` | |

### Apple 標準EULA との関係（提案）

**独自EULAを登録せず、Apple の Licensed Application End User License Agreement（標準EULA）を
そのまま適用し、本利用規約はこれを補う「追加の利用条件」とする**ことを提案します。

- 標準EULAは Apple 側で多言語に用意され、配信・表示の責任も Apple 側にあります。独自EULAに
  差し替えると、全体を自前で維持し、Apple の審査にも通す必要が生じます。
- Tamor に必要な追加事項（ゲーム内データが換金資産でないこと、買い切り商品の範囲、20ct の技能条件、
  端末内保存とバックアップの注意）は、標準EULAを置き換えなくても追加条件として書けます。
- 規約本文の「2. Apple の標準EULAとの関係」に、**抵触する場合は標準EULAが優先する**旨を明記しています。

方針を変えて独自EULAにする場合は、規約本文の当該節と App Store Connect の EULA 欄を同時に直してください。

## 本文で守った方針

- 価格を規約に恒久固定せず、「App Store の表示が正」と書いています（日本400円／米国1.99ドルは本文に書いていません）。
- 「購入で宝石が増えるわけではない」「20ct は深度6で同じ宝石・同じルール版のS評価3連続」を FAQ と規約の両方に明記。
- 「端末保存だから個人情報を一切収集しない」とは書かず、RevenueCat 経由の送信を項目ごとに説明。
- さくらのクラウドは**サポートサイトの基盤**と書き、宝石の保存先とは書いていません。
- リージョン・ログ保存期間は未確認なので数値を書かず、`TAMOR_LOG_RETENTION` を設定したときだけ表示します。
- 問い合わせは **Tamor 専用のメールアドレス**（`config('tamor.contact_email')`、既定 `tamor@sapp.sakura.ne.jp`）へ誘導します。
  会社サイトの問い合わせフォームは使いません（運営者が個人であり、はたらきろくと同じくアプリごとに窓口を分ける方針）。
  これに伴い、フォームの迷惑送信対策・Cloudflare Turnstile・セッション Cookie の記述は本文から外しました。
  サポートページは静的HTMLで Cookie を一切使わないため、その旨をプライバシーポリシー第3節に明記しています。
- App Store リンクは `TAMOR_APP_STORE_URL` 未設定のあいだ描画しません。
- TestFlight の節は一般公開版と区分し、**招待URLは載せていません**。
- **名義は個人（杉江 正 / Tadashi Sugie）。** MarcottLab株式会社は未登記のため、4ページに法人名・
  本店所在地・代表者名を出しません。専用レイアウト `layouts/tamor.blade.php` を使い、ヘッダー・
  タイトル・フッターを運営者名に統一しています。**会社サイト側の表示は変更していません**（G5 に残置）。

## 法的な位置づけについて

本文は Claude が作成した草案です。**法律上の適合性・有効性を保証するものではありません。**
特に準拠法・専属管轄・事業者表示・個人情報保護法上の記載事項については、
公開前に運営者および必要に応じて専門家の確認を受けてください（[open-questions.md](open-questions.md)）。

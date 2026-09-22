# 引き継ぎ（Codex 向け）— Tamor サポート／法務ページ

2026-09-22 作成。Windows 側（Claude Code）から Mac 側（Codex）へ作業を引き継ぐための資料です。
**この1ファイルだけ読めば続きから作業できる**ことを目指しています。

- 決定事項の一覧（表形式）: [`open-questions.xlsx`](open-questions.xlsx) — 39項目。人間が記入する欄あり
- 実装の詳細: [`README.md`](README.md)
- データ取扱いの根拠: [`data-handling.md`](data-handling.md)
- 検証記録とデプロイ手順: [`verification-and-deploy.md`](verification-and-deploy.md)

---

## 1. 対象の2リポジトリ

| 用途 | 場所 | ブランチ |
| --- | --- | --- |
| アプリ | `github.com/sugie/tamor` | `codex/testflight-preparation` |
| サイト | `bitbucket.org/fyhealth/marcottlab-site` | `main`（`0c7b5ba` が本番に反映済み） |

サイト側の Tamor 関連はすべて `main` にマージ済みで、**未マージの作業はありません**。
次の作業は `main` から新しいブランチを切ってください。

---

## 2. いま本番に出ているもの

`https://marcottlab.com` に日英8ページが公開済みです。ただし **`noindex` ＋「公開前の草案です」バナー付き**で、
サイト内のどこからもリンクされていません。URL を直接開いた人だけが見られる状態です。

| 用途 | 日本語 | 英語 |
| --- | --- | --- |
| 案内トップ | `/apps/tamor/` | `/en/apps/tamor/` |
| FAQ | `/apps/tamor/faq.html` | `/en/apps/tamor/faq.html` |
| 利用規約 | `/apps/tamor/terms.html` | `/en/apps/tamor/terms.html` |
| プライバシーポリシー | `/apps/tamor/privacy.html` | `/en/apps/tamor/privacy.html` |

拡張子なしの旧パス（`/apps/tamor/faq` など日英6本）は 301 で `.html` へ転送します。

ページに出ている値（2026-09-22 時点、本番で実測）:

```
運営者     杉江 正 / Tadashi Sugie     ← 個人。法人ではない
所在地     東京都八王子市 / Hachioji, Tokyo, Japan
施行日     2026-09-22
お問い合わせ tamor@sapp.sakura.ne.jp    ← 受信確認済み
準拠法     日本法・東京地方裁判所 / Tokyo District Court
robots     noindex, nofollow
```

---

## 3. 配信のしくみ（ここを誤解すると事故る）

**本文は Blade で書き、静的HTMLに書き出して配信します。PHP は動きません。**

```
resources/views/apps/tamor/*.blade.php    ← 本文の正本。ここだけを直す
        │  php artisan tamor:export
        ▼
public/apps/tamor/{index,faq,terms,privacy}.html      ← 配信される実体。コミットする
public/en/apps/tamor/{index,faq,terms,privacy}.html
```

| コマンド | 用途 |
| --- | --- |
| `php artisan tamor:export` | 8ページを `public/` へ書き出す |
| `php artisan tamor:export --check` | 書き出さずに、既存ファイルが Blade と一致するか確認（終了コードで判定） |
| `php artisan tamor:export --base=http://localhost:8000` | ローカル確認用の絶対URLで書き出す |
| `php artisan tamor:export --path=/tmp/out` | 別の場所へ書き出す |

### 必ず守ること

1. **Blade・`config/tamor.php`・`.env` のいずれかを直したら `tamor:export` を実行し、`public/` の差分も一緒にコミットする。**
   忘れると公開ページだけ古いまま残ります。`TamorStaticExportTest::test_the_committed_pages_under_public_are_up_to_date` が検出します。
2. **URL をベタ書きしない。** `app/Support/TamorPages.php` が単一の情報源です（`path()` / `url()` / `file()`）。
3. **問い合わせ先をベタ書きしない。** `config('tamor.contact_email')` を使います。
4. **`public/.htaccess` の行を消さない。** 下記 5 章参照。消すと英語トップ `/en` が壊れます。
5. **`server.php` を消さない。** `php artisan serve` 用のルーターで、本番 Apache と同じ解決順にそろえています。

---

## 4. 公開ゲート

`config/tamor.php` の `published` が false のあいだは、4ページとも `noindex` ＋草案バナーで、
会社サイト側（フッター・トップ・`/privacy`）に Tamor への導線が出ません。

`published = ready && TAMOR_PAGES_PUBLISHED` で、`ready` は次の5つがすべて埋まっていること:

`TAMOR_OPERATOR_NAME` / `TAMOR_OPERATOR_NAME_EN` / `TAMOR_TERMS_EFFECTIVE` /
`TAMOR_PRIVACY_EFFECTIVE` / `TAMOR_FAQ_UPDATED`

**静的配信なので `.env` を変えただけでは公開ページは変わりません。** 必ず `tamor:export` → コミット → デプロイ。

### `.env`（サイトリポジトリ）

ローカル（書き出しを実行する環境）と本番の両方に必要です。本番は `published` の判定にだけ使いますが、
公開後にサイト内導線を出すために必要です。

```
TAMOR_OPERATOR_NAME="杉江 正"
TAMOR_OPERATOR_NAME_EN="Tadashi Sugie"
TAMOR_TERMS_EFFECTIVE=2026-09-22
TAMOR_PRIVACY_EFFECTIVE=2026-09-22
TAMOR_FAQ_UPDATED=2026-09-22
TAMOR_PAGES_PUBLISHED=false
TAMOR_OPERATOR_ADDRESS="東京都八王子市"
TAMOR_OPERATOR_ADDRESS_EN="Hachioji, Tokyo, Japan"
TAMOR_GOVERNING_LAW=jp
TAMOR_JURISDICTION="東京地方裁判所"
TAMOR_JURISDICTION_EN="Tokyo District Court"
TAMOR_LOG_RETENTION=
TAMOR_LOG_RETENTION_EN=
TAMOR_APP_STORE_URL=
TAMOR_TESTFLIGHT_SECTION=true
TAMOR_CONTACT_EMAIL=tamor@sapp.sakura.ne.jp
```

**本番 `.env` にはまだ 1 つも入っていません。** 現状それで問題ありません（静的HTMLに値が焼き込まれているため）。
公開時に入れてください。

---

## 5. Web サーバー設定（壊しやすい箇所）

`public/en/` と `public/apps/` を実ディレクトリとして作ったため、そのままでは Laravel が配信している
**`/en`（英語トップ）が 403 / 404 になります**。次の2ファイルで回避しています。**行を消さないでください。**

### `public/.htaccess`

```apache
AddDefaultCharset UTF-8

<IfModule mod_dir.c>
    DirectoryIndex index.html index.php
    DirectorySlash Off
</IfModule>

    RewriteRule ^(en|apps|en/apps)/?$ index.php [L]
    RewriteRule ^((?:en/)?apps/tamor)$ /$1/ [R=301,L]
```

- `DirectorySlash Off` が無いと、mod_dir が mod_rewrite より先に動いて **`/en` が `/en/` へ 301** されます。
- その副作用で `/apps/tamor` が 403 になるため、2本目のリライトで末尾スラッシュへ転送しています。
- これらは使い捨ての `php:8.4-apache` コンテナで全URLの応答を実測して決めました。
- `TamorStaticExportTest::test_htaccess_keeps_the_english_top_page_on_laravel` が各ディレクティブの存在を検証します。

### `server.php`（`php artisan serve` 用）

PHP ビルトインサーバーは URL 先頭に実在ディレクトリがあると `SCRIPT_NAME=/apps/tamor` ＋
`PATH_INFO=/privacy` と切り出すため、正規化しないと **`/apps/tamor/privacy` が会社サイトの `/privacy`
として処理されます**。`server.php` で `SCRIPT_NAME` を `/index.php` に固定して回避しています。

**本番が nginx になった場合、`.htaccess` は一切効きません。** 同等の設定が別途必要です（未検証）。

---

## 6. 本番サーバー（実測済みの事実）

| 項目 | 値 |
| --- | --- |
| ホスト | `ssh kaoru` = 153.127.218.156（さくら、Ubuntu） |
| Web サーバー | Apache 2.4.58、mod_php、`AllowOverride All`、mod_rewrite / mod_dir / mod_mime 有効 |
| DocumentRoot | `/var/apps/marcottlab-site/public` |
| PHP | 8.3.6（opcache `validate_timestamps=On`） |
| 所有者 | `www-data`。SSH ユーザー `ubuntu` は NOPASSWD sudo 可 |
| デプロイ | git。`origin/main` を pull。www-data の Bitbucket 鍵は `/var/www/.ssh` |
| キャッシュ | `config.php` と `routes-v7.php` を使用中 |

### デプロイ手順

```bash
ssh kaoru
cd /var/apps/marcottlab-site
sudo -u www-data git pull --ff-only origin main
sudo -u www-data php artisan config:cache
sudo -u www-data php artisan route:cache
sudo -u www-data php artisan view:clear
sudo systemctl reload apache2
```

**`config:cache` と `route:cache` を忘れると新しいルートが効きません。** 実際に一度これで
拡張子なしURLが 404 のままになりました。

### 検証

```bash
for u in / /en /company /en/company /privacy /en/privacy /public-notice /contact /ja/contact /en/contact \
         /apps/tamor/ /apps/tamor/faq.html /apps/tamor/terms.html /apps/tamor/privacy.html \
         /en/apps/tamor/ /en/apps/tamor/faq.html /en/apps/tamor/terms.html /en/apps/tamor/privacy.html \
         /apps/tamor/faq /apps/tamor/privacy /apps/profile /apps ; do
  printf '%-30s %s\n' "$u" "$(curl -s -o /dev/null -w '%{http_code}' "https://marcottlab.com$u")"
done
```

期待値: 既存URLは 200（`/contact` は 302）、Tamor 8ページは 200、`/apps/tamor` と
`/en/apps/tamor` と拡張子なし6本は 301、`/apps` `/apps/other` `/apps/profile` は 404。

**`/en` が 200 であることを毎回必ず確認してください。**

---

## 7. 次にやること（優先順）

### 7.1 【最優先】G5・G4 — 会社サイトから「株式会社」表記を外す

**決定（2026-09-22、杉江 正）: 株式会社は表示しない。登記のめどが立っていないため、会社サイトも
「杉江 正」個人で統一する。**

Tamor の4ページは対応済み（専用レイアウト `resources/views/layouts/tamor.blade.php`）。
**会社サイト本体は未着手**です。

対象は `config/company.php` と、それを参照する次のビューです。

| ファイル | 法人前提の表示の数 |
| --- | --- |
| `resources/views/layouts/corporate.blade.php` | 7 |
| `resources/views/corporate/home.blade.php` | 12 |
| `resources/views/corporate/company.blade.php` | 10 |
| `resources/views/corporate/privacy.blade.php` | 2 |
| `resources/views/contact.blade.php` | 3 |

`config/company.php` のキー: `legal_name` `display_name` `english_name` `representative`
`representative_en` `postal_code` `address` `address_en` `address_region` `address_locality`
`street_address` `capital` `capital_en` `founded` `founded_en` `business` `business_en`
`public_notice_method` `public_notice_method_en` `site_url` `contact_email`

判断が必要な点:

1. **`/public-notice`（電子公告）をどうするか。** 電子公告は会社法上の制度で、法人でなければ
   そもそも不要です。ページごと外すのか、残すのかを決めてください。
2. **`capital`（資本金）・`representative`（代表取締役）・本店所在地（東京都港区北青山）。**
   個人事業なら該当しません。所在地は Tamor に合わせて「東京都八王子市」まで、が既存の方針です。
3. **英語ページ**（`/en`・`/en/company`・`/en/privacy`）も同時に直すこと。
4. **`ContactController` / `contact.blade.php`** も会社情報を参照しています。
5. 既存テスト `CorporatePagesTest` `HomePageTest` が会社名を検証しているので、一緒に直すこと。
   `CorporatePagesTest::test_founded_date_is_not_asserted_as_completed` は
   「設立済みと断定しない」ことを検証しており、方針としては維持すべきです。

Tamor 側のテスト `TamorPagesTest::test_corporate_pages_still_show_the_company_name` は
**会社サイトが法人名を出し続けること**を前提にしています。この作業で当然失敗するので、
新しい方針に合わせて書き換えてください（このテストの存在意義は「Tamor と会社サイトが
互いに混ざらないこと」の確認なので、表示内容だけ差し替えれば足ります）。

Tamor の4ページは `config/company.php` を参照していません（`config/tamor.php` が独立した情報源）。
唯一の例外は `company.site_url`（canonical / OGP 用）で、これはドメインなので変更不要です。

### 7.2 C6 — 輸出コンプライアンスの申告と新ビルド

実装調査は完了しています（Tamor リポジトリ）。

- 暗号ライブラリ（CryptoKit / CommonCrypto）の使用なし、独自の暗号実装なし
- 通信は RevenueCat SDK 経由の HTTPS のみ（`URLSession` などの直接使用はゼロ）
- CloudKit は `project.yml` の `excludes` でビルド対象外

App Store Connect での回答:

| 質問 | 回答 |
| --- | --- |
| 暗号化を使用しますか | はい |
| Category 5 Part 2 の免除に該当しますか | はい（HTTPS のみ、独自・非標準の暗号実装なし） |
| 独自の暗号アルゴリズムを実装していますか | いいえ |

`ITSAppUsesNonExemptEncryption: false` を `project.yml` と `Config/Info.plist` に設定済みです
（**この変更はまだコミットしていません。下記 8 章参照**）。

- **アップロード済みの build 5 には反映されません。** build 5 については ASC 上で1回答えてください。
- 次のビルドからは質問が出ません。**Mac 側で `xcodegen` を実行して `.xcodeproj` を再生成**してください
  （Windows では実行できなかったため未実施）。

### 7.3 C8 — アプリ内にプライバシーポリシーへのリンクを追加

App Store のガイドライン 5.1.1(i) の要求です。URL は確定しています。

```
https://marcottlab.com/apps/tamor/privacy.html
```

Tamor の設定画面に追加してください。**本作業ではアプリのコードを変更していません。**

### 7.4 一般公開（`TAMOR_PAGES_PUBLISHED=true`）

1. ローカルの `.env` を `TAMOR_PAGES_PUBLISHED=true` にする
2. `php artisan tamor:export` → `public/` の差分をコミット
3. `public/sitemap.xml` に8URLを追記（日本語トップ 0.6、FAQ 0.5、規約・ポリシー 0.4、英語は各 -0.1 が案）
4. PR → マージ
5. 本番 `.env` に `TAMOR_*` を追加 → デプロイ手順（6章）
6. 検証: 草案バナーが消えていること、`robots` が `index, follow` であること、
   会社サイトのフッター・トップ・`/privacy` に Tamor への導線が出ていること

### 7.5 App Store Connect に入れるURL

| 欄 | URL |
| --- | --- |
| Privacy Policy URL（日本語） | `https://marcottlab.com/apps/tamor/privacy.html` |
| Privacy Policy URL（英語） | `https://marcottlab.com/en/apps/tamor/privacy.html` |
| Support URL（日本語） | `https://marcottlab.com/apps/tamor/` |
| Support URL（英語） | `https://marcottlab.com/en/apps/tamor/` |
| License Agreement（EULA） | 設定しない（Apple 標準EULAのまま。決定済み B9） |

### 7.6 その他の未決事項

`open-questions.xlsx` の「決定事項」シートを見てください。優先度「必須」で未記入のものが残っています。
特に **E1〜E4（法的レビュー）** は専門家の確認が必要な項目で、本文は Claude が作成した草案です。

---

## 8. 未コミットの変更（Tamor リポジトリ）

引き継ぎ時点で、`codex/testflight-preparation` ブランチに次の未コミット変更があります。

| ファイル | 内容 |
| --- | --- |
| `project.yml` | `ITSAppUsesNonExemptEncryption: false` を追加（輸出コンプライアンス） |
| `Config/Info.plist` | 同上 |
| `docs/release/support-site/` | この引き継ぎ資料を含む5ファイル（新規） |
| `docs/release/device-testflight-2026-09-22.md` | 既存の変更（本作業とは無関係） |

`project.yml` を変更したので、**Mac 側で `xcodegen` を実行して `.xcodeproj` を再生成**してください。

---

## 9. 落とし穴（実際に踏んだもの）

| 症状 | 原因と対処 |
| --- | --- |
| `/en` が 404 / 403 になる | `public/en/` が実ディレクトリだから。`.htaccess` の `DirectorySlash Off` とリライトで回避済み。行を消さないこと |
| `/apps/tamor/privacy` が会社サイトの `/privacy` を表示する | `php artisan serve` のビルトインサーバーが `SCRIPT_NAME` を誤判定。`server.php` で正規化済み |
| 新しいルートが本番で 404 | `route:cache` の作り直し忘れ |
| 公開ページだけ古い | `tamor:export` の実行忘れ。`--check` で検出できる |
| 生成HTML内のリンクが `http://` になる | CLI の既定スキームが http。`ExportTamorPages` が `URL::forceScheme` で対処済み |
| テストが `.env` の値で結果が変わる | `TamorPagesTest::draft()` / `publish()` で config を明示的に設定すること |

---

## 10. テストと静的解析

```bash
php artisan test --filter=TamorPagesTest         # 44 テスト
php artisan test --filter=TamorStaticExportTest  # 9 テスト
php vendor/phpunit/phpunit/phpunit               # 全体 97 テスト
php artisan tamor:export --check                 # 書き出しの鮮度
```

**既知の失敗:** `ProfilePageTest` の 2 件（`test_japanese_profile_page_displays_japanese_content` /
`test_english_profile_page_displays_english_content`）は**本作業とは無関係の既存の失敗**です。
`lang/ja/profile.php` にテストが期待する文字列が存在しないためで、コミット
`6034330 feat: redesign profile page...` でテストが追随しなかったものと見られます。

**Pint:** リポジトリ全体では既存ファイルが複数 fail します（`MarliController` `PriceListController`
`app/Mail/*` `ContactFormTest`）。**変更したファイルだけを対象に実行してください。**

```bash
php vendor/bin/pint --test <変更したファイル>
```

---

## 11. 決定ログ（2026-09-22）

| ID | 決定 | 状態 |
| --- | --- | --- |
| A1 / A2 | 運営者は **杉江 正 / Tadashi Sugie**（個人。法人ではない） | 反映済み |
| A3〜A5 | 施行日・更新日はいずれも 2026-09-22 | 反映済み |
| A6 | 登記は未了。法人化は永続的な収益の見通しが立つまで保留 | — |
| A7 | App Store の販売元も個人「杉江 正」に統一 | ASC 側の確認が残り |
| B1 | 準拠法・管轄を規約に入れる（東京地方裁判所 / Tokyo District Court） | 反映済み |
| B2 | 所在地は市まで（東京都八王子市）。番地・建物名は載せない | 反映済み |
| B5 | RevenueCat との DPA は締結済み | — |
| B6 | Cloudflare Turnstile は使わない | 反映済み（本文から記述を削除） |
| B7 | 問い合わせは **tamor@sapp.sakura.ne.jp**。会社サイトのフォームは使わない | 反映済み・**受信確認済み** |
| B9 | Apple 標準EULAのまま。独自EULAは登録しない | 反映済み |
| C5 | ベータ関連は載せない | — |
| C6 | 暗号化は免除に該当。`ITSAppUsesNonExemptEncryption=false` | 設定済み・ASC 申告が残り |
| C7 | App Privacy は案どおり送信 | 未送信 |
| C8 | アプリ内にプライバシーポリシーのリンクを追加する | 未実装 |
| G1 | Tamor の4ページを個人名義に | 反映済み |
| G3 | プライバシーポリシーは一般的な構成とし、目的外の流用をしない旨を明記 | 反映済み |
| **G4 / G5** | **会社サイトも「株式会社」を表示しない。杉江 正 個人で統一** | **未着手（最優先）** |

**G2（Tamor のページを marcottlab.com 配下に置いたままでよいか）は未決**です。
参考として、同じ運営者の先行アプリ「はたらきろく」は独自ドメイン `hatarakiroku.jp` の
静的サイトに分けています（`open-questions.xlsx` の「はたらきろく参考」シート）。

---

## 12. 参考にした先行事例

同じ運営者の先行アプリ「はたらきろく」（`/Users/<user>/opt/hatarakiroku`、`https://hatarakiroku.jp/`）。
運営者名・所在地・問い合わせ先の表記はここに合わせています。詳細は
`open-questions.xlsx` の「はたらきろく参考」シート（12行）を参照してください。

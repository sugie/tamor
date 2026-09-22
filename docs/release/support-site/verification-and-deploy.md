# 検証記録とデプロイ案

2026-09-22。すべてローカル（Windows、PHP 8.4.7、既存の `vendor/`）で実施しました。
**本番サーバーへの接続・変更・デプロイ・再起動は行っていません。**

## 1. 実施した検証

### 1.1 既存のテスト手順（`composer run test` 相当）

`php vendor/phpunit/phpunit/phpunit` を実行。

| 対象 | 結果 |
| --- | --- |
| `TamorPagesTest`（新規） | **41 テスト 成功** |
| `TamorStaticExportTest`（新規） | **9 テスト 成功** |
| 全体 | 94 テスト / 445 アサーション、**失敗 2 件**（`ProfilePageTest`。下記 1.7 の既存の失敗） |

`php vendor/bin/pint --test`（新規PHPファイルと `routes/web.php`）→ `{"result":"pass"}`

### 1.2 HTTP 200（PHP 組み込みサーバー `php artisan serve`）

`php artisan tamor:export` で `public/` 配下へ書き出したうえで `curl` で実測。
静的ファイルがそのまま返っていること（バイト数がファイルと一致）も確認しました。

| URL | 結果 | 返しているもの |
| --- | --- | --- |
| `/apps/tamor/` | 200 | `public/apps/tamor/index.html` |
| `/apps/tamor/faq.html` | 200 | 静的ファイル |
| `/apps/tamor/terms.html` | 200 | 静的ファイル |
| `/apps/tamor/privacy.html` | 200 | 静的ファイル |
| `/en/apps/tamor/` | 200 | `public/en/apps/tamor/index.html` |
| `/en/apps/tamor/faq.html` | 200 | 静的ファイル |
| `/en/apps/tamor/terms.html` | 200 | 静的ファイル |
| `/en/apps/tamor/privacy.html` | 200 | 静的ファイル |
| `/apps/tamor/faq`・`/terms`・`/privacy`（日英6本） | 301 | `.html` へ転送 |
| `/apps/tamor/zzz`・`/apps/profile`・`/apps` | 404 | — |

**既存URLの回帰も同時に確認**：`/`・`/company`・`/privacy`・`/public-notice`・
`/en`・`/en/company`・`/en/privacy`・`/ja/contact`・`/en/contact` がすべて 200。

#### 1.2.1 途中で見つけて直した不具合

`public/en/` と `public/apps/` を作った直後、**`/en`（英語トップ）が 404**、
**`/apps/tamor/privacy` が会社サイトの `/privacy` を表示**する状態になりました。

- 原因1：実在ディレクトリにはフロントコントローラーへのリライトが効かず、索引ファイルも無い。
- 原因2：PHP ビルトインサーバーが URL 先頭の実在ディレクトリを見て
  `SCRIPT_NAME=/apps/tamor` ＋ `PATH_INFO=/privacy` と切り出し、Symfony の baseUrl 判定で
  `/privacy` として処理していた。

`public/.htaccess` と `server.php`（`SCRIPT_NAME` の正規化）で対処し、再確認して解消しています。

#### 1.2.2 実 Apache での確認

`php artisan serve` だけでは本番の挙動を確かめられないため、**使い捨ての
`php:8.4-apache` コンテナ**にこのリポジトリをマウントし（DocumentRoot を `public/`、
`AllowOverride All`、`mod_rewrite` 有効）、全URLの応答を実測しました。作業後にコンテナは削除済みです。

| URL | 結果 |
| --- | --- |
| `/`・`/company`・`/privacy`・`/public-notice`・`/ja/contact`・`/en/contact` | 200（従来どおり） |
| **`/en`・`/en/company`・`/en/privacy`** | **200**（`public/en/` に奪われていない） |
| `/apps/tamor/`・`/en/apps/tamor/` | 200（静的 `index.html`。`X-Powered-By` が付かず PHP が動いていない） |
| `/apps/tamor/{faq,terms,privacy}.html`（日英6本） | 200（静的ファイル。バイト数が実ファイルと一致） |
| `/apps/tamor`・`/en/apps/tamor` | 301 → 末尾スラッシュ付き |
| 拡張子なしの `/apps/tamor/faq` など（日英6本） | 301 → `.html` |
| `/contact` | 302 → `/ja/contact`（従来どおり） |
| `/ja` | 301 → `/`（従来どおり） |
| `/apps`・`/apps/other`・`/apps/profile` | 404 |

この過程で `.htaccess` を2回直しています。

1. `DirectorySlash Off` を追加。mod_dir の末尾スラッシュ付与は mod_rewrite より先に動くため、
   これが有効なままだと **`/en` が `/en/` へ 301** され、サイト内の英語トップへのリンクが
   すべて1回よけいに転送されていました。
2. `RewriteRule ^((?:en/)?apps/tamor)$ /$1/ [R=301,L]` を追加。1 の副作用で
   **`/apps/tamor` が 403** になったため、案内トップだけ明示的に末尾スラッシュへ転送します。

**本番が nginx の場合、この `.htaccess` は効きません。**同等の設定が別途必要です
（[open-questions.md](open-questions.md) D4）。

### 1.3 言語・相互リンク・canonical / hreflang

`TamorPagesTest` で自動検証しています。

- 日本語ページ：`<html lang="ja">`、対応する `/en/...` へのリンク、`hreflang="ja"` と `hreflang="en"` の両方。
- 書き出したHTML内のサイト内リンクがすべて `https://marcottlab.com/...` の絶対URLで、
  `http://` が混ざらないこと（CLI の既定スキームが http のため取り違えやすい）。
- 拡張子なしの `/apps/tamor/faq` などが本文に残っていないこと（静的配信では 404 になるため）。
- 英語ページ：`<html lang="en">`、対応する日本語ページへのリンク。
- canonical：`https://marcottlab.com` + 自ページのパス（`config('company.site_url')` 由来）。
- 4ページ間のサブナビ（サポート／FAQ／利用規約／プライバシーポリシー）と、既存の問い合わせフォームへのリンク。
- 未公開のあいだ `robots` が `noindex, nofollow` であること、公開後に `index, follow` になること。

### 1.4 既存ページの回帰

| 確認 | 結果 |
| --- | --- |
| `/`・`/company`・`/privacy`・`/public-notice`・`/en`・`/en/company`・`/en/privacy` が 200 かつ `index, follow` のまま | 成功（`test_corporate_pages_stay_indexable`） |
| `/contact` → `/ja/contact` への転送、`/ja/contact` と `/en/contact` が 200 | 成功（`test_existing_contact_routes_still_work`） |
| 会社サイトの `/privacy` 本文が Tamor の本文で上書きされていない | 成功（`test_corporate_privacy_is_not_replaced_by_tamor_content`） |
| `/apps/profile`・`/apps/other`・`/apps/tamor/support` が 404（既存の `/{locale}/...` ルートを奪っていない） | 成功 |
| `CorporatePagesTest`・`HomePageTest`・`ContactFormTest` | 全件成功 |

### 1.5 スマートフォン幅の表示

Chrome で、同一オリジンの iframe を幅 375px に固定して各ページを読み込み、
`documentElement.scrollWidth` と `clientWidth` を比較しました。

- 8ページすべてで **横スクロールの発生なし**（`scrollWidth === clientWidth === 360`）。
- 既存の `/`・`/privacy`・`/ja/contact` も同様に横あふれなし。
- 幅の広い表（プライバシーポリシーのデータ一覧）は既存の `.table-responsive` の中で横スクロールし、
  ページ自体をあふれさせません。
- 幅 390px で FAQ（日本語）とプライバシーポリシー（英語）を目視確認。草案バナー・サブナビの折り返し、
  文書メタ情報の縦積み（`dt`/`dd`）、ヘッダーのハンバーガーメニューへの切り替えが想定どおり。

### 1.6 未実施の検証

- **本番環境での確認**（HTTPS、本番ドメイン、本番の実際のWebサーバー設定）。デプロイしていないため未実施。
  Apache の挙動はローカルの使い捨てコンテナで確認しましたが（1.2.2）、**本番が Apache である確証はありません**。
- **nginx での確認**。本番が nginx の場合、`public/.htaccess` は一切効きません。未検証・未対応です。
- **実機ブラウザでの確認**（iOS Safari / Android Chrome）。
- **スクリーンリーダーでの読み上げ確認。** 見出し階層・`aria-current`・`lang` 属性・スキップリンクは
  既存レイアウトの設計に合わせていますが、支援技術での実動作は未検証です。
- **`composer run test` そのもの**（`config:clear` を含むスクリプト）ではなく、PHPUnit を直接実行しています。
  `php artisan config:clear` は実行済みです。
- **メール送信**。問い合わせフォームの送信は行っていません（`ContactFormTest` はモックで成功）。

### 1.7 既存の失敗（本タスクと無関係）

`ProfilePageTest::test_japanese_profile_page_displays_japanese_content` と
`test_english_profile_page_displays_english_content` が失敗します。

- テストは `アーキテクト / ソフトウェアエンジニア` 等の文字列を期待していますが、
  この文字列は `lang/ja/profile.php` にも `resources/views/profile.blade.php` にも存在しません。
- `profile.blade.php` は `layouts.corporate` を継承しておらず、今回変更したレイアウト・ルート・config の
  いずれからも影響を受けません。`lang/`・`profile.blade.php`・`ProfilePageTest.php` は未変更です。
- コミット `6034330 feat: redesign profile page as legacy modernization trust-building page` で
  本文が差し替えられた際にテストが追随しなかったものと見られます。
- **本タスクの作業範囲外のため修正していません。** サイト側で別途対応してください。

## 2. デプロイ案

**本番構成がリポジトリに記載されていないため、実行可能なコマンド列としては確定できません。**
Docker ファイルはありますが、`CLAUDE.md` はこれをローカル開発環境（`localhost:6354`）として説明しており、
本番も Docker と断定できません。危険なコマンドを推測で実行しないでください。

### 2.1 デプロイ前に確認が必要な情報

| # | 確認事項 | なぜ必要か |
| --- | --- | --- |
| 1 | Webサーバー（Nginx / Apache）と、`public/` を指すドキュメントルート | **静的配信にしたため重要。** Apache なら `public/.htaccess` の追記で足りるが、**nginx なら `index index.html index.php;` と `/en` の逃がしを手で入れる必要がある**（入れないと英語トップが 403/404 になる） |
| 2 | 本番のデプロイ先パス（例 `/var/www/...`）と、実行ユーザー | `git pull` と権限の確認 |
| 3 | PHP のバージョンと PHP-FPM のサービス名 | OPcache を使っている場合、反映にリロードが必要 |
| 4 | デプロイ方法（`git pull` か、rsync か、CI か） | 手順が変わる |
| 5 | 設定キャッシュ（`config:cache`）を使っているか | `config/tamor.php` と `.env` の反映方法が変わる |
| 6 | 本番 `.env` の編集権限と手順 | `TAMOR_*` を追加する必要がある |
| 7 | `TURNSTILE_ENABLED` の本番での値 | プライバシーポリシーの Cloudflare の記述が自動的に変わるため |
| 8 | Vite のビルド成果物（`public/build/`）を本番でどう用意しているか | 今回 CSS/JS の追加はないため `npm run build` は不要な想定だが、手順の確認は必要 |

### 2.2 手順（案）

**段階1：コードだけ反映する（表示は変わらない）**

1. サイトリポジトリのブランチをレビューし、`main` へマージ。
2. 本番へ反映（上記 4 の方法）。`composer install` は不要（新しい依存はありません）。
3. `php artisan config:clear`、設定キャッシュを使っているなら `php artisan config:cache`。
   ビューキャッシュを使っているなら `php artisan view:clear`。
4. OPcache を使っている場合は PHP-FPM をリロード。
5. この時点で `/apps/tamor/` 系は 200 を返しますが、**noindex の草案バナー付き**で、
   会社サイト側からの導線は出ません。既存ページの表示は変わりません。
6. **`/en`・`/en/company`・`/en/privacy`・`/` が 200 のままであることを必ず確認。**
   静的ディレクトリ `public/en/` を増やしたため、Webサーバー設定によってはここが壊れます。

**段階2：内容を確定して公開する**

7. [open-questions.md](open-questions.md) の A1〜A5 を確定。
8. サイトリポジトリのローカル `.env` に追記（`.env.example` の `TAMOR_*` ブロックを参照）:

   ```
   TAMOR_OPERATOR_NAME="（確定した運営者名）"
   TAMOR_OPERATOR_NAME_EN="（英文表記）"
   TAMOR_TERMS_EFFECTIVE=2026-xx-xx
   TAMOR_PRIVACY_EFFECTIVE=2026-xx-xx
   TAMOR_FAQ_UPDATED=2026-xx-xx
   TAMOR_PAGES_PUBLISHED=true
   ```

9. **`php artisan tamor:export` を実行し、`public/` 配下の差分をコミットする。**
   静的配信なので、これをやらないと `.env` を直しても公開ページは草案のままです。
   書き出したHTMLを開き、運営者名・施行日が確定値になっていること、
   `<meta name="robots" content="index, follow">` になっていることを目視で確認します。
10. `public/sitemap.xml` に8URLを追記（例：日本語トップ 0.6、FAQ 0.5、規約・ポリシー 0.4、英語は各 -0.1）。
11. 本番へ反映（段階1と同じ方法）。**本番の `.env` にも同じ `TAMOR_*` を入れる**
    （会社サイトのフッター・トップ・`/privacy` から Tamor への導線は Laravel 側で
    `config('tamor.published')` を見て出し分けているため）。設定キャッシュを使っているなら
    `config:cache` も実行。
12. 公開後の確認（下記 2.3）。
13. 確認できたら App Store Connect の Privacy Policy URL / Support URL を設定（[README.md](README.md) の候補表）。

### 2.3 公開後のURL確認

```bash
for u in / /company /privacy /public-notice /contact \
         /apps/tamor/ /apps/tamor/faq.html /apps/tamor/terms.html /apps/tamor/privacy.html \
         /en /en/company /en/privacy \
         /en/apps/tamor/ /en/apps/tamor/faq.html /en/apps/tamor/terms.html /en/apps/tamor/privacy.html ; do
  printf '%-32s %s\n' "$u" "$(curl -s -o /dev/null -w '%{http_code}' "https://marcottlab.com$u")"
done
```

あわせて次を目視確認します。

- 4ページに「公開前の草案です」バナーが**出ていない**こと。
- 運営者名と施行日が「確認中」ではなく確定値になっていること。
- `curl -s https://marcottlab.com/apps/tamor/privacy.html | grep -i 'name="robots"'` が `index, follow` であること。
- **`/en` が 200 であること**（静的ディレクトリ `public/en/` に隠されていないこと）。
- 拡張子なしの `/apps/tamor/privacy` が `.html` へ 301 転送されること。
- 日英の切り替えリンクが対応するページへ移動すること。
- 会社サイトの `/privacy` が従来の本文のままで、Tamor ポリシーへの参照リンクが増えていること。
- スマートフォン実機で横スクロールが出ないこと。

### 2.4 ロールバック手順

| 状況 | 対応 |
| --- | --- |
| 内容に問題が見つかった（表示は正常） | `.env` を `TAMOR_PAGES_PUBLISHED=false` に戻し、**`php artisan tamor:export` を実行して書き出し直し、その差分をデプロイする**。静的配信のため `.env` を戻すだけでは公開ページは変わりません。急ぐ場合は `public/apps/tamor/` と `public/en/apps/tamor/` を削除すれば、Laravel のルートが草案版を返す状態に戻ります |
| 施行日・運営者名だけを訂正したい | 該当の `TAMOR_*` を直し、**`tamor:export` を実行して差分をデプロイ** |
| 英語トップ `/en` が 403 / 404 になった | Webサーバー設定が `public/en/` に負けています。Apache は `public/.htaccess` の `^(en\|apps\|en/apps)/?$` の行、nginx は同等の逃がしを確認。応急処置として `public/en/` を退避すれば直ります |
| コードに問題がある | 該当コミットを `git revert` して再デプロイ。既存ページへの変更は「`$robots` 変数の追加」「公開時のみ出る導線」「`/privacy` への参照1文」だけで、いずれも既存の表示を変えていないため、revert しても既存ページに影響はありません |
| sitemap を先に公開してしまった | `public/sitemap.xml` から該当URLを削除して再デプロイ |
| 書き出しが古いか分からない | `php artisan tamor:export --check`。ずれていれば一覧と終了コード 1 で知らせます |

本番でのサービス再起動やサーバー設定の変更は、この作業では必要ない想定ですが、
実際の構成（2.1 の 1〜5）を確認したうえで運用担当が判断してください。

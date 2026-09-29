#!/usr/bin/env python3
"""Generate the Shipaton submission TODO workbook for Tamor 1.0."""
from pathlib import Path

from openpyxl import Workbook
from openpyxl.styles import Alignment, Border, Font, PatternFill, Side
from openpyxl.utils import get_column_letter

OUTPUT = str(Path(__file__).resolve().parent.parent / "docs/release/shipaton-submission-todo.xlsx")

HEADER_FILL = PatternFill("solid", fgColor="1F3864")
HEADER_FONT = Font(bold=True, color="FFFFFF", size=11)
CATEGORY_FILLS = {
    "A. App Store 公開の確定": PatternFill("solid", fgColor="FFF2CC"),
    "B. 実購入・復元の検証": PatternFill("solid", fgColor="E2EFDA"),
    "C. 参加資格・Devpost下書き": PatternFill("solid", fgColor="DEEBF7"),
    "D. 応募素材（画像・動画・英文）": PatternFill("solid", fgColor="FCE4D6"),
    "E. 審査員用オファーコード": PatternFill("solid", fgColor="EDEDED"),
    "F. サポート／法務ページの公開": PatternFill("solid", fgColor="F4CCCC"),
    "G. 最終提出": PatternFill("solid", fgColor="D9E1F2"),
}
BORDER = Border(
    left=Side(style="thin", color="BFBFBF"),
    right=Side(style="thin", color="BFBFBF"),
    top=Side(style="thin", color="BFBFBF"),
    bottom=Side(style="thin", color="BFBFBF"),
)
WRAP = Alignment(wrap_text=True, vertical="top")

COLUMNS = [
    ("#", 5),
    ("カテゴリ", 26),
    ("タスク", 46),
    ("完了条件・証拠", 48),
    ("前提／依存", 30),
    ("現状（2026-09-26）", 34),
    ("担当", 12),
    ("期限（JST）", 16),
    ("参考リンク・ファイル", 44),
]

# 期限指針: Shipaton締切 2026-10-01 15:45 JST
ROWS = [
    # A. App Store 公開の確定
    (
        "A. App Store 公開の確定",
        "App Store Connect 上で審査結果を確認する（承認 or 差し戻し）",
        "『Ready for Distribution』または『Pending Developer Release』表示、\n審査差し戻しの場合は指摘内容を確定する",
        "App Store Connect にログインできること",
        "審査提出直後（本日 2026-09-26 に公開ボタンをクリック済）",
        "所有者",
        "24〜48h 以内に日次確認",
        "https://appstoreconnect.apple.com/apps/6814390528/distribution",
    ),
    (
        "A. App Store 公開の確定",
        "米国と日本の App Store で Tamor が実際にインストールできることを確認",
        "米国 Apple ID の端末／シークレット閲覧で公開 URL からダウンロード成功。\nストアURLをテキストで保存",
        "審査承認後、リリース処理完了",
        "未実施（Ready for Sale になり次第）",
        "所有者",
        "承認当日〜翌日",
        "docs/app-store-shipaton-execution-plan.html §07\nhttps://revenuecat-shipaton-2026.devpost.com/rules",
    ),
    (
        "A. App Store 公開の確定",
        "IAP『World 1 Full Depth』が Approved になっていることを確認",
        "IAP 一覧で Approved 表示。アプリと同じ提出に含まれていた履歴を確認",
        "初回IAPをアプリと同時提出済",
        "アプリと同時提出済（build 7）と想定。要ステータス確認",
        "所有者",
        "審査承認と同時",
        "https://appstoreconnect.apple.com/apps/6814390528/distribution/iaps/6814390656",
    ),
    (
        "A. App Store 公開の確定",
        "手動リリースなら『App のリリース』ボタンを押して公開状態にする",
        "App と IAP がいずれも Ready for Sale。ストアで検索表示され、購入導線が動く",
        "審査承認済",
        "審査次第",
        "所有者",
        "2026-09-29 中を目標",
        "docs/app-store-shipaton-execution-plan.html §07『承認から公開へ』",
    ),

    # B. 実購入・復元の検証
    (
        "B. 実購入・復元の検証",
        "Sandbox アカウントで World 1 Full Depth を実際に購入し、深度4〜6が解放されることを確認",
        "Sandbox 購入→アプリ側でエンタイトルメント有効化→深度4選択が可能になるスクリーンショット／動画",
        "Sandbox テスターを App Store Connect に登録済",
        "未検証（verification-1.0.md『残る作業 1』）",
        "所有者",
        "2026-09-28",
        "docs/release/verification-1.0.md",
    ),
    (
        "B. 実購入・復元の検証",
        "『購入を復元』が同一 Apple ID の別端末／再インストール後で機能することを確認",
        "アプリ再インストール後に『購入を復元』でエンタイトルメントが戻る。\n宝石は端末保存のみで復元されないことをUI上で確認",
        "実購入 or Sandbox 購入完了",
        "未検証（verification-1.0.md）",
        "所有者",
        "2026-09-28",
        "Claude outputs/Tamor_Review_2_Reinstall_and_Restore.mp4（参考）",
    ),
    (
        "B. 実購入・復元の検証",
        "RevenueCat ダッシュボードで実トランザクションが記録されることを確認",
        "RevenueCat の Customer 画面に対象 App User ID のトランザクションが表示",
        "実購入 or Sandbox 購入完了、App Store Connect API キーが Valid",
        "資格情報は Valid 確認済（verification-1.0.md）。トランザクション未確認",
        "所有者",
        "2026-09-28",
        "https://app.revenuecat.com/projects/dff763eb/apps/app45c907c83a",
    ),

    # C. 参加資格・Devpost下書き
    (
        "C. 参加資格・Devpost下書き",
        "Shipaton 2026 公式規約を提出前に再読し、参加資格・カテゴリ・除外事項を確認",
        "所有者・チームの参加資格に問題なし、通常ゲームカテゴリで提出可能と確定",
        "-",
        "計画時に確認済。提出直前に再確認要",
        "所有者",
        "提出直前",
        "https://revenuecat-shipaton-2026.devpost.com/rules",
    ),
    (
        "C. 参加資格・Devpost下書き",
        "Devpost で Tamor の応募エントリを作成（下書きで良い）",
        "エントリ URL を取得。所有者・カテゴリ（Best Game 主軸）・連絡先・チーム構成を入力",
        "Devpost アカウント",
        "未作成",
        "所有者",
        "2026-09-27",
        "https://revenuecat-shipaton-2026.devpost.com/",
    ),
    (
        "C. 参加資格・Devpost下書き",
        "RevenueCat Project ID を Devpost に入力（公開SDKキー・秘密鍵と取り違えない）",
        "Project ID『dff763eb』を Devpost の該当欄に貼付",
        "Devpost エントリ作成済",
        "ID は既知：dff763eb（verification-1.0.md）",
        "所有者",
        "2026-09-27",
        "https://app.revenuecat.com/projects/dff763eb",
    ),
    (
        "C. 参加資格・Devpost下書き",
        "応募カテゴリの追加候補（デザイン系など）を確認し、応募可否を判断",
        "追加応募するカテゴリを確定 or 見送りを明記",
        "規約再確認",
        "未確定",
        "所有者",
        "2026-09-27",
        "docs/app-store-shipaton-execution-plan.html §08",
    ),

    # D. 応募素材
    (
        "D. 応募素材（画像・動画・英文）",
        "1024×1024 の App アイコン（不透明PNG）を応募用にコピー",
        "アルファなし 1024x1024 PNG を Devpost にアップロード",
        "-",
        "ビルド7でアルファ除去済（device-testflight-2026-09-22.md）",
        "所有者",
        "2026-09-27",
        "Assets.xcassets/AppIcon.appiconset/AppIcon.png",
    ),
    (
        "D. 応募素材（画像・動画・英文）",
        "1179×2556（iPhone 15/16/17 Pro）の英語スクリーンショットを 1 枚以上準備",
        "端末フレームなし、公開版UIと一致。Devpost にアップロード",
        "英語UIビルド",
        "release-1.0/iphone-17-pro-release-home-en.png など既存あり。Devpost規格の再書出しが必要か要確認",
        "所有者",
        "2026-09-28",
        "docs/screenshots/release-1.0/",
    ),
    (
        "D. 応募素材（画像・動画・英文）",
        "紹介動画（90〜110秒、2分未満）を撮影し、YouTube or Vimeo に公開",
        "英語字幕付き。0-15s ジュエルリング、15-55s 4ゲーム、55-75s カラット成長、75-90s 無料範囲と購入、末尾にアプリ名とストアURL",
        "実機Release、購入導線",
        "未撮影。既存レビュー動画は参考のみ",
        "所有者",
        "2026-09-29",
        "docs/app-store-shipaton-execution-plan.html §08『動画の構成案』",
    ),
    (
        "D. 応募素材（画像・動画・英文）",
        "英語紹介文（Devpost 応募本文）を作成",
        "宝石収集の狙い、4ゲーム、Metal 光表現、RevenueCat 用途、開発の工夫を英文で執筆",
        "docs/release/claude/store-listing.md の英文",
        "英文ストア掲載文は準備済（store-listing.md）。Devpost 用に短縮／編集要",
        "所有者",
        "2026-09-28",
        "docs/release/claude/store-listing.md",
    ),
    (
        "D. 応募素材（画像・動画・英文）",
        "審査員向け『使い方 / 有料機能の触り方』を英文で用意",
        "無料範囲、購入画面の場所、コード引換手順、深度解放後の遊び方の説明文",
        "-",
        "英文レビューノートあり（app-review-notes.md）を Devpost 用に整形要",
        "所有者",
        "2026-09-29",
        "docs/release/claude/app-review-notes.md",
    ),

    # E. オファーコード
    (
        "E. 審査員用オファーコード",
        "App Store Connect で World 1 Full Depth のオファーコード設定を作成",
        "対象商品／地域／利用資格／有効期限（2026-10-31 案）を設定、コード発行画面まで到達",
        "App が Ready for Distribution、IAP が Approved",
        "審査結果次第（A の完了後）",
        "所有者",
        "承認当日",
        "https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/create-offer-codes-for-in-app-purchases",
    ),
    (
        "E. 審査員用オファーコード",
        "本番用オファーコードを必要数だけ発行し、検証用と応募用を分離",
        "検証済コード（アプリで引換確認済）と、審査員に渡す未使用コードの2種を管理",
        "オファーコード設定作成済、実機での引換テスト成功",
        "未実施",
        "所有者",
        "2026-09-30 午前",
        "docs/app-store-shipaton-execution-plan.html §08",
    ),
    (
        "E. 審査員用オファーコード",
        "コード引換フロー（Apple 生成URL→アプリ復帰→CustomerInfo更新）を実機で確認",
        "引換後に深度4が解放される様子をスクリーンショットで保存",
        "本番コード発行済",
        "未実施",
        "所有者",
        "2026-09-30",
        "docs/release/verification-1.0.md",
    ),
    (
        "E. 審査員用オファーコード",
        "Devpost の『有料機能アクセス』欄にコードと使い方（英文）を記入",
        "未使用コード＋Apple 引換URL＋アプリ内での確認手順が Devpost に記載",
        "未使用コード確保、Devpost エントリ",
        "未記入",
        "所有者",
        "2026-09-30",
        "https://revenuecat-shipaton-2026.devpost.com/rules",
    ),

    # F. サポート／法務ページ
    (
        "F. サポート／法務ページの公開",
        "MarcottLab サイトの『公開ゲート 5 項目』（運営者名 日英・規約/ポリシー/FAQ 日付）を確定",
        ".env の TAMOR_OPERATOR_NAME 等 5 項目が入力済、公開扱いとなる状態",
        "契約主体（法人か個人か）と App Store 販売元表示の整合",
        "未確定（open-questions.md A1〜A5）",
        "所有者",
        "2026-09-28",
        "docs/release/support-site/open-questions.md",
    ),
    (
        "F. サポート／法務ページの公開",
        "サポート／プライバシー／利用規約の公開URLを本番へデプロイ",
        "https://marcottlab.com/apps/tamor/... と /en/apps/tamor/... がHTTP 200",
        "公開ゲート開放",
        "デプロイ未実施（handoff-codex-2026-09-22.md）",
        "所有者",
        "2026-09-28",
        "docs/release/support-site/verification-and-deploy.md",
    ),
    (
        "F. サポート／法務ページの公開",
        "App Store Connect の『プライバシーポリシーURL』『サポートURL』欄を公開URLに更新",
        "App 情報画面に公開URLが保存され、審査承認時のメタデータと一致",
        "F の公開デプロイ完了",
        "現状のリンク値を要確認（審査提出時に暫定URLで通っている場合は差替）",
        "所有者",
        "承認前まで",
        "docs/release/claude/store-listing.md",
    ),
    (
        "F. サポート／法務ページの公開",
        "アプリ設定画面のプライバシー／サポートURLと本番URLが一致",
        "実機で設定画面のリンクをタップして正しいページが開く",
        "F の公開デプロイ完了",
        "35721ab コミットでサポートリンク追加済み。URL 実値の最終確認が必要",
        "所有者",
        "承認前まで",
        "commit 35721ab (Prepare iPhone release with jewel spotlight and support links)",
    ),

    # G. 最終提出
    (
        "G. 最終提出",
        "Devpost 応募フォームに、ストアURL・Project ID・画像・動画・オファーコード・英文を全て埋める",
        "全必須欄に有効値が入り、下書きプレビューを所有者が確認",
        "A〜F 完了",
        "未実施",
        "所有者",
        "2026-09-30",
        "https://revenuecat-shipaton-2026.devpost.com/",
    ),
    (
        "G. 最終提出",
        "『Submit』ボタンを押し、応募状態が Submitted になったことを確認",
        "Devpost で Submitted 表示、応募URLと完了画面のスクリーンショットを保存",
        "全欄入力完了",
        "未実施",
        "所有者",
        "2026-09-30 中（余裕もって24h前）",
        "docs/app-store-shipaton-execution-plan.html §08『応募完了の確認』",
    ),
    (
        "G. 最終提出",
        "応募後 10-01 15:45 JST までに、ストア・動画・コード・支援サイトへのアクセスが維持されているか最終点検",
        "全URLが応答、コードが未失効、動画が公開のまま",
        "提出済",
        "-",
        "所有者",
        "2026-10-01 12:00 JST",
        "https://revenuecat-shipaton-2026.devpost.com/rules",
    ),
    (
        "G. 最終提出",
        "応募完了記録を Git に保存（応募URL・スクショ・提出時刻）",
        "docs/release/ 配下に完了記録ファイルを追加してコミット",
        "提出済",
        "-",
        "所有者",
        "2026-10-01",
        "docs/release/",
    ),
]


def summary_sheet(wb):
    ws = wb.create_sheet("概要", 0)
    ws.column_dimensions["A"].width = 30
    ws.column_dimensions["B"].width = 90

    title = ws.cell(row=1, column=1, value="Tamor Shipaton 2026 応募 TODO")
    title.font = Font(bold=True, size=16, color="1F3864")
    ws.merge_cells(start_row=1, start_column=1, end_row=1, end_column=2)

    rows = [
        ("応募締切", "日本時間 2026-10-01 15:45（2026-09-30 23:45 PDT）"),
        ("作成日", "2026-09-26"),
        ("残日数の目安", "約 5 日（審査時間・差し戻し対応の余裕を考慮）"),
        ("対象アプリ", "Tamor 1.0（Bundle ID: com.marcottlab.tamor / App ID: 6814390528）"),
        ("最新ビルド", "1.0 (7) — 2026-09-23 コミット 583815a『Prepare TestFlight build 7 with final icon』"),
        ("直前アクション", "App Store Connect で『公開』ボタンをクリック（2026-09-26）"),
        ("RevenueCat Project ID", "dff763eb（App: app45c907c83a、Entitlement: world1_full_depth）"),
        ("有料機能", "非消耗型 IAP『World 1 Full Depth』 (com.marcottlab.tamor.world1.depth / 400円 / $1.99)"),
        ("応募の完了条件", "ストア公開・実購入動作・Devpost 提出・審査員用アクセスコード発行・素材揃え"),
        ("参考ドキュメント", "docs/app-store-shipaton-execution-plan.html / docs/release/verification-1.0.md / docs/release/claude/handoff.md"),
    ]
    for i, (k, v) in enumerate(rows, start=3):
        c1 = ws.cell(row=i, column=1, value=k)
        c2 = ws.cell(row=i, column=2, value=v)
        c1.font = Font(bold=True)
        c1.alignment = WRAP
        c2.alignment = WRAP
        c1.border = BORDER
        c2.border = BORDER

    ws.cell(row=len(rows) + 5, column=1, value="凡例").font = Font(bold=True)
    legend = [
        ("A. App Store 公開の確定", "審査結果とストア公開の実確認"),
        ("B. 実購入・復元の検証", "Sandbox または本番での購入動作の証拠取り"),
        ("C. 参加資格・Devpost 下書き", "応募エントリ作成、Project ID 記入、カテゴリ確認"),
        ("D. 応募素材（画像・動画・英文）", "アイコン・スクリーンショット・動画・英文"),
        ("E. 審査員用オファーコード", "IAP オファーコード発行と Devpost への記入"),
        ("F. サポート／法務ページの公開", "MarcottLab サイトの本番デプロイと URL 一致"),
        ("G. 最終提出", "Devpost で Submit → 完了記録の保存"),
    ]
    start = len(rows) + 6
    for i, (name, desc) in enumerate(legend):
        r = start + i
        c1 = ws.cell(row=r, column=1, value=name)
        c2 = ws.cell(row=r, column=2, value=desc)
        fill = CATEGORY_FILLS.get(name)
        if fill:
            c1.fill = fill
        c1.alignment = WRAP
        c2.alignment = WRAP
        c1.border = BORDER
        c2.border = BORDER


def todo_sheet(wb):
    ws = wb.create_sheet("応募TODO")
    ws.freeze_panes = "A2"

    for idx, (header, width) in enumerate(COLUMNS, start=1):
        cell = ws.cell(row=1, column=idx, value=header)
        cell.font = HEADER_FONT
        cell.fill = HEADER_FILL
        cell.alignment = Alignment(wrap_text=True, vertical="center", horizontal="center")
        cell.border = BORDER
        ws.column_dimensions[get_column_letter(idx)].width = width

    for i, row in enumerate(ROWS, start=1):
        category, task, evidence, prereq, status, owner, deadline, ref = row
        values = [i, category, task, evidence, prereq, status, owner, deadline, ref]
        fill = CATEGORY_FILLS.get(category)
        for col, value in enumerate(values, start=1):
            cell = ws.cell(row=i + 1, column=col, value=value)
            cell.alignment = WRAP
            cell.border = BORDER
            if col == 2 and fill:
                cell.fill = fill

    for row_index in range(2, len(ROWS) + 2):
        ws.row_dimensions[row_index].height = 78


def main():
    wb = Workbook()
    default = wb.active
    wb.remove(default)
    summary_sheet(wb)
    todo_sheet(wb)
    wb.save(OUTPUT)
    print(f"wrote {OUTPUT}")


if __name__ == "__main__":
    main()

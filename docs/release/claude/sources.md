# 出典一覧 / Sources(2026-09-21 取得)

公式一次資料のみ。要約は Claude によるもので、原文を必ず確認してください。「未確認」は今回取得できなかった、または記載を見つけられなかった点です。

## Apple

1. App privacy details on the App Store — https://developer.apple.com/app-store/app-privacy-details/
   「収集(collect)」=端末外へ送信し、リクエストの即時処理に必要な期間を超えてアクセス可能にすること。第三者パートナー(SDK を含む)の収集も申告対象で、回答の正確性は開発者の責任。Purchase History / User ID / Device ID 等のデータ型定義、任意開示の4条件、トラッキングと「リンク」の定義。
2. Third-party SDK requirements — https://developer.apple.com/support/third-party-SDK-requirements/
   一覧に RevenueCat / Purchases は掲載なし(取得時点)。SDK が含むコードについて開発者が責任を負う旨の記載。
3. Privacy manifest files — https://developer.apple.com/documentation/bundleresources/privacy-manifest-files
4. Describing data use in privacy manifests — https://developer.apple.com/documentation/bundleresources/describing-data-use-in-privacy-manifests
   Xcode のプライバシーレポートを App Store Connect の回答時に参照するよう案内。Manifest が回答を代替すると明記した文は見つからず(=回答は別途必要、という理解。明文は**未確認**)。
5. App Store Review Guidelines — https://developer.apple.com/app-store/review/guidelines/
   2.1(a)(b)、2.2、2.3.1(a)、2.3.2、2.3.3、2.3.7、2.3.10、3.1.1(復元手段)、4.1、5.1.1(i)(プライバシーポリシーをメタデータとアプリ内の両方に)、5.1.2(i)。**5.2 節は本文を取得できず未確認。**
6. App information (App Store Connect) — https://developer.apple.com/help/app-store-connect/reference/app-information/ (名前 2–30 文字、サブタイトル 30 文字、プライバシーポリシーURL必須)
7. Platform version information — https://developer.apple.com/help/app-store-connect/reference/platform-version-information/ (プロモーションテキスト170、説明4000、キーワード100バイト、サポートURL必須、審査メモ4000バイト)
8. In-app purchase information — https://developer.apple.com/help/app-store-connect/reference/in-app-purchase-information/ (表示名 2–30、説明 45 文字、審査用スクリーンショット必須)
9. Submit an in-app purchase — https://developer.apple.com/help/app-store-connect/manage-submissions-to-app-review/submit-an-in-app-purchase/ (初回の IAP は新しいアプリバージョンと一緒に提出)
10. Screenshot specifications — https://developer.apple.com/help/app-store-connect/reference/screenshot-specifications/ (iPhone 6.9"、iPad 13" は iPad 対応なら必須。6.9" の必須条件の正確な文言は**未確認**)
11. Complying with encryption export regulations — https://developer.apple.com/documentation/security/complying-with-encryption-export-regulations
12. Export compliance documentation — https://developer.apple.com/help/app-store-connect/reference/export-compliance-documentation-for-encryption/
13. Age ratings — https://developer.apple.com/help/app-store-connect/reference/age-ratings-values-and-definitions/ 、https://developer.apple.com/news/?id=ks775ehf
14. Set a price for an in-app purchase — https://developer.apple.com/help/app-store-connect/manage-in-app-purchases/set-a-price-for-an-in-app-purchase/ (基準ストアフロントから他地域の価格を自動算出。¥400 に対応する米ドル額の公表値はなし)
15. Localizing and varying text with a string catalog — https://developer.apple.com/documentation/xcode/localizing-and-varying-text-with-a-string-catalog
16. CFBundleDevelopmentRegion — https://developer.apple.com/documentation/bundleresources/information-property-list/cfbundledevelopmentregion
17. Testing localizations when running your app — https://developer.apple.com/documentation/xcode/testing-localizations-when-running-your-app

## RevenueCat

18. Apple App Privacy(RevenueCat 公式ガイド) — https://www.revenuecat.com/docs/platform-resources/apple-platform-resources/apple-app-privacy
    Purchase History は RevenueCat 利用時に必須(目的: Analytics と App Functionality)。識別子はカスタム App User ID や広告ID連携を使う場合に申告。匿名IDで個人を特定できないなら「リンクなし」を選択可。IDFV への言及なし。
19. purchases-ios 5.90.2 の Privacy Manifest — https://raw.githubusercontent.com/RevenueCat/purchases-ios/5.90.2/Sources/PrivacyInfo.xcprivacy
    NSPrivacyTracking=false、収集データ型は PurchaseHistory(非リンク・非トラッキング・AppFunctionality)のみ、Required Reason API は UserDefaults CA92.1。
20. purchases-ios 5.90.2 `HTTPClient.swift` — https://raw.githubusercontent.com/RevenueCat/purchases-ios/5.90.2/Sources/Networking/HTTPClient/HTTPClient.swift
    既定ヘッダに X-Platform-Version、X-Platform-Device、X-Client-Version、X-Client-Build-Version、X-Client-Bundle-ID、X-Preferred-Locales、X-Storefront 等。`identifierForVendor` が取得できる場合は `X-Apple-Device-Identifier` として IDFV を付加(Claude が原文を再取得して確認)。
21. リリース 5.90.2 — https://github.com/RevenueCat/purchases-ios/releases/tag/5.90.2
22. Identifying customers(匿名ID) — https://www.revenuecat.com/docs/customers/identifying-customers
23. Customer attributes($idfa/$idfv/$ip 等の予約属性) — https://www.revenuecat.com/docs/customers/customer-attributes
24. RevenueCat Privacy Policy — https://www.revenuecat.com/privacy (処理者としての立場、米国の AWS に保存との説明)
25. RevenueCat DPA — https://www.revenuecat.com/dpa
26. purchases-ios LICENSE(MIT、タグ 5.90.2) — https://raw.githubusercontent.com/RevenueCat/purchases-ios/5.90.2/LICENSE

## リポジトリ内で確認した事実

- `Tamor.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved`: purchases-ios 5.90.2(revision 4faa17c4…)。
- `Sources/App/PurchaseStore.swift`: `Purchases.configure(withAPIKey:)`、`customerInfo()`、`offerings()`、`purchase(package:)`、`restorePurchases()` のみ使用。App User ID の指定、属性設定、アトリビューション、`collectDeviceIdentifiers()` の呼び出しはなし(2026-09-21 07:2x UTC 時点の作業ツリー。Codex が同ファイルを変更予定のため、公開前に再確認)。
- `Sources/PrivacyInfo.xcprivacy`: 収集データ型は空、UserDefaults(CA92.1)と SystemBootTime(35F9.1)を宣言。

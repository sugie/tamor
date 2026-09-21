# Tamor Privacy Policy (DRAFT – English)

> **Status: draft (2026-09-21, prepared by Claude). Requires human review before publication. Not legal advice.**
> `[TO CONFIRM]` marks open items. Assumes Tamor 1.0 ships without CloudKit/iCloud sync, stores game data only as on-device JSON, has no accounts, ads or analytics SDK, and sells one non-consumable through RevenueCat SDK 5.90.2.

---

Last updated: [TO CONFIRM: publication date]
Provider: [TO CONFIRM: seller name as shown on the App Store]
Contact: [TO CONFIRM: email address or contact form URL]

This policy explains how the iOS / iPadOS app "Tamor" (the "App") handles information.

## 1. Summary

- The App has no account registration or login. It does not ask for your name, email address, phone number, location, contacts, photos, microphone or camera.
- The App shows no ads and contains no advertising or behavioral analytics SDK. It does not track you as defined by Apple's App Tracking Transparency framework.
- Your game progress and gem collection are stored only on your device. They are not sent to the developer's servers or to iCloud.
- To process the in-app purchase (unlocking World 1 Depths 4–6) and to check its status, the App uses Apple's App Store and RevenueCat, Inc., a purchase infrastructure provider. The information listed in Section 3 is sent to RevenueCat.

## 2. Information stored on your device (not sent to the developer)

- Gems you have earned, the result of each play (depth, grade, time, date) and the ring's display state: JSON files in the App's data area (`Application Support/Tamor/`)
- The checkpoint of an interrupted Crusher Room run: a file in the same folder
- Settings such as rendering quality, and a random identifier the App generates for this device: the App's preferences (UserDefaults). In version 1.0 this identifier is not transmitted. [TO CONFIRM against the release build]

This data is erased when you delete the App. **Version 1.0 has no cloud backup or sync, so your gem collection cannot be recovered after deleting the App or moving to a new device** (you can keep your own copy using "Export Save Data" in Settings [TO CONFIRM: whether this feature remains in 1.0]). Whether the App's data is included in a full-device backup depends on your device settings and Apple's behavior.

## 3. Information sent off the device (in-app purchase)

The App uses the RevenueCat SDK (purchases-ios 5.90.2) for purchasing, restoring purchases and checking purchase status. When the App launches, returns to the foreground or shows the purchase screen, the following is sent to RevenueCat's servers:

| Information | Details | Purpose |
| --- | --- | --- |
| Purchase information | App Store transaction/receipt data, product ID, purchase and restore status | Validating purchases, determining the unlock, restoring, fraud prevention |
| Anonymous app user ID | A random ID generated on the device by the RevenueCat SDK; not associated with your name, email or similar | Managing purchase status |
| Identifier for Vendor (IDFV) | A per-device identifier Apple issues for apps from the same developer; the SDK attaches it to its requests | Operating the purchase infrastructure (by RevenueCat) |
| Technical device and app information | Device model, OS version, app version/build/bundle ID, preferred languages, App Store country/region code, SDK version, sandbox flag and similar | Operating the purchase infrastructure, compatibility, troubleshooting |
| IP address | Received by the server as part of any internet connection | Establishing the connection, security |

- The advertising identifier (IDFA) is not collected or sent. No contact information such as an email address is passed to RevenueCat.
- The developer can see purchase status and aggregate figures tied to the anonymous ID in RevenueCat's dashboard, and does not link them to an identified person.
- Payment itself is handled by Apple. Payment details such as card numbers are never shared with the developer or RevenueCat. Apple's handling of information is governed by Apple's privacy policy.
- RevenueCat acts as a processor on the developer's behalf and states that data is stored on servers in the United States, so the information above is transferred to the United States. See RevenueCat's privacy policy: https://www.revenuecat.com/privacy [TO CONFIRM: DPA status; wording required under applicable law such as GDPR/APPI should be reviewed by a professional]

These requests are made even if you only play the free range (Depths 1–3), because the App needs to check purchase status. [TO CONFIRM against the release build]

## 4. How the information is used

Only to (1) provide, validate and restore the in-app purchase, (2) prevent fraud, (3) investigate purchase problems and answer support requests, and (4) total sales. It is not used for advertising or profiling and is not sold.

## 5. Sharing

Information is not provided to third parties except where required by law. The transfers to RevenueCat and Apple in Section 3 are limited to what is needed to provide the purchase feature.

## 6. Retention and deletion

- On-device data: until you delete the App.
- Purchase-related data at RevenueCat: [TO CONFIRM: retention policy]. To request deletion, contact us at the address above. Because only an anonymous ID is held, we may ask for information needed to locate your data. [TO CONFIRM: procedure]

## 7. Children

The App is not directed specifically at children, and it does not ask anyone for personally identifying information. Parents can restrict in-app purchases with Screen Time. [TO CONFIRM: age rating; not in the Kids category]

## 8. Changes

Changes will be posted on this page. Material changes (for example, adding cloud storage in a future version) will also be announced in the App's release notes.

## 9. Contact

[TO CONFIRM: provider name, contact and whether an address must be shown]

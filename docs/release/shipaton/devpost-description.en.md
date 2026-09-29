# Devpost description (English) — DRAFT

> Fill the `[TODO]` items before submitting. Paste into the Devpost project story / text description.

## Tagline
Break glass, collect gems: four skill mini-games that grow a ring of real-time Metal-rendered jewels.

## What it is
Tamor is an iPhone game about earning gems through short, skill-based mini-games and displaying them on a ring of twelve pedestals. The size of each gem (0.10–20.00 ct) is decided by how well you play, never by chance: no stamina, no ads, no random draws, no account.

## Features and functionality
- **Four gems, four mini-games**
  - Diamond — *Glass Break*: tap each red dot before time runs out to break through thick glass.
  - Ruby — *Glass Trace*: follow a green dot with your finger; three cracks end the run.
  - Sapphire — *Kurukuru World*: find and tap pairs of gems spinning the same way.
  - Obsidian — *Crusher Room*: break as many glass plates as you can in 10 seconds; hitting the glowing weak point scores higher.
- **Depths and carats:** each gem has depths 1–6. Clearing a depth opens the next and raises the carat ceiling. Runs are graded B / A / S. Every gem you earn stays in the Gem Box; the largest of each kind is shown on the ring.
- **Light and material:** refraction and color absorption inside each gem, window light, and cracking, shattering glass rendered in real time with SwiftUI + Metal. Optional ray tracing on supported devices.
- **Collection interaction:** tap a gem to bring it into a spotlight, swipe to rotate it, tap again to return it. The ring tilts with the device (can be disabled; respects Reduce Motion).
- **Local-first:** progress and gems are stored on the device. Japanese and English UI.

## How RevenueCat is used
Tamor is free to download; Depths 1–3 (gems up to 3.00 ct) are free forever. One **non-consumable in-app purchase — "World 1 Full Depth"** (`com.marcottlab.tamor.world1.depth`) unlocks *access* to Depths 4–6. It never sells gems: the 20.00 ct gem still requires clearing earlier depths and three consecutive S grades.

RevenueCat handles the whole purchase layer:
- **Offerings** deliver the product and its localized price (from StoreKit) to the paywall.
- **Entitlement** `world1_full_depth` gates the deeper depths; the app listens to `CustomerInfo` updates so a purchase, an offer-code redemption, or a refund is reflected immediately, and a network error never removes an existing entitlement.
- **Restore Purchases** brings the unlock back after reinstall or on another device with the same Apple Account (gems are stored locally and are not restored — this is stated in the app).

Why RevenueCat: a one-time unlock is simple on paper, but entitlement state, restore, refunds and offer codes are where hand-rolled StoreKit code breaks. RevenueCat let a solo developer ship those correctly and see real transactions in one dashboard.

## Built with
Swift, SwiftUI, Metal, StoreKit 2, RevenueCat SDK (Purchases 5.90.2).

## Challenges
- Making glass shatter and gems refract convincingly in real time while staying smooth on an iPhone 12 mini; the game rules and hit-testing never change with rendering quality.
- Keeping a fair progression: money unlocks a *range of challenge*, never the result.

## Links
- App Store: [TODO: US App Store URL]
- Demo video: [TODO: YouTube URL]
- Support / Privacy: [TODO: URLs]
- RevenueCat Project ID: `dff763eb`

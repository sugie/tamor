# Devpost entry plan — Tamor (DRAFT, 2026-09-29)

Deadline: 2026-09-30 23:45 PDT = **2026-10-01 15:45 JST**. Target: submit by 9/30 daytime (JST).
Form structure follows Shipaton's official submission guide (5 steps). `[TODO]` = owner input. Devpost advises against AI-written descriptions: **rewrite the description below in your own voice, and fill in the build story yourself.**

## Step 1 — Team
Solo entry (owner). Add nobody else unless there is a co-developer.

## Step 2 — Project overview
| Field | Entry |
| --- | --- |
| Project name | **Tamor** (same as the App Store listing; store name is "Tamor - ジュエルリング") |
| Tagline | Break glass, chase light, and grow a ring of real-time jewels with four skill mini-games. |
| Thumbnail | 3:2 JPG/PNG. Suggested: ring with gems on the left + Crusher glass shattering on the right, no text. `[TODO: export 1500×1000]` |

## Step 3 — Project details

### Description (headings + short paragraphs; covers the 7 required points)

**The problem**
Casual games either gate rewards behind luck (gacha) or stamina timers. I wanted a collection game where what you own is exactly what you earned with your hands.

**Who it's for**
Mobile players who enjoy short, replayable reflex and observation challenges, and who like collecting and visual polish. Japanese and English UI.

**What it does**
Tamor is a gem-collecting game for iPhone. Four gems, four mini-games: Diamond (Glass Break — tap red dots before time runs out), Ruby (Glass Trace — follow a moving dot; three cracks end the run), Sapphire (Kurukuru World — tap pairs of gems that spin the same way), Obsidian (Crusher Room — break as many glass plates as possible in 10 seconds, hitting weak points for a higher grade). Each result awards a gem whose carat weight (0.10–20.00 ct) reflects how well you played. Gems live on a ring of twelve pedestals; tap one to inspect it in a spotlight and rotate it. Progress is stored on the device.

**How it makes money (RevenueCat)**
Free download; Depths 1–3 (up to 3.00 ct) are free forever. One non-consumable purchase, "World 1 Full Depth", unlocks *access* to Depths 4–6. It never sells gems: the 20.00 ct gem still needs clearing earlier depths and three consecutive S grades. No ads, no stamina, no random draws. RevenueCat provides the Offering/price, the `world1_full_depth` entitlement, live entitlement updates (purchase, offer-code redemption, refund), and Restore Purchases.

**What makes it different**
- Carats come from skill, not chance; money buys a range of challenge, not outcomes.
- Real-time Metal rendering: refraction and color absorption in the gems, window light, cracking and shattering glass.
- Four distinct skill checks in one collection loop.

**Categories I'm entering**
Best Game (primary). Design Award (secondary) — see the category fields below. `[TODO: decide on extra categories]`

**Build story, challenges, learnings, future plans**

*Where it started.* In early September, Apple announced the iPhone 18 with the A20 chip, with a stronger GPU and Neural Engine. That launch inspired me to see how beautiful I could make a gem on a phone. I built a gem rendering engine in Metal, and Tamor grew around it.

*What I built.* The rendering is the heart of the app: refraction and color absorption inside each gem, window light, and glass that cracks and shatters, all drawn in real time with Metal. On supported newer iPhones you can switch on ray tracing for the selected gem.

*The hardest part.* I designed the visuals for the newest chips, then had to make them run on much weaker ones. Most of the work was deciding what to thin out: fewer glass fragments, particles and reflections on lower-power devices, while keeping the rules, timing, hit-testing and rewards identical. A gem earned on an old phone must be worth the same as one earned on a new phone. I tested on an iPhone 12 mini as my low-end device.

*What I learned.* Rich rendering and broad device support are a design problem, not a last-minute optimization. Also, for a paid unlock, verifying purchase and restore on a real store build matters more than any mock.

*What's next.* More gems and a second world, plus richer ray-traced effects as more devices support them. `[TODO: edit in your own words; add anything you tried on newer devices only if you actually tested it]`

### Technology tags (max 25)
`RevenueCat`, `Swift`, `SwiftUI`, `Metal`, `StoreKit`, `iOS`, `iPhone`, `Xcode`, `Game`, `In-App Purchases`, `Purchases SDK`, `TestFlight`

### App Store link
`[TODO: US App Store URL]` — open it in a private window and confirm it works from the US before submitting.

### Images
- App icon 1024×1024 (opaque PNG): `Assets.xcassets/AppIcon.appiconset/AppIcon.png`
- Screenshots: at least one **1179×2556, no device frame**; suggest 4–5 (ring, Glass Break, Crusher, gem spotlight, paywall). Source: `docs/screenshots/release-1.0/` — re-export if not exactly 1179×2556. Do not put prices in images.

### Demo video
YouTube (unlisted is fine), under 2:00 — script in [demo-video-script.en.md](demo-video-script.en.md). Cover: elevator pitch, core experience, monetization, target categories. No copyrighted music.
`[TODO: YouTube URL]`

## Step 4 — Additional information

| Field | Entry |
| --- | --- |
| RevenueCat Project ID | `dff763eb` |
| Promo code / judge access | Offer code `SHIPATON2026`, redeem link `https://apps.apple.com/redeem?ctx=offercodes&id=6814390528&code=SHIPATON2026` (free, up to 500 uses, valid to 2026-12-31). Full text: [judge-access.en.md](judge-access.en.md) |

### Best Game — category fields
- **Gameplay loop:** pick gem + depth → 10–60 s skill mini-game → graded result (B/A/S) → gem with carat weight added to the ring/Gem Box → next depth opens.
- **Progression / replayability:** 6 depths per gem; carat ceiling rises with depth; 20.00 ct requires three consecutive S grades at Depth 6; smaller gems stay collected while the ring shows the largest of each kind.
- **Art direction:** dark, window-lit "jewel room"; physically motivated refraction and absorption; glass that cracks and shatters. Rendered in real time in Metal.
- **Monetization justification:** one-time unlock of deeper difficulty. Fits a skill game: no luck-based sales, no energy, results still have to be earned.

### Design Award — category fields (if entered)
Craft points to cite: gem spotlight transition (same-scale move to center, swipe-rotate, tap to return), device-tilt ring parallax with a setting and Reduce Motion support, Metal glass shatter, consistent JA/EN UI. `[TODO: add 1–2 sentences on a detail you're proud of]`

### Categories I recommend skipping
- **HAMM:** requires business model + conversion/revenue data; you likely have little data this soon.
- **#BuildInPublic:** needs a public posting trail; only enter if you actually posted along the way (`[TODO: check]`).
- **Peace Prize / Catvertising / Next Gen / sponsor awards:** don't fit.
- **Grand Prize:** needs launch traction metrics; optional, decide after seeing your numbers.

## Step 5 — Review and submit
Checklist: store link works in a private window · video plays without login · promo code redeems (test once with an account that hasn't purchased) · icon and screenshot sizes exact · status shows **"Submitted and 5/5 steps done"** · save the submission URL and a screenshot.

## Flags before you submit
- **AI-generated assets:** the asset rights note says gem imagery was AI-generated. Check the Shipaton rules on originality/AI use and the asset inventory ([asset-rights-inventory.md](../claude/asset-rights-inventory.md)) and state it honestly in the description if required.
- **Only claim what exists:** no World 2 content, no cloud sync, no "20 ct is purchasable".
- Re-read the official rules right before submitting: https://revenuecat-shipaton-2026.devpost.com/rules

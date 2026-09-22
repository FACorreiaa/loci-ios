# Slice 10: In-season band and sign-in HIG pass

## In-season band (web: Dashboard/InSeasonBand)
Sits under the Discover hero, where web puts it between the desk hero and the news band.

| Piece | Web source | Service | RPC → fields sent |
|---|---|---|---|
| Curated picks for the month | `lib/dashboard/seasons.ts` | — | Same table, `Features/Discover/Model/SeasonalPicks.swift` |
| "planned this week" overlay | `useTrendingDiscoveries(8)` | `DiscoverService` | `GetTrending{limit: 8}`; missing or failing → curated table alone |
| Merge and order | `buildInSeasonItems` | — | planned picks first, then table order, then trending cities not in season; max 12; no repeated ids |
| Tap a chip | `requestHeroPrompt` | — | Puts `Plan N days in <city> for <hook>` in the search box; nothing runs |

Motion:
- One linear loop of `max(30, 6 × items)` seconds, as web. Driven by `TimelineView(.animation)`; the offset is a pure read of the clock, nothing is written per frame.
- Two copies of the content with the gap between and after, so the seam lands exactly (web: `padding-inline-end == gap`).
- A finger on the strip holds it still; lifting resumes from the same spot (web: hover/focus pause).
- Paused when the strip is off screen.
- Reduce Motion, or fewer than 5 chips: a plain horizontal scroll instead.
- Full-bleed under the screen margin with a fade at both ends (web: `mask-image`). Chips press to 98% on touch-down (NATIVE_DESIGN `press`), light haptic on tap.

`-designPreview inSeason` (Debug builds) launches straight into a preview of the band, so it can be checked on a simulator without an account. `Core/DesignPreview.swift`.

## Sign-in screen, against the HIG
Fixed:
- Wordmark uses the bundled Fraunces through `Font.lociDisplay`, so it scales with Dynamic Type; it was `system(.serif)` at a fixed 32pt.
- Secondary text uses the `lociMutedInk` token instead of seven different `opacity()` values on ink.
- Error and success banners use `lociDestructive` and `lociForest`, not raw red and green.
- Tagline in sentence case.

Open (not in this slice):
- ~~Sign in with Apple~~ — landed on main in PR #5 (`feat/native-sign-in`, `SignInWithIDToken`), which satisfies App Review 4.8.
- The Google button draws an SF Symbol "G" in the brand terracotta; Google's guidelines want their own mark.
- No way to browse before signing in. Web's public landing lets a visitor search; iOS goes straight to sign-in. A Phase 1.5 candidate.
- Already sound: 44pt targets, native fields with AutoFill content types, ScrollView keyboard handling, one primary action.

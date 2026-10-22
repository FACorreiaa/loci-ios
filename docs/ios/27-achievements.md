# 27 · Achievements and the Field score

Achievements replace both badge systems: 15 tiered tracks (bronze to
platinum), 15 moments and 4 secrets. The Field score and rank (Scout →
Walker → Guide → Local → Keeper) are the one score; the legacy level and
daily streak are gone from the app. Web: `/achievements`, `/field`.

## Where it shows

- **Achievements** (`Features/Achievements/UI/AchievementsView.swift`): You
  hub row, Your progress, a profile's showcase or count, and the
  `/achievements` link (achievement and cheer pushes). Filter All / Earned /
  Up next (closest to its next rung first). Tap a row for its rungs, dates
  and rarity (`AchievementDetailSheet`). Someone else's comes from
  `AppRoute.achievements(userID:name:)`; the server refuses a private one.
- **Reveal** (`RevealView`): once, when `unseen_backfill_count` > 0. The
  backfill found what the person earned before achievements existed; closing
  the sheet marks them seen on every device. Otherwise the "New" marks clear
  four seconds after the page shows them.
- **Unlock toast**: `CompleteTripDayResponse.unlocked` goes to
  `PointsFeedback.unlocked(_:)`, which shows the best one ("+2 more") after
  any points chip. Unlocks queue; points replace each other.
- **Your progress** (`MyProgressView`): `FieldRankCard` (rank, score, bar to
  the next rank, this week) and `WeekStreakCard`, then Achievements and
  Leaderboard links, today, and points.
- **Leaderboard**: the Following board (`GetFieldBoard`, `FRIENDS_WEEK`),
  ranked by overall, places kept or days finished.
- **Profile subtitle** (`ProgressSummaryLine`): "Walker · 385" and the
  weekly streak.

## Medallions

`MedallionView` draws an SF Symbol on a ring. The server sends a semantic
`icon` key (a lucide name, which web draws), and
`AchievementText.symbols` maps it; an unknown key falls back to a rosette,
so new art never needs a release. `AchievementsModelTests` checks every
mapped name resolves with `UIImage(systemName:)`. Tier metals are
`lociBronze`, `lociSilver`, `lociGold`, `lociPlatinum` in `LociTheme`
(web's `--tier-*` tokens); moments and secrets use the coral accent.

`AchievementTier` names its zero case `unranked`, not `none` (SwiftLint
`discouraged_none_name`, and `Optional.none`).

## Weekly streak reminder

`StreakReminder` now fires on **Sunday at 18:00** local, the end of the ISO
week the server counts. After each daily check-in the app reads the Field
profile and reschedules (`fireDate(after:now:)`): this Sunday when the week
still needs exploring, next Sunday once it is done, nothing without a streak.

## Previews

`-designPreview achievements` (with the reveal), `achievementsList`, `feed`,
`myProgress`, `leaderboard`. Design previews need a Debug build.

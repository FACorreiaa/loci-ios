# Changelog

User-facing changes per App Store version. The store's "What's New" text lives in
`loci/fastlane/metadata/en-US/release_notes.txt`; App Store Connect shows it from
the second version on (fastlane skips it for the first).

## 1.0 (resubmitted 2026-10-20)

The 1.0 first submitted on 2026-10-01 (`9e22368`) was pulled from review and
replaced with a build of `main` that has everything below.

### Trips
- Trip Plan section: dates, a hotel per city, flight searches, Ask the planner (#73)
- Companion on a trip day: Discover opens on today, optional "Saved places nearby", Siri intents (#89)
- Trip journal with notes and photos per day; opt-in visit logging (#90)
- Trip recap story player with save-image and share-link (#82, #84, #88)
- Year in review cards, held back on the server until `RECAP_YEAR_UNLOCK_DATE` (#86)

### Taste
- Places I've been, "I've been here", remove a visit (#80, #81)
- "Not for me" on recommended places (#81)
- Match chip with "Why it fits you", "How was it?" ranking, top-10 lists (#87)
- Import places into a list from a shared link (#91)

### Friends
- Leaderboard, progress, streaks, find friends by phone and contacts (#55, #69)
- Invite from Profile; invite links don't expire; the inviter carries through sign-up (#75)
- Facebook friend finding, hidden until the Meta app is live (#71, #72)

### Boards
- Today's destination pinned above the feed; AI-generated posts carry a badge (#83)

### Under the hood
- Privacy manifest declares phone number and contacts (#70)
- ContactsUI weak-linked for Apple-silicon Macs, ITMS-90863 (#79)
- SwiftLint build phase, Periphery scan, SwiftUI review fixes (#77, #78)
- swift-algorithms (#85)

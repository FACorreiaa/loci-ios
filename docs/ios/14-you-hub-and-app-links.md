# Slice 14: the You hub and app links (parity pass 2, Phase 0)

Web has signed-in pages with no iOS screen: Recents, Lists, City Packs,
Reviews, Contribute, the globe. The tab bar stays at five, so this slice builds
the doors first and the rooms later. Every new entry pushes a placeholder
(`ComingSoonView`) that its phase replaces.

| Entry | Where | Replaced by |
|---|---|---|
| Profile › You: Recents, Where you've been, Lists, My reviews, Contribute | `Features/Profile/UI/YouSection.swift` (`YouDestination`) | Phases 1, 7, 2, 5, 6 |
| Saved › Lists segment | `SavedView.Segment.lists` (inline `ComingSoonPlaceholder`) | Phase 2 |
| Discover › City Packs card | `DiscoverView.packsEntry` | Phase 4 |

## App links

`AppLink` (`Core/Routing/AppRouter.swift`) is parsed after `SessionLink`, so a
result link keeps opening its session. It accepts `loci://<route>/…` and
`https://{lociai.fyi,www.lociai.fyi}/…`:

| Path | Case | Tab | Pushes |
|---|---|---|---|
| `/lists/:id` | `.list(id:)` | Saved (Lists segment) | placeholder |
| `/packs/:slug` | `.pack(slug:)` | Discover | placeholder |
| `/trips/:id` | `.trip(id:)` | Calendar (Trips hang off it) | `TripEditorView(tripID:)` |
| `/recents` | `.recents` | Profile | placeholder |
| `/contribute` | `.contribute` | Profile | placeholder |

A missing id or extra segment is nil, so the link stays in Safari.
`AppRouter.open(_:)` sets `selectedTab` and `pendingLink`; the owning tab takes
it with `takeLink(for:)` (on appear and on change, the same shape as
`AssistantView.openPending`) and pushes `AppLinkDestination` through
`.navigationDestination(item:)`. Other tabs see the change but `takeLink`
returns nil for them, so only the owner clears it.

The https form only reaches the app once the AASA file lists these paths
(`loci-client/public/.well-known/apple-app-site-association`, plan Phase 8).
Until then `loci://` is the way to test:
`xcrun simctl openurl booted loci://trips/<id>`.

Tests: `lociTests/AppLinkTests.swift` (every route, rejections, the
SessionLink-first rule, tab ownership). Preview: `-designPreview youHub`
(Debug builds).

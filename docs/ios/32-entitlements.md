# 32 — Entitlements (pass 3, Phase 0)

The account's plan and free-tier counters, read once per sign-in and shown on
the You hub. **Nothing is gated by it**: `PlanGating.enabled` is false (see
ROADMAP → Deferred — Pro gating) and the app never points at a purchase.

## RPC

`EntitlementService.GetEntitlements{}` → `Entitlements{plan, lists_used,
lists_limit, places_saved, places_limit, advanced_filters, export_full}`.
`-1` on a limit means unlimited. Web: `lib/api/entitlements.ts`.

## Pieces

- `Core/Entitlements/Entitlements.swift` — the struct, `.free` (5 lists, 50
  places), `isPro` (the same plan names as `ProGate.proPlans`),
  `listsRemaining` / `placesRemaining` (nil when unlimited), `chipText`.
- `Core/Entitlements/EntitlementsAPI.swift` — the one call.
- `Core/Entitlements/EntitlementsStore.swift` — `@MainActor @Observable`
  singleton; `refresh(userID:)` goes through `cacheThrough` with
  `LocalCache.Kind.entitlements` keyed by user id, so a cold launch shows the
  last known plan and an offline fetch keeps it; `invalidate()` after a
  free-limit refusal (`ListsStore`); `reset()` on sign-out.
- `YouSection` → `PlanChip` ("Pro" or "Free · 3/5 lists · 12/50 places").
- `ResultsAPI.plan()` now reads the same RPC instead of
  `PaymentService.GetSubscription`, so the results pages and the hub agree.

## Previews

`-designPreview youHubPro`, `youHubFree`.

## Not done

No upgrade button, no paywall, no counters anywhere but the hub. When gating
is switched on, `TripExportGate` and `ProGate` already take `isPro`; feed them
`EntitlementsStore.shared.current.isPro` then.

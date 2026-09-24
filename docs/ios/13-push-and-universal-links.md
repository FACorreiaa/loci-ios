# Slice 13: APNs search-finished push and Universal Links (Phase 2A)

Phase 1 announced a finished search with a local notification, which only
works while the app is alive in the background. The server has sent web push
since api #70; this slice registers the iPhone with the same notifier
(api #77, proto v5.25.0) and lets a `https://lociai.fyi/…` result link open
the app.

| iOS piece | Web equivalent | RPC → fields sent |
|---|---|---|
| `Core/Notifications/PushRegistration.swift` | `lib/push/push-client.ts` | `UserService.RegisterPushDevice{platform: APNS, endpoint: <64-hex token>, apnsTopic: <bundle id>, apnsEnvironment: sandbox (Debug) or production}`; `UnregisterPushDevice{endpoint}` before logout (web: `AuthContext`) |
| Settings › Notifications › Search finished | settings tab "notifications" | `UpdateNotificationSettings{…, searchFinished}`: the flag the server checks before pushing |
| `SessionLink(url:)` https branch, `.onContinueUserActivity(NSUserActivityTypeBrowsingWeb)` | the web routes themselves | none; `applinks:lociai.fyi` in `loci.entitlements`, AASA served by the web Worker (client #70) |

## How it fits together

1. `PushNotificationManager` asks for permission on the first search and
   registers for remote notifications; the token arrives in the app delegate.
2. `PushRegistration.registerIfNeeded()` runs on that token and again after
   sign-in (the token usually lands before the first login). It posts once
   per `(user, token)` pair and remembers the pair in `UserDefaults`; failure
   is silent and retried next launch, because the local notification still
   covers a live app.
3. Once registered, `SearchSessionController.finish` no longer posts the
   local notification: the server announces the run, killed app included, and
   two banners for one search would be wrong. A push for the session on
   screen is not shown at all (`willPresent` returns no options), matching
   web's RunWatcher, which does not toast the run you are looking at.
4. A tap on the push carries `sessionId`, `cityName`, `domain` at the top
   level of the payload, the same keys the local notification used, so
   `SessionLink(userInfo:)` and `AppRouter.open` are unchanged.
5. A `https://lociai.fyi/{itinerary,hotels,restaurants,activities,nearme}?sessionId=…`
   link opens the app through `SessionLink(url:)`; `nearme` opens as an
   itinerary page since Nearby has no session restore. Any other host or path
   stays in Safari.

## Environment rule

Apple drops a token sent to the wrong host without an error. Debug builds are
signed with a development profile (`aps-environment` development), so they
register as `sandbox`; Beta and Release register as `production`. The server
refuses a topic that is not one of the two bundle ids.

## Signing

`com.apple.developer.associated-domains` is a new entitlement, which means
both App IDs need the Associated Domains capability before `match` can build
a profile: run `scripts/enable_capability.rb ASSOCIATED_DOMAINS` (Spaceship,
uses `loci/fastlane/.env`), then `gh workflow run seed-signing.yml --ref main`,
then release. See `docs/ios/02-auth.md` for the same dance Sign in with Apple
needed.

## Checking it

- Unit: `PushRegistrationTests` (request shape, environment per build),
  `SessionLinkTests` (https links, `nearme`, foreign hosts rejected).
- Device: sign in, allow notifications, run a search, background the app;
  the banner comes from the server (`loci_push_sent_total{platform="apns"}`
  ticks). Kill the app, run a search from the web, tap the banner: the result
  page cold-starts. Toggle Search finished off: no banner. Tap a
  `https://lociai.fyi/itinerary?sessionId=…` link in Notes: the app opens.
  Apple caches the AASA; a fresh install can take up to a day to pick it up.

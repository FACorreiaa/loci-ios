# Slice 31: First-run profile wizard (parity pass 2, Phase 8 item 6, iOS half)

Web's `/trip-setup` on the phone (loci-client #82, `lib/trip-setup.ts`): four
questions fill in the default travel profile, so the very first search is
already personalised. Offered once, right after the sign-in that created the
account. Everything is `Features/Onboarding`.

## Why the first version never showed

The server creates a profile named "Default" for every new user (the
`AFTER INSERT ON users` trigger, migration 0008). #45 offered the wizard only
to accounts with zero profiles, which no account ever has, and would have added
a second profile next to "Default". Web had the same bug; #82 fixed both, and
this slice ports that fix.

## When it is offered (`TripSetup.shouldOffer`, `TripSetupOffer`)

- Only after a sign-in that created the account: email sign-up
  (`LoginViewModel.performSignup` → `AuthService.login(…, isNewUser: true)`), or
  Apple/Google native sign-in where `SignInWithIDToken` returned `isNewUser`.
  `AuthSessionManager.storeSession(…, isNewUser:)` puts it in the
  `authSessionDidAuthenticate` notification's `userInfo`
  (`AuthSessionUserInfo.isNewUser`); `lociApp` passes it with
  `currentUserID` to `TripSetupOffer.offerIfNeeded(isNewUser:userID:)`.
- Existing accounts cost no RPC. For a new one, `GetUserPreferenceProfiles`;
  offered only when every profile is untouched (`isUntouched`: named "Default",
  no interests, tags, vibes or dietary needs). A failed read does not offer.
- Seen per user id: `UserDefaults` `loci_trip_setup_seen:<userId>`, set when the
  cover is presented (finished or skipped), so a second account on the phone
  still gets it. (#45's device-wide `loci_trip_setup_seen` key is no longer read.)

## Screens → RPCs

| Screen | RPC | Fields sent |
|---|---|---|
| Interests step (chips) | `InterestService.GetInterests` | `activeOnly: true`; chips are the curated labels the catalogue has, else the catalogue's names. Loading row; on failure a message and Try again, and Start planning stays enabled |
| Start planning | `ProfileService.GetUserPreferenceProfiles`, then `UpdateUserPreferenceProfile` (or `CreateUserPreferenceProfile` when no profile is default) | `TripSetup.draft` applied onto `TravelProfileDraft(storedDefault)`: `budgetLevel` 1–4, `preferredPace` (packed → FAST), `preferredTransport` (walking → WALK, transit and step-free → PUBLIC, car → CAR), `preferAccessiblePois` for step-free, `interestIds` (catalogue ids, never labels). Vibes, dietary needs, tags and the hotel/dining/activity/itinerary sections go back unchanged, because update replaces lists. Name: "Default" (or empty) becomes "My Trip Profile"; a name the user chose is kept |

## Rules (`Model/TripSetup.swift`, tests in `TripSetupTests`, ported from web's `trip-setup.test.ts`)

- Interests go out as catalogue ids matched by name, case-insensitively, in chip order; unknown labels are dropped.
- Every pace and mobility choice maps to a real enum, never ANY. Step-free is PUBLIC plus accessible: the enum has no wheelchair case, and WALK would favour long on-foot legs.
- `save(existing:)`: update the default profile in place; create only when there is none.

## State

- `TripSetupStore` (`@MainActor @Observable`, injected `TripSetupService`): step, answers, catalogue state (loading/loaded/failed), save with Try again and Skip for now. The cover closes (`isDone`) only on a successful save or a skip, then the main tabs show Discover.
- `PreviewTripSetupService` (server "Default", switches for a failed save or catalogue) for `-designPreview tripSetup` and tests.
- Dynamic Type: the choice grid drops to one column at accessibility sizes; every control is at least 44pt.

## Analytics

- `onboarding_completed {skipped, step}` (step: budget, pace, getting_around, interests); screen `trip_setup`.

## Not verified

Not run signed in against the live API: a real new account (email, Apple, Google) actually getting the cover, the update landing on the server's "Default" profile, and the catalogue's real names versus the curated chips.

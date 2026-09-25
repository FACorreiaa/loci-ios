# Slice 31: First-run profile wizard (parity pass 2, Phase 8 item 6, iOS half)

Web's `/trip-setup` on the phone: four questions, one default travel profile,
so the very first search is already personalised. Offered once, after a
sign-in, to an account that has no profile yet. Everything is `Features/Onboarding`.

## Screens → RPCs

| Screen | RPC | Fields sent |
|---|---|---|
| Interests step (chips) | `InterestService.GetInterests` | `activeOnly: true`; chips are the curated labels the catalogue has, else the catalogue's names |
| Offer decision | `ProfileService.GetUserPreferenceProfiles` | none; `profiles.count == 0` offers, a failed read counts as unknown and never offers |
| Start planning | `ProfileService.CreateUserPreferenceProfile` | `TravelProfileDraft.createRequest()`: name "My Trip Profile", `isDefault`, `budgetLevel` 1–4, `preferredPace` (packed → FAST), `preferredTransport` (walking/step-free → WALK, transit → PUBLIC, car → CAR), `preferAccessiblePois` for step-free, `interestIds` (catalogue ids, never labels) |

## Rules (`Model/TripSetup.swift`, tests in `TripSetupTests`)

- Interests go out as catalogue ids matched by name, case-insensitively, in chip order; unknown labels are dropped. Sending labels is what made every web submit with a selection fail.
- Every pace and mobility choice maps to a real enum; web's "packed", "walking" and "transit" used to fall to ANY.
- `shouldOffer(seen:profileCount:)`: once per device (`loci_trip_setup_seen`), only when the account has zero profiles, never when the count is unknown.

## State

- `TripSetupStore` (`@MainActor @Observable`, injected `TripSetupService`): step, answers, catalogue, save with Try again; `isDone` closes the cover. `PreviewTripSetupService` for `-designPreview tripSetup` and tests.
- `TripSetupOffer.shared`: `offerIfNeeded()` runs on `authSessionDidAuthenticate` (`lociApp.swift`), marks seen when it presents; `MainTabView` shows the wizard in a full-screen cover with Skip on every step.

## Analytics

- `trip_setup_completed {interests, pace}`; screen `trip_setup`.

## Not verified

Not run signed in against the live API: the catalogue's real names versus the curated chips, and the created profile showing up in Profile › Travel profiles.

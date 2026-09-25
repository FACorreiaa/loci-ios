# Slice 20: Near me directions (route line, walking figure, follow mode)

The next step of "Near me like Pokémon Go", on top of the walk from slice 11. Tapping a place on the Near me map draws the walking route to it. Pressing **Go** starts the walk if it isn't already running, and the camera then follows a little walker figure while the line shrinks to what is left. Everything runs on the phone: no new RPCs, and Apple's directions are free and need no key.

| Piece | Apple SDK | Where | Notes |
|---|---|---|---|
| Walking route | MapKit `MKDirections` (`.walking`) | `Features/Nearby/Services/WalkNavigator.swift` (`appleMaps`) | Behind an injected closure, so tests stub it. When no route comes back (offline, no path), the line is drawn straight and labelled as such; Go still works on straight-line distance. |
| Geometry | none (pure Swift) | `Core/Navigation/WalkingRoute.swift` | Snapping a fix onto the line, what is left, ETA (Apple's route time scaled to the remaining distance, or 1.35 m/s), off route (> 40 m), arrival (≤ 25 m), heading, which way the walker faces, and the camera rect. |
| Follow state | Observation | `WalkNavigator`, owned by `NearbyWalk` | `preview` does not start anything. `start` follows the route. `ingest` runs on every fix from the walk's `liveUpdates` loop. A reroute needs 2 consecutive stray fixes and happens at most once every 10 s, because MKDirections throttles apps. A newer preview or reroute wins over one that is still in flight. |
| Line + walker | SwiftUI MapKit `MapPolyline`, `Annotation` | `NearbyView.swift`, `UI/WalkerFigure.swift` | Dashed in preview, solid while following. The walker replaces `UserAnnotation` while following. It is mirrored rather than rotated so it stays upright, bobs while moving (GPS speed > 0.3 m/s or a step in the last 3 s), and stands still under Reduce Motion. |
| Follow camera | `MapCamera` | `NearbyView.followCamera` | 400 m, pitch 60, turned to the heading. Panning (`positionedByUser`) stops following and shows **Recenter**. |
| Route card | SwiftUI | `UI/RouteCard.swift` | Pinned above the list: time and distance, **Open in Maps** (walking) and **Go**. While following it shows what is left and **End**. On arrival it shows "You're at …" and **Done**, with a success haptic. |
| Lock Screen | ActivityKit | `Shared/NearbyWalkAttributes.swift`, `NearbyWalkWidget/NearbyWalkLiveActivity.swift` | Optional `destinationName`, `destinationMeters` and `etaSeconds`. Shows "Bolhão · 400 m · 5 min" in place of the nearest place. The fields are optional so an activity from an older build still decodes (tested). |

## Behaviour
- **End** stops only the route. **Stop** in the walk row still ends the whole walk (pedometer, fences, Live Activity).
- Tapping another place while following previews that place. **Go** switches to it.
- Arrival while the phone is locked already produces the slice-11 geofence notification (60 m), so arrival posts no second one.

## HealthKit: still no
Asked again for this slice ("should it count steps in Apple Health?"). The answer stays no:
- The iPhone writes its own step count to Health from the motion coprocessor. If Loci wrote steps as well, Health would show them twice (Health dedupes by source priority, which people rarely set).
- `CMPedometer` already gives Loci the same count, with only the Motion & Fitness prompt.
- The one Health integration worth doing is saving a walk as an `HKWorkout` (walking). It needs the HealthKit entitlement on both App IDs and a seed-signing round. Only worth it if people ask.

## Verified
- Tests (`lociTests/WalkNavigatorTests.swift`):
  - snapping and the off-route threshold;
  - remaining distance shrinks along an L-shaped route, without drawing the corner vertex twice;
  - ETA scaling and its formatting;
  - the heading fallback when GPS course is -1, and which way the walker faces;
  - preview does not trim, but following does;
  - 2 stray fixes produce exactly one reroute, and the 10 s throttle holds;
  - arrival clears the route and names the place;
  - no route falls back to a straight line;
  - a newer preview beats a slow one;
  - old Live Activity payloads still decode.
- Builds under Swift 6. SwiftLint is clean.

## Not verified
A real walk on a phone: whether the line hugs the pavement, how the follow camera feels, battery cost over 20 minutes, and the walker direction on a real heading. The simulator's location simulation (Features ▸ Location ▸ City Walk or a GPX) is the closest stand-in.

# Slice 11: Near me walk (steps, geofences, Live Activity)

The first native-only layer, and the smallest version of the "Near me like Pokémon Go" idea: press **Start** in the Near me sheet and the phone counts your steps, fences the places on the map, and keeps a Live Activity on the Lock Screen and Dynamic Island until you press Stop. No new RPCs; the places come from the same `StreamChat` nearby search.

| Piece | Apple SDK | Where | Notes |
|---|---|---|---|
| Steps and distance | CoreMotion `CMPedometer` | `Core/Motion/WalkTracker.swift` | Live updates from the motion coprocessor. **No HealthKit**: nothing read from or written to Health. Prompt: Motion & Fitness, first Start. A refusal keeps the walk running without a count. |
| "You're near …" nudges | CoreLocation `CLMonitor` | `Features/Nearby/Services/POIProximityMonitor.swift` | One `CircularGeographicCondition` (60 m) per place, the 20 nearest (CLMonitor's cap). Entering one posts a local notification, once per place per walk. Conditions are removed on Stop, because CLMonitor persists them across launches. |
| Stay alive while walking | CoreLocation `CLServiceSession` + `CLLocationUpdate.liveUpdates()` | `Features/Nearby/Services/NearbyWalk.swift` | When-in-use authorization plus the `location` background mode keep the walk going with the phone locked; the status-bar arrow shows while it does. Also feeds "nearest place". |
| Lock Screen / Dynamic Island | ActivityKit + WidgetKit | `Shared/NearbyWalkAttributes.swift` (app + extension), `NearbyWalkWidget/` (extension target) | Steps, distance, places fenced, nearest place, elapsed timer. Updated at most every 5 s. Ends immediately on Stop. `NSSupportsLiveActivities` in Info.plist. |
| UI | SwiftUI | `WalkRow` in `NearbyView.swift` | Start / Stop with live numbers; `contentTransition(.numericText())` on the counter. |

## Project changes
- New target `NearbyWalkWidget` (WidgetKit extension), added by `scripts/add_widget_extension.rb` with the `xcodeproj` gem so the pbxproj edit is reviewable. Bundle ids `com.fernandocorreia.loci.NearbyWalkWidget` and `com.fernandocorreia.loci.beta.NearbyWalkWidget`; both registered on the Developer Portal and listed in `fastlane/Matchfile`. `prepare_signing` now sets the extension's profile too.
- Info.plist: `NSMotionUsageDescription`, `NSSupportsLiveActivities`, `UIBackgroundModes` += `location`.

## Before the next release
Seed signing must run once so match issues the two extension profiles (`Seed signing` workflow). Otherwise the archive fails at the appex, the same way the Sign in with Apple entitlement did.

## Verified
- Builds under Swift 6 with the extension embedded (`PlugIns/NearbyWalkWidget.appex`, `com.apple.widgetkit-extension`); installs on the simulator.
- Tests: nearest-20 fence selection without repeats or pin-less places; nearest place by real distance; the shared Live Activity text.

## Not verified
A walk on a real phone: step counts, a geofence firing, the Live Activity on the Lock Screen. The simulator has no pedometer and only simulated location.

## Design notes
- Every permission is asked on Start, not at launch. Motion & Fitness is the only new prompt; Live Activities need none.
- Reduce Motion is respected by the existing map and sheet; the walk adds no motion of its own.
- HealthKit would add an entitlement (and a seed-signing round) for no gain in this pass; it's the right tool only if walks should be written to Health as workouts.

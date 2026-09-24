# Loci iOS: architecture study guide

A reading guide to the native app in `loci/`, written against `origin/main` at
`bc49e41` (2026-09-23). Every claim points at a file; the snippets are copied
from the source with a `// path:LINE` line above them, where LINE is the first
line shown. Where a slice doc in this folder already has the RPC table, this
guide links to it instead of repeating it. Paths are relative to the repository
root unless they start with `../`.

## 1. What this app is

Loci iOS is a SwiftUI client for the same Connect RPC API the web app
(`../loci-client`) talks to, generated from the same protos
(`../loci-connect-proto/gen/swift`). Phase 1 is parity: sign in, stream a
search, show the result pages web has (`/itinerary`, `/hotels`, `/restaurants`,
`/activities`), edit a trip, compare weekends, keep saved things, and mirror
every settings tab except Billing. The rule for the phase is "no new
endpoints": everything the app does is an RPC web already calls, with the same
fields (each slice doc has the screen → RPC → fields table). The first
native-only layer (a step-counting walk with geofences and a Live Activity)
has already landed on top of that. The roadmap and the server work that unlocks
Phase 2 live in [`ROADMAP.md`](ROADMAP.md).

## 2. Timeline of what was built

From `git log --first-parent origin/main`, the merged PR bodies, and the slice
docs. "Verified" means run on a real device against the live API; the PR bodies
are precise about this, and none of the slices records a device pass of its own
feature. Two device facts exist only indirectly: Google sign-in on TestFlight
failed on the web callback (which produced #5), and the first real search on
TestFlight showed raw model JSON (which produced #10).

| Date | Commit / PR | Slice | What landed | Verified on a device |
|---|---|---|---|---|
| 2026-09-20 | `4388c2d` … `991b683` | pre-slice | Xcode project, proto package, Google web-OAuth, Beta and Release schemes, TestFlight lane, APNs key and `send_push` lane, SwiftLint + swift-format, calendar tab | TestFlight builds shipped; no feature pass recorded |
| 2026-09-22 | PR #1 `aca94b4` | 1, 2 | Shell, `LociTheme` tokens and bundled fonts, `ConnectTransport` + `AuthInterceptor`, `actor AuthTokenProvider` (single-flight refresh), `withAuthRetry`, `loci://` deep links, Swift 6 mode | No (simulator tests only) |
| 2026-09-22 | PR #2 `2f264d7` | 3 | Every web settings tab except Billing, incl. MCP keys, model provider, Telegram, outbound servers, calendars, notifications | No ("none of these screens has been run against the live API") |
| 2026-09-22 | PR #3 `d1d075f` | 6 | `SearchSessionController`, `SearchState` reducer, envelope persistence, BGAppRefresh reconcile, local notifications, `SearchResultsView`, Ask Loci list | No ("no search has been streamed against the live API") |
| 2026-09-22 | PR #4 `b565917` | 4, 5, 7, 8, 9 | Discover, Near me (MapKit + detent sheet), Trips editor, Compare, Saved | No ("nothing has run against the live API") |
| 2026-09-22 | PR #5 `a46c118` | auth | Native Sign in with Apple and Google via `SignInWithIDToken`; web-callback flow removed | Motivated by a TestFlight failure; the fix not recorded as passed on a device |
| 2026-09-22 | PR #6 `73e1adf` | 10 | In-season marquee under the Discover hero, sign-in HIG pass, `-designPreview inSeason` | Simulator screenshots |
| 2026-09-22 | PR #7 `6095f3b` | 11 | Near me walk: `CMPedometer`, `CLMonitor` geofences, Live Activity, `NearbyWalkWidget` target | No ("the simulator has no pedometer") |
| 2026-09-23 | PR #8 `632a52c` | Muse A | Ask Loci and results restyled to the shared Muse chat contract | Screenshots in `../_reviews/muse` |
| 2026-09-23 | PR #9 `a37405e` | Muse B | `MuseActivity` drives the header from the live search; ring animation | Screenshots |
| 2026-09-23 | PR #10 `be99707` | 12 | Result pages at web `/itinerary` parity: header, local context strip, map hero → full map, day sections, stop cards, detail sheet, Trip Kit; tokens no longer rendered | 74 unit tests, design previews; not on a device |
| 2026-09-23 | PR #11 `bc49e41` | here brief | `HereBriefSection` on Discover from `GetHereBrief` (proto v5.23.0) | No; needs server PR #76 deployed; simulator QA owed |

## 3. Project setup

### Synchronized folders

The three app groups are `PBXFileSystemSynchronizedRootGroup`s with empty
exception lists, so a new `.swift` file under `loci/loci`, `loci/lociTests` or
`loci/lociUITests` joins its target when it is saved. No pbxproj edit is needed
for new files.

```text
// loci/loci.xcodeproj/project.pbxproj:70
		0DC776AB305DBE860029F87E /* loci */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			exceptions = (
			);
			path = loci;
			sourceTree = "<group>";
		};
```

The widget extension is the exception: it was added by a script (below) with
explicit file references, because the shared attributes file must be compiled
into two targets.

### Swift 6 and default MainActor isolation

Every target builds in Swift 6 language mode with the "approachable
concurrency" settings, and the default actor isolation is `MainActor`:

```text
// loci/loci.xcodeproj/project.pbxproj:611
				SWIFT_APPROACHABLE_CONCURRENCY = YES;
				SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor;
```

(`SWIFT_VERSION = 6.0` is at line 615 and `IPHONEOS_DEPLOYMENT_TARGET = 26.2`
at line 602 of the same file.)

The consequence to internalise: a type with no annotation is main-actor
isolated. That is what SwiftUI views and the `@Observable` controllers want, so
most of the code carries no isolation keyword at all. Anything that must be
usable off the main actor (a value handed to a `Task`, an actor's dependency,
a protocol a test double implements) is marked `nonisolated` explicitly.
`SearchState` is the canonical example: reduced on the main actor, but
`Sendable` so it can be stored, compared and built in tests:

```swift
// loci/loci/Features/Search/Model/SearchState.swift:7
nonisolated struct SearchState: Equatable, Sendable {
  enum Status: Equatable, Sendable {
    case idle
    case streaming
    /// The client lost the stream; the server may still be generating.
    case detached
```

The same keyword appears on free functions (`rpc`, `withAuthRetry`), on enum
namespaces of static helpers (`DayGrouping`, `ResultsAPI`, `SettingsClients`),
and on the Keychain protocol so an actor can hold it:

```swift
// loci/loci/Core/Security/SecureStringStore.swift:20
public nonisolated protocol SecureStringStoring: Sendable {
  func string(for key: String) throws -> String?
  func setString(_ value: String, for key: String) throws
  func removeValue(for key: String) throws
}
```

One `@preconcurrency import` exists, and the comment beside its use says why:
ActivityKit's `Activity` is not `Sendable`, but `update`/`end` are safe to
call from a detached task, so the import downgrades the diagnostic to a warning:

```swift
// loci/loci/Features/Nearby/Services/NearbyWalk.swift:21
  // ActivityKit's Activity is not marked Sendable, though update/end are safe to
  // call from anywhere; the @preconcurrency import keeps that a warning.
  private var activity: Activity<NearbyWalkAttributes>?
```

Deployment target is iOS 26.2 on every target. Bundle ids:
`com.fernandocorreia.loci` (Release) and `com.fernandocorreia.loci.beta`
(Beta / TestFlight), each with a `.NearbyWalkWidget` extension id.

### SwiftLint rules that bite

`.swiftlint.yml` at the repo root opts into a long list; the ones that most
often fail a fresh file are `force_unwrapping` (an error, not a warning),
`indentation_width: 2`, `trailing_comma` with `mandatory_comma: true`,
`line_length` 150 warning / 200 error, `closure_body_length` 80/120,
`function_body_length` 90/120, `type_body_length` 500/700, `file_length`
900/1200, and `explicit_self` and `unused_import` as analyzer rules.
`closure_parameter_position` is disabled because it fights swift-format. The
check CI runs is:

```text
./scripts/format.sh --skip-install --lint-only
```

Without `--lint-only` the script runs swift-format, then `swiftlint --fix`,
and reports the before/after count; `--reporter github-actions-logging` is
what `ci.yml` passes.

### The local proto package

The Swift protos are not a remote dependency. The project references the
sibling checkout by relative path, so the proto repo must sit next to the Loci
folder:

```text
// loci/loci.xcodeproj/project.pbxproj:1005
		0DC776E0305DBE860029F87E /* XCLocalSwiftPackageReference "loci-connect-proto" */ = {
			isa = XCLocalSwiftPackageReference;
			relativePath = "../../loci-connect-proto";
		};
```

`../loci-connect-proto/Package.swift` builds `gen/swift` as the
`LociConnectProto` library on `connect-swift` ≥ 1.2 and `swift-protobuf` ≥ 1.28
with `StrictConcurrency` enabled. `gen/swift` is committed by hand (proto CI
does not run Buf's Swift generation yet; see `ROADMAP.md`). CI reproduces the
layout by checking the proto repo out and copying it one level above the
workspace:

```yaml
# .github/workflows/ci.yml:48
      - name: Setup local proto link
        run: |
          mkdir -p "$GITHUB_WORKSPACE/../loci-connect-proto"
          cp -R "$GITHUB_WORKSPACE/loci-connect-proto/." "$GITHUB_WORKSPACE/../loci-connect-proto/"
```

The other two packages are remote: `connect-swift` (≥ 1.0) and
`GoogleSignIn-iOS` (≥ 9.0).

### The widget extension target

`NearbyWalkWidget` is a WidgetKit extension holding one Live Activity. It was
added with the `xcodeproj` gem rather than Xcode's UI so the pbxproj diff was
reviewable; the script adds the shared attributes file by reference:

```ruby
# loci/scripts/add_widget_extension.rb:21
ext = project.new_target(:app_extension, EXT_NAME, :ios, "26.2")
ext.product_type = "com.apple.product-type.app-extension"

group = project.main_group.new_group(EXT_NAME, EXT_DIR)
sources = %w[NearbyWalkWidgetBundle.swift NearbyWalkLiveActivity.swift].map { |f| group.new_file(f) }
sources << project.main_group.new_file(SHARED_FILE)
```

The extension cannot see `LociTheme`, so `NearbyWalkLiveActivity.swift` carries
its own four-colour `Palette` (NATIVE_DESIGN light values).

### CI, release, seed signing

- `ci.yml`: a `lint` job (SwiftLint 0.65.1) and a `test` job that resolves
  packages with retries, builds the `loci Beta` scheme for the simulator, then
  runs `bundle exec fastlane test` (`lociTests` only; UI tests are not in CI).
- `release.yml`: a green "iOS CI" on `main` triggers the `beta` lane
  (TestFlight, `com.fernandocorreia.loci.beta`); `workflow_dispatch` can run
  `beta` or `release` (App Store, phased rollout) with an optional version.
- `seed-signing.yml`: manual. Runs `match` read-write to (re)create
  certificates and profiles in the private `loci-certificates` repo. It has to
  run whenever an entitlement or a bundle id is added; both the Sign in with
  Apple entitlement (`loci/loci.entitlements`) and the widget's two bundle ids
  needed it. The Matchfile lists all four identifiers.

## 4. Architecture map

```text
loci/loci
├── lociApp.swift                    entry: preview / loading / signed-in / sign-in switch, deep links, scene phase
├── Core
│   ├── AppDelegate.swift            notification delegate wiring, BGTask registration
│   ├── Configuration/AppConfig.swift  base URL per build configuration, client ids from Info.plist
│   ├── DesignPreview.swift          `-designPreview <case>` screens and sample SearchStates
│   ├── Location/CurrentLocation.swift  one fix with CLServiceSession + liveUpdates
│   ├── Motion/WalkTracker.swift     CMPedometer steps and distance
│   ├── Network/                     ConnectTransport, AuthInterceptor, AuthTokenProvider, APIError(+Connect)
│   ├── Notifications/PushNotificationManager.swift  UNUserNotificationCenter delegate, APNs token
│   ├── Routing/                     AppRouter, SessionLink, SearchDestination, InteractivePop
│   ├── Security/                    KeychainStringStore, JWTTokenInspector
│   └── Theme/LociTheme.swift        tokens, fonts, modifiers, Muse metrics
├── Features
│   ├── Auth/                        Services (Apple, Google, NativeSignIn, session, web auth) + UI (LoginScreen…)
│   ├── Calendar/                    AppleCalendar (EventKit), CalendarMath, CalendarView, CalendarConnectService
│   ├── Chat/                        MuseActivity, MuseChatHeader (+ bubbles, ring, scrim), AssistantView
│   ├── Compare/UI/CompareView.swift
│   ├── Discover/                    DiscoverView, HereBriefSection, InSeasonBand, SeasonalPicks
│   ├── Lists/                       Model (LociList, ListPayload, EntitlementLimit), Services (ListsAPI + ListsService),
│   │                                UI (ListsView/ListsRows, ListDetailView, AddToListSheet, ListsStore)
│   ├── Main/UI/MainTabView.swift    the five tabs
│   ├── Nearby/                      NearbyView, NearbyWalk, POIProximityMonitor
│   ├── Profile/UI/                  ProfileView, YouSection (the You hub), NotificationSettingsView
│   ├── Recents/                     Model (ActivityEntry, DayBuckets, RecentCity, ActivityDestination),
│   │                                Services (RecentsAPI + RecentsService), UI (RecentsView, RecentCityView)
│   ├── Saved/UI/SavedView.swift
│   ├── Search/                      SearchSessionController; Model (SearchState, SearchEnvelope, DayGrouping);
│   │                                Services (ChatStreamClient, ResultsAPI, SearchNotifier); UI (composer, results page)
│   ├── Settings/                    SettingsClients + one view per web settings tab
│   └── Trips/UI/                    TripsView, TripEditorView
├── Resources/Fonts                  Fraunces, DM Sans, Space Mono (+ OFL licences)
└── Shared/NearbyWalkAttributes.swift  ActivityAttributes compiled into app and widget
```

### Layering

Core knows nothing about features. Features depend on Core and on the
generated proto clients, never on each other's views; what features share are
small value types (`SessionLink`, `SearchState`, `DayGroup`) and a handful of
process-wide singletons. There is no dependency-injection container.

| Singleton | File | Owns |
|---|---|---|
| `ConnectTransport.shared` | `Core/Network/ConnectTransport.swift` | The one authenticated `ProtocolClient` every generated client wraps |
| `AuthTokenProvider.shared` | `Core/Network/AuthTokenProvider.swift` | Access-token reads and the single-flight refresh (an `actor`) |
| `AuthSessionManager.shared` | `Features/Auth/Services/AuthSessionManager.swift` | Keychain writes, `currentUserID`, the sign-in/sign-out notifications |
| `AppRouter.shared` | `Core/Routing/AppRouter.swift` | Selected tab, the pending `SessionLink` from a deep link or notification tap, and the pending `AppLink` (`/lists`, `/packs`, `/trips`, `/recents`, `/contribute`) its owning tab takes (`14-you-hub-and-app-links.md`) |
| `SearchSessionController.shared` | `Features/Search/SearchSessionController.swift` | The one running search, its envelope and its result copy |
| `PushNotificationManager.shared` | `Core/Notifications/PushNotificationManager.swift` | `UNUserNotificationCenterDelegate`, authorisation, APNs device token |
| `NearbyWalk.shared` | `Features/Nearby/Services/NearbyWalk.swift` | The active walk and its Live Activity |
| `AppleCalendar.shared` | `Features/Calendar/AppleCalendar.swift` | The `EKEventStore` and the "Loci" calendar |

Views read these directly (`private let controller = SearchSessionController.shared`)
rather than through the environment. Tests construct their own instances with
injected dependencies (`AuthTokenProvider(store:performRefresh:onSessionEnded:)`,
`SearchStore(directory:)`).

The entry point shows the shape: which root to show, and (lines 48-60) who
handles a URL (`GIDSignIn` first, then `AppRouter.shared.open`) and who is told
about scene phase changes (`SearchSessionController`).

```swift
// loci/loci/lociApp.swift:20
        if let preview = DesignPreview.requested {
          preview.body
        } else if isCheckingAuth {
          ZStack {
            Color.lociPaper.ignoresSafeArea()
            ProgressView()
          }
        } else if isAuthenticated {
          MainTabView(onSignOut: { withAnimation { isAuthenticated = false } })
        } else {
          LoginScreen(onAuthenticated: { withAnimation { isAuthenticated = true } })
        }
```

## 5. Networking

### ConnectTransport

One `ProtocolClient` over `URLSessionHTTPClient`, Connect protocol, JSON codec,
with the auth interceptor installed. A second, bare client exists only so the
token refresh cannot recurse into the interceptor that needs a token:

```swift
// loci/loci/Core/Network/ConnectTransport.swift:16
    self.protocolClient = ProtocolClient(
      httpClient: URLSessionHTTPClient(),
      config: ProtocolClientConfig(
        host: resolved.absoluteString,
        networkProtocol: .connect,
        codec: JSONCodec(),
        interceptors: [InterceptorFactory { AuthInterceptor(config: $0) }]
      )
    )
  }

  static func makeBareClient(baseURL: URL? = nil) -> ProtocolClientInterface {
```

The base URL comes from `AppConfig`: `http://localhost:8000` in Debug,
`https://api.lociai.fyi` otherwise, unless `ConnectBaseURL` in Info.plist is
set to a real value (it is `$(CONNECT_BASE_URL)` by default, which the guard
treats as unset). `mcpEndpoint` is `baseURL + /mcp`, shown on the MCP settings
screen.

### AuthInterceptor

`Core/Network/AuthInterceptor.swift` implements both `UnaryInterceptor` and
`StreamInterceptor`. It only touches headers, and only when the caller has not
set `Authorization` itself. The token read is `async` (it may trigger a
refresh), so each hook hops into a `Task` and calls `proceed` when it has the
headers (`handleUnaryRequest`, line 12; `handleStreamStart`, line 23).

### AuthTokenProvider: an actor with single-flight refresh

The provider is the only reader of the access token. It treats a JWT as
expired 30 s before its `exp`, and refreshes before the request leaves. If
eight callers arrive while a refresh is running, they all await the same
`Task`:

```swift
// loci/loci/Core/Network/AuthTokenProvider.swift:54
  func accessToken() async -> String? {
    guard let token = try? store.string(for: AuthKeychainKeys.accessToken), !token.isEmpty else { return nil }
    if let expiry = JWTTokenInspector.expirationDate(in: token), expiry.addingTimeInterval(-Self.expirySkew) <= now() {
      return await refresh()
    }
    return token
  }

  /// Refresh the session. Concurrent callers share one network call.
  func refresh() async -> String? {
    if let inFlight { return await inFlight.value }
    let task = Task { await runRefresh() }
    inFlight = task
    let token = await task.value
    inFlight = nil
    return token
  }
```

The refresh runs on the bare client, and the outcome is a three-way enum:
`refreshed`, `rejected` (clear the Keychain, post `authSessionDidInvalidate`,
back to sign-in) or `unavailable` (keep the session; the next call tries
again):

```swift
// loci/loci/Core/Network/AuthTokenProvider.swift:99
    switch response.code {
    case .unauthenticated, .invalidArgument, .permissionDenied, .notFound: return .rejected
    default: return .unavailable
    }
```

Everything about the constructor is injectable (`store`, `performRefresh`,
`onSessionEnded`, `now`), which is what `AuthTokenProviderTests` uses.

### withAuthRetry and the rpc helpers

A unary call that comes back `Unauthenticated` is retried once after a refresh.
Because the interceptor re-reads the Keychain, the retry carries the new token
without the caller doing anything:

```swift
// loci/loci/Core/Network/APIError+Connect.swift:9
nonisolated func withAuthRetry<Output>(
  tokens: AuthTokenProvider = .shared,
  _ call: @Sendable () async -> ResponseMessage<Output>
) async -> ResponseMessage<Output> {
  let first = await call()
  guard first.code == .unauthenticated else { return first }
  guard await tokens.refresh() != nil else { return first }
  return await call()
}
```

`rpc` wraps that and `unwrap`s the `ResponseMessage` into either the message or
a thrown `APIError`. There are two overloads, and the second exists because of
Swift 6: a `var request` built up before the call cannot be captured by a
`@Sendable` closure, so it is passed in as a parameter and copied instead.

```swift
// loci/loci/Core/Network/APIError+Connect.swift:59
nonisolated func rpc<Output>(_ fallback: String, _ call: @Sendable () async -> ResponseMessage<Output>) async throws -> Output {
  try await withAuthRetry(call).unwrap(fallback)
}

/// `rpc` with the request passed through, so a `var` built up before the call
/// is copied in rather than captured by the `@Sendable` closure.
nonisolated func rpc<Input: Sendable, Output>(
  _ fallback: String,
  _ request: Input,
  _ call: @Sendable (Input) async -> ResponseMessage<Output>
) async throws -> Output {
  try await withAuthRetry { await call(request) }.unwrap(fallback)
}
```

A typical call site, from the result page's side data:

```swift
// loci/loci/Features/Search/Services/ResultsAPI.swift:17
  static func localContext(latitude: Double, longitude: Double) async throws -> Loci_Localcontext_LocalContext {
    var request = Loci_Localcontext_GetLocalContextRequest()
    request.latitude = latitude
    request.longitude = longitude
    request.days = 5
    return try await rpc("Could not load the local forecast.", request) { await localContext.getLocalContext(request: $0, headers: [:]) }
  }
```

### APIError mapping, including quota reasons

`APIError` is a small `LocalizedError` enum (`unauthorized`, `forbidden`,
`notFound`, `conflict`, `network`, `server`, `custom`, `cancelled`).
`ResourceExhausted` reads the `x-loci-quota-reason` trailer the same way web's
`quota-error.ts` does and turns it into the two sentences web shows;
`canceled` becomes `.cancelled`, which views never show as a banner:

```swift
// loci/loci/Core/Network/APIError+Connect.swift:42
    case .unavailable, .deadlineExceeded: self = .network(message)
    case .canceled: self = .cancelled
    case .resourceExhausted:
      let reason = error.metadata.first { $0.key.lowercased() == "x-loci-quota-reason" }?.value.first
      switch reason {
      case "free_daily_limit": self = .custom("You've used today's 10 free searches. They reset at midnight UTC.")
      case "fair_use": self = .custom("You've hit today's fair-use limit. Access resets at midnight UTC.")
      default: self = .custom(message)
      }
```

Views surface errors through `Error.userMessage` and the `.errorAlert($error)`
modifier, both in `Features/Settings/UI/SettingsView.swift:44-72`.

### How a feature declares its clients

A feature keeps its generated clients as statics on a `nonisolated enum`, all
built on the shared transport. Settings has thirteen; the result page has six:

```swift
// loci/loci/Features/Settings/Services/SettingsClients.swift:6
nonisolated enum SettingsClients {
  private static var transport: ProtocolClientInterface { ConnectTransport.shared.protocolClient }

  static let auth = Loci_Auth_AuthServiceClient(client: transport)
  static let user = Loci_User_UserServiceClient(client: transport)
```

`ResultsAPI` (`Features/Search/Services/ResultsAPI.swift`) does the same and
adds one static function per RPC, each documenting the web call it mirrors.
Smaller features build a client inline at the call site, or share one through
a tiny enum (`TripAPI.client` in `TripsView.swift:53`).

## 6. State and data flow

There is no view-model layer. Screens hold `@State`, read the singletons
directly, and call `rpc` from `.task` or button actions. Where state must
outlive a screen or be observed from several places, it lives in an
`@Observable @MainActor` class (`SearchSessionController`, `AppRouter`,
`NearbyWalk`, `WalkTracker`, `HereBriefModel`, `ResultsSideData`). The
`ObservableObject`s left (`LoginViewModel`, `PushNotificationManager`) are
pre-slice code.

### SearchState: a reducer over stream events

`SearchState` is a plain value: everything one search has produced, plus the
bookkeeping a resume needs. `apply(_:)` takes a `Loci_Chat_StreamEvent`,
mutates the state, and returns an effect the controller acts on. The
deduplication key is `(event_id, payload case)` because the server reuses one
event id for several events:

```swift
// loci/loci/Features/Search/Model/SearchState.swift:138
  @discardableResult mutating func apply(_ event: Loci_Chat_StreamEvent) -> SearchEffect? {
    guard let payload = event.payload else { return nil }
    if !event.eventID.isEmpty {
      let key = "\(event.eventID)|\(payload.caseName)"
      guard seen.insert(key).inserted else { return nil }
      lastEventId = event.eventID
    }

    switch payload {
    case .start(let start):
      sessionId = start.sessionID
      domain = start.domain.routeName
      destination = SearchDestination(domain: start.domain.routeName)
      if start.hasCityName, !start.cityName.isEmpty { cityName = start.cityName }
      status = .streaming
      return link.map(SearchEffect.started)
```

The end of the switch encodes two web behaviours: an ERROR after places keeps
the places (`completedWithError`), and a COMPLETE whose result is empty must
not wipe what the `itinerary` event delivered (`hasContent`), while
`load_from_session` asks the controller for a fetch:

```swift
// loci/loci/Features/Search/Model/SearchState.swift:182
    case .error(let error):
      let message = error.userMessage.isEmpty ? "The search failed." : error.userMessage
      status = hasResult ? .completedWithError(message) : .failed(message)
      return .failed(message: error.userMessage, retryable: error.retryable)
    case .complete(let complete):
      if !complete.sessionID.isEmpty { sessionId = complete.sessionID }
      if complete.hasResult, complete.result.hasContent, destination == .itinerary || itinerary == nil {
        adopt(complete.result)
      }
      needsSessionFetch = complete.loadFromSession && !hasResult
      status = .completed
      return .completed
```

Derived views of the state (`places`, `dayGroups`, `extras`, `allPlaces`,
`phase`, `link`) are computed properties, so the UI never keeps a second copy.

### SearchSessionController: one live search, app-scoped

The controller is the only place a stream is opened. A search is not owned by
the screen that started it; leaving the screen or the app does not stop it.

```swift
// loci/loci/Features/Search/SearchSessionController.swift:13
/// Lifecycle, mirroring web's streamingService + resume-live.ts:
/// start → StreamChat → events reduced into `state` → envelope saved after each
/// event → COMPLETE/ERROR → local notification unless the user is looking at it.
/// Detached → on return, StreamChat{sessionId, resumeToken} replays what was
/// missed; if that ends without COMPLETE, GetChatSession is polled with backoff.
@MainActor @Observable final class SearchSessionController {
```

Its public surface is small: `state`, `startedLink` (set when the server names
the session, so the starting screen can push the results page),
`viewingSessionId` (suppresses the notification while that page is open),
`start(...)`, `stop()`, `state(for:)`, the two scene-phase hooks and the
background-refresh entry. Every event goes through `receive`, which reduces,
persists the envelope, and dispatches the effect:

```swift
// loci/loci/Features/Search/SearchSessionController.swift:138
  private func receive(_ event: Loci_Chat_StreamEvent) async {
    let effect = state.apply(event)
    if var envelope {
      envelope.sessionId = state.sessionId ?? envelope.sessionId
      envelope.lastEventId = state.lastEventId ?? envelope.lastEventId
      envelope.domain = state.domain ?? envelope.domain
      envelope.cityName = state.cityName ?? envelope.cityName
      self.envelope = envelope
      store.save(envelope)
    }
    switch effect {
    case .started(let link): startedLink = link
    case .completed:
      // COMPLETE with load_from_session: the result is stored, not streamed (web fetches it too).
      if state.needsSessionFetch, let sessionId = state.sessionId { await fetchStoredResult(sessionId: sessionId) }
      await finish()
```

`finish` (line 182) saves the phone's copy of the result (even a partial one:
"web keeps it and shows the error on the rail"), posts the local notification
unless `viewingSessionId` is this session and the app is in the foreground,
and clears the envelope.

Backgrounding starts a `UIBackgroundTask`; when iOS calls time, the client
stream is cancelled, the envelope kept, and a `BGAppRefreshTask` requested.
That task does one `GetChatSession` and either notifies or reschedules:

```swift
// loci/loci/Features/Search/SearchSessionController.swift:296
  static func registerBackgroundTask() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: reconcileTaskID, using: nil) { task in
      guard let task = task as? BGAppRefreshTask else { return }
      let work = Task { @MainActor in
        let done = await SearchSessionController.shared.reconcileInBackground()
        task.setTaskCompleted(success: done)
      }
      task.expirationHandler = { work.cancel() }
    }
  }
```

The identifier `com.fernandocorreia.loci.search-reconcile` is listed under
`BGTaskSchedulerPermittedIdentifiers` in `loci/Info.plist`, and
`AppDelegate.application(_:didFinishLaunchingWithOptions:)` calls
`registerBackgroundTask()` before anything can schedule it. Polling
(`pollUntilFinished`, line 221) backs off 2 s → 30 s and gives up at the
server's five-minute generation deadline plus a margin. "Finished" means the
session has a `currentItinerary` whose `updatedAt` is later than this search
started, because a follow-up reuses a session that already has a result.

### SearchEnvelope and SearchStore: what is persisted, where, why

Two kinds of file live in Application Support under `search/`:

```swift
// loci/loci/Features/Search/Model/SearchEnvelope.swift:5
/// What survives the app being suspended or killed mid-search: enough to
/// reattach (session id + resume token) and to rebuild the request. Mirrors
/// web's `sessionStorage["active_streaming_session"]` envelope.
nonisolated struct SearchEnvelope: Codable, Equatable, Sendable {
  var sessionId: String?
  var requestId: String
  var profileId: String?
  var lastEventId: String?
```

`SearchStore` (line 26) keeps two files "because GetChatSession cannot return
hotel, restaurant or activity lists". The envelope is JSON (`active-search.json`) written with
`.completeFileProtectionUntilFirstUserAuthentication`, so a background refresh
can read it while the phone is locked (the Keychain items use the matching
`AfterFirstUnlockThisDeviceOnly`). The result copy is a serialised
`Loci_Chat_StreamEvent` (`result-<sessionId>.bin`) whose `complete.result`
holds an `AiCityResponse` assembled from the state, with the domain lists in
the typed fields proto v5.22 added:

```swift
// loci/loci/Features/Search/Model/SearchEnvelope.swift:58
    payload.hotels = state.hotels
    payload.restaurants = state.restaurants
    payload.activities = state.activities
    if payload.pointsOfInterest.isEmpty { payload.pointsOfInterest = state.generalPOIs }
    payload.sessionID = sessionId
    snapshot.complete.result = payload
```

Reusing the proto as the on-disk format means the restore path
(`SearchState.restored(link:result:text:)`, line 81) is the same whether the
`AiCityResponse` came from disk or from `GetChatSession`, and a copy written
before v5.22 still restores through `pointsOfInterest`.

### ResultsSideData

The result page fetches three things beside the stream: local context
(forecast, alerts), FX rates and the viewer's plan. They are cached in statics
for the life of the process so reopening a page does not refetch, and every
path is short-circuited when a design preview is running:

```swift
// loci/loci/Features/Search/UI/Results/ResultsSideData.swift:20
  /// Offline pages (the design preview) never touch the network.
  static var isOffline: Bool { DesignPreview.requested != nil }
```

### How a results page gets its state

`SearchResultsView` is keyed by a `SessionLink`. It shows the live state when
the controller's session is this one, otherwise whatever it restored:

```swift
// loci/loci/Features/Search/UI/SearchResultsView.swift:28
  private var state: SearchState? {
    controller.state.sessionId == link.sessionId ? controller.state : restored
  }
```

Restoration follows web's `restoreOrHydrateSession` order: live search, this
phone's copy, then the server:

```swift
// loci/loci/Features/Search/SearchSessionController.swift:333
  func state(for link: SessionLink) async -> SearchState? {
    if state.sessionId == link.sessionId { return state }
    if let saved = store.loadResult(for: link) { return saved }
    var request = Loci_Chat_GetChatSessionRequest()
    request.sessionID = link.sessionId
    guard let session = try? await rpc("", request, { await self.chat.getChatSession(request: $0, headers: [:]) }).session,
      session.hasCurrentItinerary
    else { return nil }
    let restored = SearchState.restored(link: link, result: session.currentItinerary)
    return restored.hasResult ? restored : nil
  }
```

If all three fail the page shows "Search not found" with a re-run button.

## 7. Streaming search end to end

1. **Composer.** `SearchComposer` (`Features/Search/UI/SearchComposer.swift`)
   is the one search box. Send calls `controller.start(...)`; if a search is
   already running it asks first. It watches `controller.startedLink` and calls
   `onStarted` once the server has named the session, which is what pushes the
   results page:

   ```swift
   // loci/loci/Features/Search/UI/SearchComposer.swift:74
       .onChange(of: controller.startedLink) { _, link in
         guard awaitingStart, let link else { return }
         awaitingStart = false
         onStarted(link)
       }
   ```

2. **start.** `SearchSessionController.start` (line 60) resolves the default
   travel profile (unless `useDefaultProfile: false`, which Discover and Nearby
   pass, as web sends `profileId: ""` there), stops any running search, asks
   for notification permission once, writes a fresh envelope, resets `state`,
   and opens the stream with `request(from:resuming: false)`.

3. **ChatStreamClient.** Wraps `ChatService.StreamChat` in an
   `AsyncThrowingStream` (`events(_:)`, line 15). If the stream fails as
   `Unauthenticated` before the first event, it refreshes the token once and
   reopens; `continuation.onTermination` cancels the underlying stream. The
   inner `run` is shown in section 10.

4. **Events → reducer.** `open` iterates the stream on a `Task` and hands each
   event to `receive`, which calls `state.apply` (section 6). A clean end
   without COMPLETE means "detached", and polling takes over; a network error
   mid-stream is also "detached", not "failed".

5. **Rendering.** `SearchResultsView` draws the query as the user bubble and
   `ResultsPage` inside the agent bubble. `ResultsPage` renders skeleton cards
   while `state.hasResult` is false and the search is active, then the
   structured result. **Tokens are never rendered.** The server streams `token`
   events from three parallel workers, so the concatenated text is the model's
   raw JSON interleaved; web shows skeletons then the parsed result, and
   PR #10 made iOS do the same. `state.text` still accumulates (it feeds the
   "is writing" status and is saved with the result), but nothing displays it.

   ```swift
   // loci/loci/Features/Search/UI/Results/ResultsPage.swift:4
   /// The body of the agent bubble on a result page, in web's `/itinerary`
   /// order: city header, forecast and money, status rail, title and summary,
   /// map hero, the days, "More to explore", the Trip Kit. Tokens are never
   /// shown; the structured events are the answer.
   ```

6. **Resume.** On return to the foreground with an unfinished envelope,
   `resume` rebuilds a placeholder state and reopens the stream with
   `sessionId` and `resumeToken = lastEventId`. Without a token it only polls,
   because a StreamChat without one would start the search again and spend
   quota:

   ```swift
   // loci/loci/Features/Search/SearchSessionController.swift:377
       if resuming, let token = envelope.lastEventId { request.resumeToken = token }
       return request
   ```

7. **load_from_session.** When COMPLETE says the result is stored rather than
   streamed and nothing has arrived, `fetchStoredResult` (line 250) fetches
   `GetChatSession` and adopts `currentItinerary`.

8. **Notification and deep link.** `SearchNotifier.post` builds a local
   notification whose `userInfo` is `link.userInfo`, with identifier
   `search-<sessionId>` so a later post replaces the earlier one:

   ```swift
   // loci/loci/Features/Search/Services/SearchNotifier.swift:18
       content.userInfo = link.userInfo
       content.threadIdentifier = "search"

       // One notification per session: a later post for the same search replaces it.
       let request = UNNotificationRequest(identifier: "search-\(link.sessionId)", content: content, trigger: nil)
       try? await center.add(request)
   ```

   The keys are the three the planned server push will also carry:

   ```swift
   // loci/loci/Core/Routing/AppRouter.swift:33
     public enum Key {
       public static let sessionId = "sessionId"
       public static let cityName = "cityName"
       public static let domain = "domain"
     }
   ```

   A tap lands in `PushNotificationManager.userNotificationCenter(_:didReceive:)`
   (line 85), which does `SessionLink(userInfo:)` then `AppRouter.shared.open(link)`.
   A `loci://itinerary?sessionId=…` URL from `onOpenURL` takes the same path
   through `SessionLink(url:)`; the host is the web route (`itinerary`,
   `hotels`, `restaurants`, `activities`) and `loci://oauth2redirect/*` is
   rejected so `ASWebAuthenticationSession` keeps it. `AppRouter.open` selects
   the Ask Loci tab and sets `pendingSession`; `AssistantView.openPending`
   (`AssistantView.swift:91`) clears it and sets the navigation path to
   `[link]`, which pushes `SearchResultsView(link)`.

The full failure-case table (permission denied, app killed, resume buffer
evicted, duplicate event ids, no token, quota) is in
[`../ios-search-notifications.md`](../ios-search-notifications.md).

## 8. Screens

### Auth

Mirrors web sign-in. RPCs: `AuthService.Login`, `VerifyMFA`, `Register`,
`ForgotPassword`, `Logout`, `RefreshToken`; `CustomAuthService.SignInWithIDToken`
for the two native providers. Table in [`02-auth.md`](02-auth.md).

Both native sheets return a provider ID token that goes straight to the
server. The shared half is `NativeSignIn`: a 32-byte URL-safe nonce, and the
exchange. Apple is given the SHA-256 of the nonce (that digest is what Apple
puts in the token), Google the nonce itself; the server always gets the raw
value:

```swift
// loci/loci/Features/Auth/Services/NativeSignIn.swift:26
  /// Lowercase hex SHA-256, the form Apple puts in the token's `nonce` claim.
  public static func sha256Hex(_ value: String) -> String {
    SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
  }
```

```swift
// loci/loci/Features/Auth/Services/AppleSignInService.swift:20
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = [.fullName, .email]
    request.nonce = NativeSignIn.sha256Hex(nonce)
```

`AppleSignInService` bridges the delegate-based `ASAuthorizationController`
to async with a `CheckedContinuation`; the delegate callbacks are
`nonisolated` and hop back with `MainActor.assumeIsolated`
(`AppleSignInService.swift:63-74`). `GoogleAuthService` uses the GoogleSignIn
SDK with the iOS client id and signs the SDK out afterwards so Loci keeps the
only session. The old web-OAuth path (bouncing through lociai.fyi) is gone for
sign-in; `OAuthWebAuth` keeps its helpers for calendar connect, including the
fix for the bug that made TestFlight fail (returning a `UIWindow` that is not
in the hierarchy). Cancel on either sheet is `APIError.cancelled`, which
`LoginViewModel` swallows.

Known gaps (`10-in-season.md`): the Google button is an SF Symbol "G", not
Google's mark; no browsing before sign-in.

### Discover

Mirrors `/discover`. RPCs: `DiscoverService.GetDiscoverPage`, `GetTrending{limit: 8}`
(for the band), `LocalContextService.GetHereBrief`, and `StreamChat` without a
profile. Tables in [`04-discover.md`](04-discover.md) and
[`10-in-season.md`](10-in-season.md).

The screen is a `NavigationStack` with a `[SessionLink]` path, so a search
started here pushes `SearchResultsView` in place. The page and the here brief
load concurrently:

```swift
// loci/loci/Features/Discover/UI/DiscoverView.swift:49
      .task {
        async let brief: Void = here.load()
        if page == nil { await load() }
        await brief
      }
```

**Here brief.** `HereBriefModel` only loads when location is already
authorised; Discover never raises the prompt (Nearby owns it). Coordinates are
rounded to two decimals before they leave the phone:

```swift
// loci/loci/Features/Discover/UI/HereBriefSection.swift:22
  func load() async {
    let status = CLLocationManager().authorizationStatus
    guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
    guard let coord = try? await CurrentLocation.fetch(timeout: .seconds(8)) else { return }
    var req = Loci_Localcontext_GetHereBriefRequest()
    req.latitude = (coord.latitude * 100).rounded() / 100
    req.longitude = (coord.longitude * 100).rounded() / 100
    let res = await SettingsClients.localContext.getHereBrief(request: req, headers: [:])
    if let message = res.message { brief = message }
  }
```

Note this call bypasses `rpc` (no retry, errors dropped); the section simply
stays hidden.

**In-season marquee.** `InSeason.items` merges the curated month table
(`SeasonalPicks`) with trending cities exactly as web's `buildInSeasonItems`.
The motion is a `TimelineView` whose offset is a pure read of the clock, so a
pause holds the strip where it is and nothing is written per frame:

```swift
// loci/loci/Features/Discover/UI/InSeasonBand.swift:175
  private func progress(at date: Date) -> Double {
    let elapsed = banked + (runningSince.map { date.timeIntervalSince($0) } ?? 0)
    let loop = max(loopDuration, 1)
    return elapsed.truncatingRemainder(dividingBy: loop) / loop
  }
```

Two copies of the content sit in an `HStack` with the same gap between and
after, so the seam lands exactly. Reduce Motion, or fewer than five chips,
gives a plain horizontal scroll.

### Search results

Mirrors `/itinerary`, `/hotels`, `/restaurants`, `/activities`. RPCs beside
the stream: `GetLocalContext`, `GetFxRates`, `GetSubscription`,
`GetPlaceFacts`, `AddToFavorites`, `ExportItineraryToPDF`, `BookmarkItinerary`,
`GetChatSession`. The piece-by-piece table against web is in
[`12-results-parity.md`](12-results-parity.md).

The page is the Muse chat chrome (`MuseChatHeader` in a top safe-area inset,
Stop or a follow-up composer at the bottom, navigation bar hidden with
`interactivePopEnabled()` keeping swipe-back) around `SearchTranscript`, which
is the query bubble plus one agent bubble containing `ResultsPage`
(`ResultsPage.swift:43-75` is the body; the pieces below appear in that order,
with `SkeletonCards` in place of `results` while the search is active and
nothing has landed).

Pieces, in order:

- `ResultsHeader`: city, country, description and four tiles, `redacted` until
  `city_data` lands.
- `LocalContextStrip`: forecast, alerts and FX from `ResultsSideData`.
- `StatusRail`: "Sketching your days…" / "Adding photos n/total" /
  "Itinerary ready · N stops", driven by `SearchState.phase`.
- `ResultsMapCard`: a 260 pt non-interactive MapKit hero with numbered
  day-coloured pins, one dashed `MapPolyline` per day and a `MapCircle` halo
  per geolocated alert; any tap opens `FullMapView`, a full-screen map with the
  stop list in a detent sheet (the Nearby shape). `ResultsMapData` precomputes
  pins, routes and halos so the two maps share content.
- `DaySection` / `StopCard` / `PlaceImage`: the first two days open, then
  "Show the rest". `PlaceImage` prefers `image_credits[0]`, then `images[0]`,
  then a gradient hashed from `stableID`.
- `PlaceDetailSheet`: credited gallery, stat tiles, `GroundedBadge`, verified
  facts from `GetPlaceFacts` (only when the POI has a real id and the page is
  not a preview), contact rows, Save / Share / Apple Maps / Google Maps.
- `TripKitView`: Apple Maps per day, Google Maps multi-stop URL, one EventKit
  event per stop from a chosen start date, PDF via `ShareLink`. The Pro gate is
  computed from the cached plan:

```swift
// loci/loci/Features/Search/UI/Results/TripKitView.swift:23
  private var unlocked: [DayGroup] { ProGate.unlocked(groups, isPro: side.isPro) }
  private var gated: Bool { !side.isPro && groups.count > 1 }
  private var checking: Bool { !side.planChecked }
```

The model half lives in `DayGrouping.swift`: `DayGrouping.groups` (server
`day` when any stop has one, else chunks of four, groups labelled by
position), `DayGrouping.extras` ("More to explore"), `ShareText.build`,
`GoogleMapsRoute.url` (≤ 8 waypoints, `lat,lng` or `name, address, city`),
`CalendarSchedule.events` (09:00 start, 90 min default, 15 min buffer) and
`ProGate`:

```swift
// loci/loci/Features/Search/Model/DayGrouping.swift:34
  static func groups(_ stops: [Loci_Poi_POIDetailedInfo]) -> [DayGroup] {
    let sorted = ordered(stops)
    guard sorted.contains(where: \.hasDay) else {
      return stride(from: 0, to: sorted.count, by: stopsPerDay).enumerated().map { index, start in
        DayGroup(number: index + 1, stops: Array(sorted[start..<min(start + stopsPerDay, sorted.count)]))
      }
    }
```

```swift
// loci/loci/Features/Search/Model/DayGrouping.swift:205
  static let proPlans: Set<String> = ["premium_monthly", "premium_annual", "premium", "pro", "paid", "explorer"]
```

Known gaps (`12-results-parity.md`): no `EditTripCTA` because the Swift
`CompletePayload` has no `navigation` field; no StoreKit (the Pro line links
to `/pricing`); hotel and restaurant detail RPCs not used; the proto's
per-stop `part` on tokens not used.

### Nearby

Mirrors `/nearme`. RPCs: `StreamChat` with web's exact sentence and
`cityName: "nearme"`, no profile. Table in [`05-nearby.md`](05-nearby.md);
the walk in [`11-nearby-walk.md`](11-nearby-walk.md).

Map first, list in a detent sheet that cannot be dismissed. The screen filters
the controller's state to its own session so another running search does not
paint its pins:

```swift
// loci/loci/Features/Nearby/UI/NearbyView.swift:33
  private var places: [Loci_Poi_POIDetailedInfo] {
    guard let sessionId, controller.state.sessionId == sessionId else { return [] }
    return controller.state.allPlaces.filter { $0.hasLatitude && $0.hasLongitude }
  }
```

The location fix is one `CLServiceSession` plus `CLLocationUpdate.liveUpdates()`
raced against a timeout in a task group (`Core/Location/CurrentLocation.swift:17-36`).

**NearbyWalk** starts three things on one button: the pedometer, the
geofences and the Live Activity, and keeps a location session open for the
walk (with the `location` background mode, this is what keeps it alive while
the phone is locked):

```swift
// loci/loci/Features/Nearby/Services/NearbyWalk.swift:34
    tracker.start()
    await proximity.arm(places: places, from: coordinate)
    startActivity(radiusKm: radiusKm)
```

`WalkTracker` wraps `CMPedometer.startUpdates` and hops each callback onto the
main actor with `Task { @MainActor in … }`; a permission refusal sets
`deniedByUser` and the walk continues without a count. No HealthKit.

`POIProximityMonitor` uses `CLMonitor` with one `CircularGeographicCondition`
of 60 m per place, the 20 nearest, because CLMonitor caps conditions at 20.
Conditions persist across launches, so `disarm` removes every identifier on
Stop:

```swift
// loci/loci/Features/Nearby/Services/POIProximityMonitor.swift:26
    // Drop fences that are no longer on the list, then add the new ones.
    let wanted = Set(chosen.map(\.stableID))
    for identifier in await monitor.identifiers where !wanted.contains(identifier) { await monitor.remove(identifier) }
```

The Live Activity is throttled to one update per 5 s and ended immediately on
Stop. The attributes type is compiled into both targets:

```swift
// loci/loci/Shared/NearbyWalkAttributes.swift:7
public nonisolated struct NearbyWalkAttributes: ActivityAttributes {
  public nonisolated struct ContentState: Codable, Hashable, Sendable {
    public var steps: Int
    public var distanceMeters: Double
    public var placesNearby: Int
```

`NearbyWalkWidget/NearbyWalkLiveActivity.swift` draws the Lock Screen view and
the three Dynamic Island regions from that state. Known gap: never run on a
real phone (no pedometer in the simulator).

### Ask Loci and the Muse chat

Mirrors `/chat`. RPCs: `GetChatSessions{pagination{1, 25}}`, `StreamChat`.
Table in [`06-search.md`](06-search.md); the visual contract in
[`../../../_reviews/muse-chat-contract.md`](../../../_reviews/muse-chat-contract.md).

`AssistantView` is the tab root: a "Running now" section for the live search,
"Recent" sessions, the Muse header in the top inset, the composer in the
bottom inset. `MuseChatHeader` draws a 40 pt circular button, a "New chat"
pill, the 110 pt avatar with a ring, and a pill with the agent name and
status. `MuseActivity.resolve` is a pure function from search status to mood
and copy, so every state is unit-tested without a screen:

```swift
// loci/loci/Features/Chat/MuseActivity.swift:49
    switch status {
    case .streaming:
      if let stage = stagePhrase(progressStage) { return MuseActivity(mood: .working, status: "is \(stage)") }
      return MuseActivity(mood: .working, status: hasText ? "is writing" : "is thinking")
    case .detached:
      return MuseActivity(mood: .working, status: "is still working — you can leave")
```

Below that, a `Flash` wins ("found N places" / "hit a snag"), then the
composer ("is listening"), then `.ready`. The two momentary states (celebrating for 1.2 s, "hit a snag" for 3 s) are a
`Flash` the screen holds via the `museFlash` modifier, which watches status
transitions and clears the flash on a timer (`MuseChatHeader.swift:234-246`).
`stagePhrase` drops machine names (`intent_classified`), lowercases a leading
capital unless it is an acronym, and cuts at the contract's 32 characters.

`MuseBubble` is the one bubble type: user (coral, right, 85 % width) or agent
(card, left, 94 % width), no avatar or name label per message. The working
ring is a `TimelineView` arc that turns once per 1.4 s; under Reduce Motion
it is a static stroke.

### Trips editor

Mirrors `/trips` and `/trips/:id`. RPCs: `ListTrips`, `GetTrip`,
`ReorderStops`, `RenameStop`, `EditStopDuration`, `SetConstraint`, `SearchPOI`
+ `AddStop`, `ReplaceStop`, `RemoveStop`, `ShareTrip`, `ExportTrip`,
`SuggestPacking`, plus EventKit. Table in [`07-trips.md`](07-trips.md).

The whole editor is one pattern: every edit sends `baseVersion = trip.version`
and adopts the `TripDraft` the server returns, so a stale edit from another
device is refused rather than merged:

```swift
// loci/loci/Features/Trips/UI/TripEditorView.swift:167
  /// Run an edit and adopt the trip the server returns.
  private func apply<Input: Sendable>(
    _ fallback: String,
    _ request: Input,
    _ call: @escaping @Sendable (Input) async -> ResponseMessage<Loci_Trip_TripDraft>
  ) async {
    do { trip = try await rpc(fallback, request, call) } catch { self.error = error.userMessage }
  }
```

Each mutation (`reorder`, `rename`, `setDuration`, …, lines 176-260) builds
its request, sets `request.baseVersion = trip.version`, and calls `apply`.
Gap: Pro-only export limits are the server's message, shown as-is.

### Compare

Mirrors `/compare`. RPCs: `CompareWeekend{originCity, candidateCityNames, startDate, endDate}`,
`SaveTrip{trip, baseVersion: 0}` for the three save paths. Table in
[`08-compare.md`](08-compare.md).

```swift
// loci/loci/Features/Compare/UI/CompareView.swift:9
  /// web: lib/compare-presets.ts COMPARE_PRESETS
  static let presets: [(origin: String, candidates: [String])] = [
    ("Porto", ["Évora", "Beja"]), ("Lisbon", ["Sintra", "Óbidos"]), ("Madrid", ["Toledo", "Segovia"]),
  ]
```

`CompareView.defaultWeekend(now:calendar:)` is the coming Saturday to Sunday
(a week ahead when today is Saturday), covered by `ParityPayloadTests`. Gap:
web's city autocomplete (`CityService.SearchCities`) is not carried over.

### Saved

Mirrors `/saved` (`/favorites` and `/bookmarks` redirect there). RPCs:
`GetFavorites{userId, limit: 1000}`, `RemoveFromFavorites`,
`GetUserItineraries{pagination{1, 100}}`, `DeleteBookmark`. Table in
[`09-saved.md`](09-saved.md). A segmented picker switches Places and
Itineraries; swipe actions remove. Gap: no offline copy (web has IndexedDB;
SwiftData is Phase 2).

### Settings, including MCP

Mirrors every `/settings?tab=` except Billing. The screen → service → RPC
table with the fields sent is in [`03-settings.md`](03-settings.md); the
entry list is `SettingsView.swift:8-36`.

Two patterns worth reading. `ProfileDraft.changes(from:)` sends only changed,
non-empty fields, because every param is `optional` with `min_len: 1` on the
server, so an empty string marked present is rejected:

```swift
// loci/loci/Features/Settings/UI/AccountProfileView.swift:99
  func changes(from old: ProfileDraft) -> Loci_User_UpdateProfileParams {
    var params = Loci_User_UpdateProfileParams()
    func set(_ new: String, _ previous: String, _ apply: (String) -> Void) {
      let trimmed = new.trimmingCharacters(in: .whitespacesAndNewlines)
      if !trimmed.isEmpty, trimmed != previous { apply(trimmed) }
    }
    set(displayName, old.displayName) { params.displayName = $0 }
```

And the MCP screen shows the endpoint from the transport and the server-built
setup snippets, rather than composing any config on the phone:

```swift
// loci/loci/Features/Settings/UI/ConnectionsView.swift:9
      Section {
        LabeledContent("MCP endpoint") {
          Text(ConnectTransport.shared.mcpEndpoint.absoluteString).font(.lociCoord(12)).textSelection(.enabled)
        }
```

The four sections that follow (`McpKeysSection`, `ModelProviderSection`,
`TelegramSection`, `OutboundConnectionsSection`) are web's four cards.

`McpKeysSection` calls `ListApiKeys`, `CreateApiKey{name, scopes, clientKind}`
(plaintext shown once), `RevokeApiKey`, and `GetSetupInstructions{clientKind}`
(`ConnectionsView.swift:198-203`). Gap: none of these screens has been run
signed in.

### Calendar

Mirrors the trips calendar and `ConnectedCalendars`. RPCs: `ListTrips`
(month grid), `CalendarService.ListCalendarConnections`, `StartCalendarConnect`
(Google Calendar or Calendly through `ASWebAuthenticationSession`),
`GetTripCalendarFeedUrl`. EventKit for the device calendar.

`AppleCalendar` owns the `EKEventStore`, asks for full access, and writes into
a calendar named "Loci", created on first use. `writeTrip` makes one event per
trip day; `writeStops` (used by the Trip Kit) makes one per stop in a single
commit:

```swift
// loci/loci/Features/Calendar/AppleCalendar.swift:48
  @discardableResult func writeStops(_ events: [StopEvent]) throws -> Int {
    guard isAuthorized else { throw APIError.custom("Calendar access was not granted.") }
    let cal = try lociCalendar()
```

Each stop becomes an `EKEvent` saved with `commit: false`, then one
`store.commit()` (lines 51-62).

`CalendarMath` (`monthCells`, Monday-first grid, `dateKey`) is pure and tested.
Gap: the Google Calendar and Calendly connect flows are coded, but nothing in
this repo records them working against a configured provider.

## 9. Design system

`LociTheme.swift` is the only place tokens live, and its header says where
they come from: `loci-client/docs/NATIVE_DESIGN.md`, "change them there first".

**Colours** are `Color.loci*` statics built with a `dynamic(light:dark:)`
helper over a `UIColor` trait closure, so dark mode is free everywhere:

```swift
// loci/loci/Core/Theme/LociTheme.swift:62
  nonisolated private static func dynamic(light: UInt32, dark: UInt32) -> Color {
    Color(
      UIColor { trait in
        let hex = trait.userInterfaceStyle == .dark ? dark : light
```

```swift
// loci/loci/Core/Theme/LociTheme.swift:78
  static let lociPaper = dynamic(light: 0xF5F0E6, dark: 0x101A16)
  /// foreground
  static let lociInk = dynamic(light: 0x1A2E26, dark: 0xEDE8DC)
  /// card
  static let lociCard = dynamic(light: 0xFDFBF7, dark: 0x162019)
  /// primary
  static let lociForest = dynamic(light: 0x214D3C, dark: 0xA8B896)
```

Where NATIVE_DESIGN gives no dark value (`muted`, `mutedForeground`,
`destructive`) the comment says which source the dark value came from.

**Fonts** are bundled (`Resources/Fonts`, listed in `UIAppFonts`) and exposed
as `Font.loci*` functions that scale with Dynamic Type through `relativeTo:`:

```swift
// loci/loci/Core/Theme/LociTheme.swift:119
  static func lociDisplay(_ size: CGFloat = 34) -> Font {
    .custom("Fraunces", size: size, relativeTo: .largeTitle).weight(.semibold)
  }
```

`lociTitle` (Fraunces), `lociHeadline`, `lociBody`, `lociCaption` (DM Sans)
and `lociCoord` (Space Mono) follow the same shape (lines 117-125).

**Radii, motion, day palette.** `cornerRadius` 12.8, `cornerRadiusHero` 14.4,
`minTapTarget` 44, `defaultPadding` 16. The animations are named after
NATIVE_DESIGN's table, and `reducedFade` is what every Reduce Motion branch
uses:

```swift
// loci/loci/Core/Theme/LociTheme.swift:17
  public static let resultArrive = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.4)
  /// A selection settling: 250ms, cubic-bezier(0.22, 1, 0.36, 1).
  public static let selectionSettle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.25)
  /// What Reduce Motion falls back to: a short fade, no movement.
  public static let reducedFade = Animation.easeOut(duration: 0.2)

  /// Map day colours, in order (day 1 first). Cycle past day 8.
  /// Web's `LOCI_DAY_COLORS` (loci-client/src/lib/theme-colors.ts), same order
  /// and the same indexing: the server's 1-based day picks `dayColors[day % 8]`,
  /// so Day 1 is pine teal on both, and a one-day list (day 0) is coral.
  public static let dayColors: [Color] = [0xE2664A, 0x2F7D6E, 0xB07A2A, 0x7A5CA8, 0x4A7CB0, 0x8C6248, 0x5E8C3A, 0xA34F72].map { Color(hex: $0) }
  public static let clusterColor = Color(hex: 0x294D3C)
  public static let ungroupedColor = Color(hex: 0x6E7A82)

  public static func dayColor(_ day: Int) -> Color { dayColors[max(day, 0) % dayColors.count] }
  /// Web's `colorForMapDay(0)`: the pins and stamps of a list that has no days.
  public static var listColor: Color { dayColor(0) }
```

The indexing rule is web's `colorForMapDay`: the server's 1-based day picks
`dayColors[day % 8]`, so day 1 is pine teal, day 8 wraps to coral, and a list
with no days (day 0, `listColor`) is coral. Extras use `ungroupedColor`. The
palette is web's `LOCI_DAY_COLORS` in the same order since PR #12; NATIVE_DESIGN
§map palette was corrected to match (loci-client #68).

**Modifiers.** `.lociCard(padding:)` is the flat card (fill, 1 px border,
continuous corners, no shadow); `.lociCoordStyle(size)` is Space Mono,
uppercase, 1.2 tracking, muted ink:

```swift
// loci/loci/Core/Theme/LociTheme.swift:140
  func lociCard(padding: CGFloat = LociTheme.cardPadding) -> some View {
    self.padding(padding).background(Color.lociCard)
      .clipShape(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
      .overlay(
        RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).stroke(Color.lociBorder, lineWidth: LociTheme.borderWidth)
      )
  }
```

**Muse contract values** are a nested `LociTheme.Muse` enum (bubble radius 24,
avatar 110, header button 40, scrim 120, bubble widths 0.85 / 0.94, ring 3 pt
at 5 pt inset) plus `Color.muse*` tokens mapped from the contract's table
(`LociTheme.swift:33-46`, `93-107`) and three `Font.muse*` styles (17/22 body,
15 semibold name, 13 status).

**Reduce Motion** is read with `@Environment(\.accessibilityReduceMotion)`
in every animated view and swaps to `reducedFade` or `.identity`: result
arrival, the celebration scale, the ring (static stroke), the marquee (plain
scroll), chip press scale (off). The contract's "no float or bob" is met by
the avatar never moving.

**DesignPreview.** Launching a Debug build with `-designPreview <case>` shows
one component with sample data and no account; `lociApp` checks it before
anything else, and `ResultsSideData.isOffline` keeps previews off the network:

```swift
// loci/loci/Core/DesignPreview.swift:35
  static var requested: DesignPreview? {
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "-designPreview"), index + 1 < arguments.count else { return nil }
      return DesignPreview(rawValue: arguments[index + 1])
    #else
      return nil
    #endif
  }
```

Cases: `inSeason`, `museChat`, `museChatStreaming`, `museChatThinking`,
`museChatStage`, `museChatDetached`, `museChatCelebrating`, `museChatSnag`,
`museChatListening`, `museChatPush`, `museChatPushBar`, `results`,
`resultsDays`, `resultsKit`, and (parity pass 2) `youHub`, `recents`, `recentsCities`, `recentCity`. To screenshot one on a booted simulator (or set
the argument in the scheme's Run action):

```text
xcrun simctl launch booted com.fernandocorreia.loci.beta -designPreview results
xcrun simctl io booted screenshot results.png
```

## 10. Concurrency patterns worth studying

**An actor for the one thing that must serialise.** `AuthTokenProvider`
(section 5) keeps `inFlight: Task<String?, Never>?` as actor state; the actor
guarantees the check-then-set in `refresh()` cannot interleave.

**`@Observable @MainActor` classes for shared, screen-crossing state.** With
default MainActor isolation the annotation is documentation as much as
enforcement; it is written out on every controller anyway:

```swift
// loci/loci/Core/Motion/WalkTracker.swift:8
@MainActor @Observable final class WalkTracker {
  private(set) var steps = 0
  private(set) var distanceMeters: Double = 0
```

**`nonisolated` value types for models and proto helpers.** Extensions on
generated types are `nonisolated` so they can be used from any context:

```swift
// loci/loci/Features/Search/Model/SearchState.swift:248
nonisolated extension Loci_Poi_POIDetailedInfo {
  /// A key for ForEach and map selection. The server sometimes sends places
  /// with no id, so those fall back to name plus coordinates.
  var stableID: String { id.isEmpty ? "\(name)|\(latitude)|\(longitude)" : id }
}
```

**`Task` lifecycle in views with `.task(id:)`.** Restoration re-runs when the
link changes and is cancelled when the view disappears; the same modifier
drives context loading keyed on the city's coordinates
(`ResultsPage.swift:59`) and the flash timer keyed on the flash value
(`MuseChatHeader.swift:241`):

```swift
// loci/loci/Features/Search/UI/SearchResultsView.swift:69
    .task(id: link.sessionId) { await restoreIfNeeded() }
    .onAppear { controller.viewingSessionId = link.sessionId }
    .onDisappear { if controller.viewingSessionId == link.sessionId { controller.viewingSessionId = nil } }
```

**`AsyncThrowingStream` over the RPC stream.** `ChatStreamClient.run` reads
`stream.results()` inside `withTaskCancellationHandler` so a cancelled
consumer cancels the Connect stream, and classifies the `.complete` code into
finished / retry / cancel / error:

```swift
// loci/loci/Features/Search/Services/ChatStreamClient.swift:47
    return try await withTaskCancellationHandler {
      for await result in stream.results() {
        switch result {
        case .headers: continue
        case .message(let event):
          sawEvent = true
          continuation.yield(event)
        case let .complete(code, error, _):
          if code == .ok { return .finished }
          if code == .unauthenticated, !sawEvent { return .unauthenticatedBeforeFirstEvent }
          if code == .canceled { throw CancellationError() }
          let connectError = error as? ConnectError ?? ConnectError(code: code, message: nil, exception: error)
          throw APIError(connect: connectError, fallback: "The search stopped.")
        }
      }
      return .finished
    } onCancel: {
      stream.cancel()
    }
```

**Racing an async sequence against a timeout.** `CurrentLocation.fetch` adds
the location loop and a `Task.sleep` to a throwing task group and takes the
first result:

```swift
// loci/loci/Core/Location/CurrentLocation.swift:28
      group.addTask {
        try await Task.sleep(for: timeout)
        throw Failure.unavailable
      }
      defer { group.cancelAll() }
      guard let first = try await group.next() else { throw Failure.unavailable }
      return first
```

**Delegate callbacks back onto the main actor.** Apple's authorisation
delegate methods are `nonisolated` and use `MainActor.assumeIsolated`:

```swift
// loci/loci/Features/Auth/Services/AppleSignInService.swift:64
  public nonisolated func authorizationController(
    controller: ASAuthorizationController,
    didCompleteWithAuthorization authorization: ASAuthorization
  ) {
    MainActor.assumeIsolated { finish(.success(authorization)) }
  }
```

The pedometer callback uses `Task { @MainActor in … }` (`WalkTracker.swift:27`);
the background-task expiry handler does the same
(`SearchSessionController.swift:266`).

**`@preconcurrency import ActivityKit`** (section 3) and **`Sendable` on the
extension-shared type**: `NearbyWalkAttributes.ContentState` is
`Codable, Hashable, Sendable` because ActivityKit serialises it across the
process boundary and the app builds it off the main actor.

**`BGTaskScheduler` registration at launch** (section 6): register in
`didFinishLaunching`, submit from the expiry handler, complete the task from a
`@MainActor` `Task` and cancel that task in `expirationHandler`.

**One reader per stream.** The controller owns `streamTask`; a results screen
never spawns its own reader, and `streamEnded` keeps `streamTask` set while
polling so a return to the foreground cannot start a second one
(`SearchSessionController.swift:159-168`).

## 11. Testing

All unit tests are Swift Testing (`import Testing`, `@Test`, `#expect`,
`#require`); the only XCTest is the UI target. `fastlane test` runs
`lociTests` on the `loci Beta` scheme; PR #10 reports 74 passing.

| File | Covers |
|---|---|
| `loci/lociTests/AuthTokenProviderTests.swift` | Valid token returned without refresh; 8 concurrent callers make 1 refresh and all get the new token; rejected refresh ends the session; unreachable server keeps it |
| `loci/lociTests/SearchStateTests.swift` | Reducer: start → route, token order, replay dedup, same id different payload kept, complete/error; `SearchStore` envelope and result round trips; resume request fields; notification titles. Also defines `Events` |
| `loci/lociTests/ResultsParityTests.swift` | Day grouping (server days, chunks of four, extras, sequence), share text shape, Google Maps URL (coordinates, 8 waypoints, name fallback), calendar timing, Pro gate, reducer partial failure and `load_from_session`, list restore incl. pre-v5.22 fallback, image choice, meta line |
| `loci/lociTests/MuseActivityTests.swift` | Every status → mood/copy case, flash rules (stop is not a snag, opening a finished search earns nothing), `stagePhrase`, a full stream walk-through |
| `loci/lociTests/SessionLinkTests.swift` | Deep link parsing for every route, rejects `oauth2redirect` and incomplete links, URL/userInfo round trip, domain → destination map |
| `loci/lociTests/RecentsBucketsTests.swift` | Mirrors web's `day-buckets.test.ts`: local-midnight boundaries, group order, undated rows, `relativeTime` steps |
| `loci/lociTests/ActivityMappingTests.swift` | Proto → feed entry (kind, detail defaults), prompt-wrapper unwrapping, paging (`hasMore`, the 200 cap), chip counts and filters, badges, city `extractMessage`, activity level, city sort tiebreak |
| `loci/lociTests/ActivityDestinationTests.swift` | Mirrors web's `activity-link.test.ts`: domain → page, message/session/city carried, nearby, kept trips, favourites by kind; saved-itinerary lookup |
| `loci/lociTests/ListPayloadTests.swift` | Every ListService request builder (trim, real city ids only, domain → content type, name-keyed places refused, trace passed, description capped), web's entitlement classifier (header, message fallback, PermissionDenied only, copy with no purchase pitch), tab filter and counts, store create/limit/delete and create-then-add |
| `loci/lociTests/AppLinkTests.swift` | `AppLink` parsing for every route and its rejections, SessionLink parsed first, the tab that owns each link and `takeLink` clearing it once |
| `loci/lociTests/ParityPayloadTests.swift` | Nearby sentence byte-for-byte, default weekend, `allPlaces` dedup |
| `loci/lociTests/SettingsPayloadTests.swift` | Empty-string omission in profile updates, web defaults on a new travel profile, ids and full lists on update, Telegram deep link |
| `loci/lociTests/InSeasonTests.swift` | Mirrors web's `in-season.test.ts`: merge order, cap, no repeated ids, loop duration, marquee threshold, flags |
| `loci/lociTests/NativeSignInTests.swift` | Nonce bounds and uniqueness, SHA-256 vector, Apple/Google cancel is silent, server error copy |
| `loci/lociTests/NearbyWalkTests.swift` | Nearest-20 fence selection, nearest place by real distance, shared Live Activity text |
| `loci/lociTests/OAuthWebAuthTests.swift` | Redirect URI, cancellation detection, no window without scenes |
| `loci/lociTests/HereBriefModelTests.swift` | Empty until loaded, locality over region, weather alone counts |
| `loci/lociTests/CalendarMathTests.swift` | Date key, Monday-first October 2026 grid |
| `loci/lociTests/lociTests.swift` | JWT payload parsing, `APIError` descriptions, `AppConfig` resolution |

**The `Events` fixture helpers** build stream events the way the server sends
them, and are shared by three suites:

```swift
// loci/lociTests/SearchStateTests.swift:8
enum Events {
  static func start(_ session: String, domain: Loci_Chat_DomainType, city: String? = nil, id: String = "e0") -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.start.sessionID = session
    event.start.domain = domain
    if let city { event.start.cityName = city }
    return event
  }
```

**`@MainActor` on suites touching app types.** Any suite that constructs a
main-actor type (`HereBriefModel`, `SearchSessionController.request`,
`NearbyView.message`, `CompareView.defaultWeekend`) is marked `@MainActor`;
suites over pure `nonisolated` values (`SearchStateTests`, `ResultsParityTests`,
`InSeasonTests`, `AuthTokenProviderTests`) are not. The single-flight test is
the model for testing an actor with injected closures:

```swift
// loci/lociTests/AuthTokenProviderTests.swift:62
    let tokens = await withTaskGroup(of: String?.self) { group in
      for _ in 0..<8 { group.addTask { await provider.accessToken() } }
      return await group.reduce(into: []) { $0.append($1) }
    }

    #expect(tokens.allSatisfy { $0 == "new-access" })
    #expect(await calls.value == 1)
```

**The UI test.** `MuseChatNavigationUITests` launches a design preview that
pushes the chat with the navigation bar hidden and proves the edge swipe still
goes back (plus a control with the bar showing). It skips itself on a
non-Debug build:

```swift
// loci/lociUITests/MuseChatNavigationUITests.swift:20
    // `-designPreview` screens exist only in Debug builds.
    app.launchArguments = ["-designPreview", preview]
    app.launch()

    let open = app.buttons["Open the chat"]
    guard open.waitForExistence(timeout: 10) else { throw XCTSkip("Design previews need a Debug build.") }
```

**Not tested.** Nothing touches the network: `ChatStreamClient`,
`ResultsAPI`, `SettingsClients` and every screen's `load()` are exercised only
by running the app. Views are not snapshot-tested; the design previews are
the visual check. `SearchSessionController`'s lifecycle (background task,
BGAppRefresh, polling) has no test beyond `request(from:resuming:)`. The UI
tests are not in CI.

## 12. Decisions and their reasons

- **Local notifications only.** There is no device-token RPC in the proto the
  app was built against and the phase rule is "no new endpoints", so the
  search-finished alert is a `UNNotificationRequest` posted by the app itself.
  The payload keys already match the planned push, so APNs can plug into the
  same router later. (`docs/ios-search-notifications.md`, `ROADMAP.md`.)
- **Keep the five tabs.** Discover, Calendar, Assistant, Saved, Profile stay
  as the pre-slice app had them (`MainTabView.swift`), even though
  NATIVE_DESIGN §5 describes four journeys; the roadmap records "the current
  five tabs stay".
- **Tokens are never rendered.** Three parallel workers interleave their JSON
  in the token stream; web never shows it, and after TestFlight showed raw
  JSON, iOS stopped too (PR #10). Skeletons, then structured events.
- **Layout rule (user, 2026-09-23).** Discover and itinerary results are a
  map hero plus list, tap to expand; Nearby is a full map with the list in a
  sheet; web's phone List/Map toggle is never copied
  (`12-results-parity.md`, `ResultsMapCard.swift:112`).
- **Palette = web's `LOCI_DAY_COLORS`** (verdict 2026-09-24, PR #12). iOS had
  copied a stale list from NATIVE_DESIGN; web's palette is the one built for
  telling days apart on a map, so both clients use it, indexed the same way
  (`12-results-parity.md`, `LociTheme.swift`).
- **No StoreKit in Phase 1.** Billing is off-app; the Pro gate reads
  `GetSubscription` and links to `/pricing`. Settings omits the Billing tab
  for the same reason (`SettingsView.swift:3-5`).
- **No view-model layer.** Screens hold `@State` and call `rpc` directly;
  shared state is a small number of `@Observable` singletons. The review pass
  in PR #4 removed the one place a controller had been wrapped in `@State`.
- **Connect-Swift over REST.** The generated clients give the same message
  types web uses and the same wire shape, so a field-for-field parity table
  can be written per screen and checked in tests (`ParityPayloadTests`,
  `SettingsPayloadTests`).
- **Keychain for tokens**, `AfterFirstUnlockThisDeviceOnly`, not synchronised,
  so a background refresh can read them while the phone is locked and they
  never leave the device (`SecureStringStore.swift:51`).
- **iOS keeps its own copy of a finished result per session.** Until proto
  v5.22 `GetChatSession` could only return an itinerary, and a phone that ran
  a hotel search had already seen the hotels, so the finished state is
  serialised to `result-<sessionId>.bin` and restored before the server is
  asked. The server now stores the lists too (api #73), so the copy is the
  fast path and the offline path, not the only path
  (`SearchEnvelope.swift:23-25`, `SearchSessionController.state(for:)`).
- **One active search, app-scoped.** Matching web's single
  `active_streaming_session`; starting another asks first, and the session
  controller (not a screen) owns the stream so leaving a page never kills a
  search.
- **Every permission at the moment of use.** Location on the first Nearby
  search, Motion & Fitness on the first walk Start, notifications on the first
  search, calendar on the first write. Discover reads location only when it is
  already granted.

## 13. Known gaps and where Phase 1 stands

From [`ROADMAP.md`](ROADMAP.md) and the slice docs.

**Done (merged to main).** All nine Phase 1 slices, native sign-in, the
in-season band, the Muse chat (stages A and B), result-page parity, the here
brief. The build signs, tests pass in CI, TestFlight builds ship from the
`beta` lane.

**Verified live so far.** One TestFlight session on the owner's phone
(build 10, 2026-09-22 evening): Google sign-in, Discover, Saved, the Ask Loci
list and a Near me search all reached the server. Every search of that
session died on the Postgres pgvector crash and, once that was fixed, on the
shared OpenRouter key being out of credits; on 2026-09-23 the raw-token
result page showed up in the same way (fixed in #10). Web searches generate
again since the evening of 2026-09-23.

**Still unrecorded on a device.** Token refresh against the real API; every
settings screen; a streamed search end to end with the new result page, and
a notification tap that restores it; the trips editor, Compare and Saved
flows in PR #4; native sign-in after the fix; a real walk (steps, a geofence
firing, the Live Activity on the Lock Screen); the here brief with location
granted and denied.

**Phase 2 items that already exist.** The Near me walk with `CMPedometer`,
`CLMonitor` fences and the Live Activity (`NearbyWalkWidget`) is roadmap
item 8 in its smallest form. Items 2 and 3 shipped as Phase 2B
(`14-offline-trip-day.md`): `Core/Cache/LocalCache.swift` keeps serialized
protos on disk and `cacheThrough` (`Core/Cache/Loaded.swift`) makes the
Trips, editor, Saved and forecast loaders render the copy first and keep it
offline; `TripPrefetch` refreshes the next trip day in the background;
`Features/Trips/Model/DayTimeline.swift` turns a day into timed slots and
`TripDayActivityController` runs them as a Live Activity drawn by
`NearbyWalkWidget/TripDayLiveActivity.swift`.

**What the server still owes, and what iOS has not adopted.**

- APNs is done (Phase 2A, `13-push-and-universal-links.md`):
  `PushRegistration` registers the token with `RegisterPushDevice`, the
  server sends over APNs (api #77), and a registered phone no longer posts
  the local notification. Still open: `SearchSessionController` polls
  `GetChatSession` rather than `GetRunStatus`.
- `EditTripCTA` needs `navigation` (a trip id) in `CompletePayload`; the Swift
  message today has `sessionID`, `result`, `loadFromSession` and `message`
  only (`gen/swift/loci/chat/chat.pb.swift:1426-1457`).
- StreamChat resume was fixed server-side on 2026-09-23 (proto v5.21.1, api
  1f64023): a resume now follows a live run to its terminal event, event ids
  are unique per stream, and a run whose buffer is gone answers with one
  COMPLETE carrying `load_from_session` (handled since #10). The reducer's
  `(id, case)` dedup key is therefore belt and braces, not a workaround, and
  polling `GetChatSession` could give way to `GetRunStatus`.
- Buf Swift + Connect-Swift generation in proto CI; `gen/swift` is committed
  by hand.
- Sign in with Apple token validation on the server; StoreKit 2 receipts.

**Smaller gaps recorded in the slice docs.** Google's brand mark on the
sign-in button; no browsing before sign-in; no city autocomplete on Compare;
no offline copy of Saved; hotel and restaurant detail RPCs unused; the
`HereBriefModel` load bypasses `rpc` so it never retries after a refresh.

## 14. Study path

Read in this order; each line says what to look for.

1. `loci/loci/lociApp.swift`: the four root states, who handles URLs, who is
   told about scene phase. Twenty lines that place every singleton.
2. `loci/loci/Core/Network/ConnectTransport.swift`: why there are two clients.
3. `loci/loci/Core/Network/AuthTokenProvider.swift`: the actor, the 30 s skew,
   the three refresh outcomes, the injectable constructor.
4. `loci/loci/Core/Network/APIError+Connect.swift`: `withAuthRetry`, the two
   `rpc` overloads and the Swift 6 reason for the second, the quota trailer.
5. `loci/loci/Core/Routing/AppRouter.swift`: `SearchDestination(domain:)`,
   `SessionLink`'s three parsers and the shared keys, `AppRouter.open`.
6. `loci/loci/Features/Search/Model/SearchState.swift`: the reducer; note the
   dedup key, `completedWithError`, `hasContent`, and the derived properties.
7. `loci/loci/Features/Search/SearchSessionController.swift`: read once top to
   bottom; then trace `start` → `open` → `receive` → `finish`, and
   `sceneDidEnterBackground` → `backgroundTimeExpired` → `reconcileInBackground`.
8. `loci/loci/Features/Search/Model/SearchEnvelope.swift`: what is on disk and
   why the proto is the file format.
9. `loci/loci/Features/Search/Services/ChatStreamClient.swift`: the
   `AsyncThrowingStream` wrapper and the unauthenticated-before-first-event
   retry.
10. `loci/loci/Features/Search/UI/SearchResultsView.swift` then
    `Results/ResultsPage.swift`: live vs restored state, and the page order.
11a. `loci/loci/Core/Cache/LocalCache.swift` and `Core/Cache/Loaded.swift`: the
    disposable proto cache and the one loading dance every offline page uses.
11b. `loci/loci/Features/Trips/Model/DayTimeline.swift` then
    `Features/Trips/Services/TripDayActivityController.swift`: a day as
    slots, and how the schedule, Next and a geofence share one index.
11. `loci/loci/Features/Search/Model/DayGrouping.swift`: the pure rules ported
    from web (`trip-kit.ts`, `share.ts`, `subscription.ts`).
12. `loci/loci/Features/Chat/MuseActivity.swift` and `UI/MuseChatHeader.swift`:
    a pure state function and the view that renders it, with the `museFlash`
    timer between them.
13. `loci/loci/Core/Theme/LociTheme.swift`: every token, and the
    `dynamic(light:dark:)` trick.
14. `loci/loci/Features/Nearby/Services/NearbyWalk.swift` with
    `POIProximityMonitor.swift` and `loci/loci/Shared/NearbyWalkAttributes.swift`:
    the first native-only feature, and the one `@preconcurrency import`.
15. `loci/lociTests/SearchStateTests.swift` and `ResultsParityTests.swift`:
    the fixtures, and how much of the product's behaviour is checkable without
    a screen.

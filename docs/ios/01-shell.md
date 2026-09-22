# Slice 1: shell, design tokens, transport

## What changed
- Swift 6 language mode (`SWIFT_VERSION = 6.0`) on every target. Default `MainActor` isolation is unchanged. Test suites that call app types are marked `@MainActor`.
- Removed the Xcode template leftovers: `ContentView`, `Item` and the SwiftData `ModelContainer`.
- `Core/Theme/LociTheme.swift` now follows `loci-client/docs/NATIVE_DESIGN.md`:
  - light and dark colour tokens
  - the map day colours
  - the motion curves
  - `Font.loci*` for Fraunces, DM Sans and Space Mono, bundled under `Resources/Fonts` with their OFL licences and registered in `UIAppFonts`
  - `.lociCard()`
- Deep links: `Core/Routing/AppRouter.swift`. It parses `loci://{itinerary|hotels|restaurants|activities}?sessionId=&cityName=&domain=`, the web routes with the `loci` scheme as host. It ignores `loci://oauth2redirect/*`, which `ASWebAuthenticationSession` owns. Notification taps go through the same parser.

## Transport
| Piece | File | Notes |
|---|---|---|
| Authenticated client | `Core/Network/ConnectTransport.swift` `protocolClient` | Connect protocol, JSON codec, `AuthInterceptor` |
| Bare client | `ConnectTransport.makeBareClient()` | No interceptors; used only by the token refresh |
| Auth header | `Core/Network/AuthInterceptor.swift` | Adds `Authorization: Bearer` to unary calls and streams unless the caller set one |
| Errors | `Core/Network/APIError+Connect.swift` | `ResponseMessage.unwrap`, the Connect → `APIError` mapping, and `x-loci-quota-reason` handling (web: `lib/quota-error.ts`) |
| MCP endpoint | `ConnectTransport.mcpEndpoint` | `<ConnectBaseURL>/mcp` (web: `lib/mcp-endpoint.ts`) |

Base URL per configuration: Debug → `http://localhost:8000`; Release and Beta → `https://api.lociai.fyi`.

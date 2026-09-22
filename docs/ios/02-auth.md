# Slice 2: auth refresh

| Screen / trigger | Service | RPC | Fields sent |
|---|---|---|---|
| Sign in | `loci.auth.AuthService` | `Login` | `email`, `password` |
| MFA step | `AuthService` | `VerifyMFA` | `mfa_token`, `code` or `recovery_code` |
| Any call with an expired token | `AuthService` | `RefreshToken` | `refresh_token` |
| Unary call that gets `Unauthenticated` | `AuthService` | `RefreshToken`, then the original call once more | — |

## Behaviour
- **Single flight.** `actor AuthTokenProvider` (`Core/Network/AuthTokenProvider.swift`) runs at most one refresh at a time; concurrent callers await the same task. This mirrors web's `tokenRefreshInterceptor`.
- **Proactive refresh.** A token is treated as expired 30 seconds before its `exp`, and is refreshed before the request leaves.
- **Retry once.** `withAuthRetry { … }` re-runs a unary call once after a refresh.
- **Refresh outcomes.**
  - Rejected (`Unauthenticated`, `InvalidArgument`, `PermissionDenied`, `NotFound`): the Keychain is cleared and `authSessionDidInvalidate` fires, which returns the user to sign-in.
  - Network trouble: the session is kept, and the next call retries.
- **Launch.** With an expired access token and a refresh token present, the app refreshes on launch. If it's offline, it keeps the session instead of signing the user out.
- **Keychain.** Accessibility is now `AfterFirstUnlockThisDeviceOnly`, so a background refresh (slice 6) can read the tokens while the phone is locked. Existing items move over on their next write.

## Not done here
- `ValidateSession` on launch is not called. With the interceptor and retry in place, the first real call already proves the session.
- Streams reopening after `Unauthenticated` belongs to the stream reader in slice 6.

# Slice 3: Settings

The path is Profile tab › Settings. Each row matches a web settings tab (`/settings?tab=…`) except Billing, which is left out because the iOS app sells nothing in this pass. Every call goes through `rpc(…)`, which uses the authenticated transport and retries once after a token refresh.

| iOS screen | Web source | Service | RPC → fields sent |
|---|---|---|---|
| Profile | tab `settings`, profile card | `UserService` | `GetUserProfile{}`; `UpdateUserProfile{params}`. Only changed, non-empty fields are sent, because every param is `optional` with `min_len:1` (mirrors `buildUpdateProfileParams`) |
| Region and units | `LocaleSettings` | `UserService` | `UpdateUserProfile{params.timezone, units, currency}` |
| Security › Change password | `ChangePassword` | `AuthService` | `ChangePassword{oldPassword, newPassword}` |
| Security › Two-factor | `TwoFactor` | `AuthService` | `GetMFAStatus`, `BeginMFAEnrollment` (the QR is drawn on the device from `provisioning_uri`), `ConfirmMFAEnrollment{code}`, `DisableMFA{code}`, `RegenerateRecoveryCodes{code}` |
| Security › Signed-in devices | `SignedInDevices` | `AuthService` | `ListSessions{refreshToken}`, `RevokeSession{sessionId}`, `RevokeOtherSessions{refreshToken}` |
| Your data | `AccountData` | `UserService` | `ExportUserData{}` (saved to a file and shared); `DeleteAccount{confirmation:"DELETE"}` |
| Travel profiles | `TravelProfiles` (tab `profiles`) | `ProfileService` | `GetUserPreferenceProfiles`, `Create/UpdateUserPreferenceProfile` (the web form's fields, defaults and option strings; `tagIds`/`interestIds` are ids; update sends full lists), `SetDefaultProfile{profileId}`, `DeleteUserPreferenceProfile{profileId}` |
| Interests | tab `interests` | `InterestService` | `GetInterests{activeOnly:false}`, `CreateInterest{name, description, active}`, `UpdateInterest{interestId, name?, description?, active}`, `DeleteInterest{interestId}` |
| Tags | tab `tags` | `TagsService` | `GetTags{}`, `CreateTag{name, description, tagType, active}`, `UpdateTag{tagId, …}`, `DeleteTag{tagId}` |
| Taste and privacy | `TasteAndPrivacy` | `RecommendationService` | `Get/UpdatePersonalizationSettings{personalizationEnabled, contributeAggregate, disclosureSeen}`, `GetTasteProfile`, `ResetTasteProfile{confirmation:"RESET"}` |
| What Loci remembers | `/settings/memory` | `MemoryService` | `GetMemory{includeEvidence:true}`, `ForgetTrait{traitKey}`, `ForgetEvidence{feedbackId}` |
| MCP and agents › Agents | tab `connections`, `/mcp` | `ApiKeyService` | `ListApiKeys`, `CreateApiKey{name, scopes ⊂ read/write/write:generate, clientKind}` (plaintext shown once, alongside the server's setup snippets), `RevokeApiKey{id}`, `GetSetupInstructions{clientKind}`. The endpoint shown is `ConnectBaseURL/mcp` |
| MCP and agents › Model provider | `ModelProviderCard` | `AiCredentialService` | `ListProviders`, `GetCredential`, `SaveCredential{provider, apiKey, model, baseUrl}`, `VerifyCredential`, `DeleteCredential`. Hidden when `enabled` is false |
| MCP and agents › Telegram | `TelegramCard` | `MessagingService` | `GetLink{platform:"telegram"}`, `CreateLinkCode{platform}` (link: `https://t.me/<bot>?start=<code>`), `Unlink{platform}` |
| MCP and agents › Servers Loci can call | `OutboundConnections` | `IntegrationService` | `ListConnections`, `Connect{provider, endpoint, accessToken}`, `TestConnection{provider}`, `Disconnect{provider}`. Hidden when `enabled` is false |
| Calendars | `ConnectedCalendars` | `CalendarService` | Existing `CalendarConnectionsView`, plus `GetTripCalendarFeedUrl{}` (share, or subscribe via `webcal://`) |
| Notifications | tab `notifications` | `UserService` | `GetNotificationSettings{}`, `UpdateNotificationSettings{recommendations, tripReminders}`, plus the iOS permission |
| Travel news strip | `NewsTickerToggle` | `LocalContextService` | `GetNewsTicker{limit:1}` to read the state; `SetNewsTickerEnabled{enabled}` |

Theme (appearance) stays on the device, as on web, and needs no screen: the app follows the system appearance.

## Verified
- Builds under Swift 6; lint is clean.
- `SettingsPayloadTests` covers:
  - the empty-string omission
  - the web defaults on a new travel profile
  - ids and full lists on update
  - the Telegram deep link
- The app launches on the simulator to the restyled sign-in screen.

## Not verified
None of these screens has been run against the live API: signing in needs an account, and none was used in this session.

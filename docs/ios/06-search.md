# Slice 6: streaming search, results, Ask Loci

| iOS screen | Web route | Service | RPC → fields sent |
|---|---|---|---|
| Composer (Ask Loci, results follow-ups; Discover and Nearby next) | Dashboard hero, `/chat` | `ChatService` | `StreamChat{message, cityName?, profileId, userLocation?, requestId, sessionId? (follow-up)}` |
| Default profile lookup before a search | `DeskHero` | `ProfileService` | `GetUserPreferenceProfiles{}`. If there is no profile, a sheet opens Settings › Travel profiles, as web does |
| Reattach after the background | `resume-live.ts` | `ChatService` | `StreamChat{sessionId, resumeToken: lastEventId, message, requestId, …}` |
| Reconcile or restore | `restoreOrHydrateSession` | `ChatService` | `GetChatSession{sessionId}` → `session.currentItinerary` |
| Result page `/itinerary`, `/hotels`, `/restaurants`, `/activities` | same | — | Live state from the stream |
| Save (itinerary) | `/itinerary` Save | `ItineraryService` | `BookmarkItinerary{primaryCityName, title, description, tags: [], isPublic: false, sessionId}` |
| Ask Loci list | `/chat` | `ChatService` | `GetChatSessions{pagination{page:1, pageSize:25}}` (web also sends `userId`; the server ignores it) |

Code: `Features/Search/` — `SearchState` (reducer), `SearchEnvelope` / `SearchStore` (persistence), `ChatStreamClient`, `SearchNotifier`, `SearchSessionController`, and the UI (`SearchComposer`, `SearchResultsView`, `Chat/UI/AssistantView`).

Order change: this slice shipped before Discover (4) and Nearby (5), because both of them start searches through it.

The notification and resume design is in `../ios-search-notifications.md`.

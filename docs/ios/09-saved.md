# Slice 9: Saved

| iOS | Web | Service | RPC → fields sent |
|---|---|---|---|
| Saved › Places | `/saved?view=places` (`/favorites` redirects) | `FavoritesService` | `GetFavorites{userId, limit: 1000}` (userId must be non-empty for validation; the server uses the token), `RemoveFromFavorites{userId, itemId, contentType}` |
| Saved › Itineraries | `/saved?view=itineraries` (`/bookmarks` redirects) | `ItineraryService` | `GetUserItineraries{pagination{1, 100}}` (100 is the validation cap), `DeleteBookmark{itineraryId}` |
| Saved itinerary page | | — | Markdown content, share, and a link to the session that made it |

Web's offline IndexedDB copy has no counterpart yet (Phase 2, SwiftData).

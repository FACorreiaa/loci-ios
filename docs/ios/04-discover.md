# Slice 4: Discover

| iOS | Web | Service | RPC → fields sent |
|---|---|---|---|
| Discover tab | `/discover` | `DiscoverService` | `GetDiscoverPage{}` → trending, featured, recent discoveries |
| Search box | Discover search | `ChatService` | `StreamChat{message, cityName?, userLocation?}` with **no profile**, as web's Discover sends `profileId: ""` |
| Quick categories, featured collections | `categories`, featured cards | — | Fill the search box (web focuses the input) |
| Trending city | trending cards | — | Fills the city field |
| Recent discoveries | recent sessions | — | Opens the session's result page |
| Near me, Weekend compare | links | — | Push `NearbyView`, `CompareView` |

Not carried over: the Pro `AdvancedFiltersBar`, and `RecommendationService.RecordEvents` impressions. Neither changes what the server returns for a search.

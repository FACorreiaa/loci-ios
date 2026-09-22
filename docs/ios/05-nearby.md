# Slice 5: Near me

Web has `/nearme` only; `/near` redirects there and there is no `/nearby`, so this is one screen.

| iOS | Web | Service | RPC → fields sent |
|---|---|---|---|
| Near me (MapKit, list in a detent sheet at 25% / medium / large) | `/nearme` | `ChatService` | `StreamChat{message: "Find places near me within N kilometers. My location is at latitude … and longitude …. Show me restaurants, attractions, hotels, and activities nearby.", cityName: "nearme", userLocation{lat, lon}}`, no profile |
| Radius menu 5 / 10 / 25 / 50 km (50 default, the server's default) | radius dropdown | — | Re-runs the search |

The map shows every place from every event (general, restaurants, hotels, activities merged, as web's `allPois`). Pins use the NATIVE_DESIGN day colours; selecting one gives a light haptic and scrolls the list.

Location comes from `CLServiceSession(.whenInUse)` + `CLLocationUpdate.liveUpdates()` (`Core/Location/CurrentLocation.swift`); `NSLocationWhenInUseUsageDescription` is in Info.plist.

Web's `/nearme` does not call `FavoritesService.GetNearbyHotels/Restaurants`; those back the hotel and restaurant detail pages, which are not in this pass.

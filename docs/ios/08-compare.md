# Slice 8: Compare

| iOS | Web | Service | RPC → fields sent |
|---|---|---|---|
| Compare (from Discover) | `/compare` | `CompareService` | `CompareWeekend{originCity, candidateCityNames (2+), startDate, endDate}` |
| Presets | `COMPARE_PRESETS` | | Porto → Évora/Beja, Lisbon → Sintra/Óbidos, Madrid → Toledo/Segovia; one tap runs the compare |
| Default dates | `defaultWeekend` | | The coming Saturday to Sunday, a week ahead when today is Saturday |
| Save a city as a trip | save handler | `TripService` | `SaveTrip{trip{cityName, cityId, title "<City> weekend", constraints{pace: moderate}, days[1: top 2 POIs]}, baseVersion: 0}` |
| Save both cities | dual option | `TripService` | Same, title "Weekend: A + B", two days of two stops |
| Save the multi-city route | multi-city plan | `TripService` | Days per planned city with day numbers and coordinates, plus `legs` |

The 8-city and multi-city limits are Pro; the server enforces them and the app shows its message. Web's city autocomplete (`CityService.SearchCities`) is not carried over: cities are typed.

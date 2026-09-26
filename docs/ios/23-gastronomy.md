# 23 · Typical gastronomy

A city's typical food: an overview, its signature dishes and the well-known
places to eat each one, filterable by dish type and by ingredient or diet.
Web: `/gastronomy` and `components/gastronomy/GastronomySection.tsx`.

## Where it shows

- **Local food** (`Features/Gastronomy/UI/GastronomyView.swift`), entered from
  the card under City Packs on Discover. Type a city or tap a suggestion.
- **Under itinerary and discovery results** (`ResultsPage`, after "More to
  explore"): a compact `GastronomySection` when the answer carries one.
- **A gastronomy search** ("food in Madeira", "what to eat in Porto"): the
  server detects `DOMAIN_TYPE_GASTRONOMY`, the stream sends a `gastronomy`
  event and no places, and `ResultsPage` renders the full section as the
  answer (`SearchState.isGastronomySearch`). The destination stays
  `.itinerary`, so no `SearchDestination` case was added.

## Data

- `GastronomyService.GetCityGastronomy` (loci.gastronomy) for the screen.
- `AiCityResponse.gastronomy` (field 8) on itinerary/general answers and the
  stored session, and the `GastronomyPayload` stream case, which
  `SearchState.apply` stores in `gastronomy` before the itinerary arrives.
  `SearchStore.saveResult` keeps it, so a reopened result still has it.
- Places are light references (name, neighbourhood, why it is famous, price,
  optional coordinates), not POIs. A place row opens Apple Maps at the
  coordinates, or searches for the name in the city.
- Filtering is local (`GastronomyFilter`): the server keys a city's gastronomy
  on the city alone, so every filter, every search and the standalone screen
  read one cached answer.

## Tests

`lociTests/GastronomyFilterTests.swift` (the filter) and
`lociTests/GastronomySearchStateTests.swift` (the stream event, a
gastronomy-domain search and restore from a saved result).

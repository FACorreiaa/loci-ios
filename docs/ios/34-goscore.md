# 34 — GoScore and drive cost (pass 3, Phase 3)

## GoScore on the here-brief

`LocalContextService.GetGoScore{latitude, longitude}` → `GoScore{score,
verdict go|maybe|skip, factors[label, contribution, max_contribution,
detail], summary, has_estimated_inputs}` (web: GoScoreCard, which web only
shows inside Compare columns; the here-brief is the natural iOS home).

- `Features/Discover/Model/GoScoreModel.swift` — `tone` and `label` from the
  verdict (empty → maybe, as on web), `factorRows` with a clamped `share` for
  the bar (nil without a maximum) and web's "30 / 40" wording, `estimatedNote`.
- `Features/Discover/UI/GoScoreCard.swift` — score and verdict lead; a tap
  unfolds the factors. Tints: forest for go, red for skip, ink for maybe.
- `HereBriefModel.loadGoScore` runs alongside the brief for the same rounded
  coordinates; a failure leaves the card out and never blocks the brief.
  Injected `fetchGoScore` for tests and previews.
- `Features/Discover/API/LocalContextAPI.swift` — the two calls.

## Fuel on a multi-city trip

`LocalContextService.EstimateDriveCost{distance_km}` → `DriveCostEstimate{
distance_km, litres, cost, currency, assumptions}` (web: TripMoney). The
trip editor's "Travel between cities" section ends with `DriveCostRow`:
"Fuel ≈ 32.64 EUR · 274 km · 19.2 L" and the server's assumptions, always
shown so the figure can be corrected against one's own car. Every leg's km
is summed (web: totalDriveKm); zero, offline or a failure hides the row. No
currency is sent, as on web: the server picks from the account.

## Previews

`-designPreview goScoreGood | goScoreMaybe | driveCost`.

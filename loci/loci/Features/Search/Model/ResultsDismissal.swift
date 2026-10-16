import LociConnectProto

/// Places waved away with "Not for me", taken out of a result page. Lists and
/// "More to explore" lose them; an itinerary's days keep every stop, because
/// hiding one would break the plan. The page numbers and maps from the result,
/// so cards and pins stay in step.
nonisolated enum ResultsDismissal {
  static func apply(
    groups: [DayGroup],
    extras: [Loci_Poi_POIDetailedInfo],
    dismissed: Set<String>,
    showsDays: Bool,
  ) -> (groups: [DayGroup], extras: [Loci_Poi_POIDetailedInfo]) {
    guard !dismissed.isEmpty else { return (groups, extras) }
    let keptExtras = extras.filter { !dismissed.contains($0.stableID) }
    guard !showsDays else { return (groups, keptExtras) }
    let keptGroups = groups
      .map { DayGroup(number: $0.number, stops: $0.stops.filter { !dismissed.contains($0.stableID) }) }
      .filter { !$0.stops.isEmpty }
    return (keptGroups, keptExtras)
  }
}

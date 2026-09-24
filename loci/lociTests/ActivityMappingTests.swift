import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

/// The proto → feed mapping, the prompt unwrapping, the type chips and the
/// Cities view helpers (web: lib/api/recents.ts, prompt-wrapper.ts,
/// ActivityTypeChips.tsx, CitiesView.tsx).
struct ActivityMappingTests {
  private func interaction(
    kind: String? = nil,
    entityType: String = "",
    contentType: String? = nil,
    description: String = "three days in Porto",
    createdAt: Date? = Date(timeIntervalSince1970: 1_790_000_000)
  ) -> Loci_Recents_RecentInteraction {
    var interaction = Loci_Recents_RecentInteraction()
    interaction.id = "row-1"
    interaction.entityID = "ref-1"
    interaction.entityType = entityType
    interaction.description_p = description
    interaction.cityName = "Porto"
    if let kind { interaction.metadata["kind"] = kind }
    if let contentType { interaction.metadata["content_type"] = contentType }
    if let createdAt { interaction.createdAt = Google_Protobuf_Timestamp(date: createdAt) }
    return interaction
  }

  // MARK: mapActivityEntry

  @Test func promptTakesItsDomainFromEntityType() {
    let entry = ActivityFeed.entry(interaction(kind: "prompt", entityType: "dining"))
    #expect(entry.kind == .prompt)
    #expect(entry.detail == "dining")
    #expect(entry.id == "row-1")
    #expect(entry.refId == "ref-1")
    #expect(entry.cityName == "Porto")
    #expect(entry.occurredAt == Date(timeIntervalSince1970: 1_790_000_000))
  }

  @Test func missingKindIsAPromptAndMissingDomainIsGeneral() {
    let entry = ActivityFeed.entry(interaction())
    #expect(entry.kind == .prompt)
    #expect(entry.detail == "general")
  }

  @Test func favouriteDetailIsItsContentTypeDefaultingToPoi() {
    #expect(ActivityFeed.entry(interaction(kind: "favourite", entityType: "favourite", contentType: "hotel")).detail == "hotel")
    #expect(ActivityFeed.entry(interaction(kind: "favourite", entityType: "favourite")).detail == "poi")
  }

  @Test func savedItineraryDetailIsAlwaysItinerary() {
    let entry = ActivityFeed.entry(interaction(kind: "saved_itinerary", entityType: "saved_itinerary"))
    #expect(entry.kind == .savedItinerary)
    #expect(entry.detail == "itinerary")
  }

  @Test func unknownKindIsKeptAsOther() {
    #expect(ActivityFeed.entry(interaction(kind: "review")).kind == .other)
  }

  @Test func labelIsUnwrappedAgainForAnOlderServer() {
    let entry = ActivityFeed.entry(interaction(description: "Unified Chat Stream - Domain: itinerary, Message: Itinerary in Funchal."))
    #expect(entry.label == "Itinerary in Funchal.")
  }

  @Test func noTimestampStaysNil() {
    #expect(ActivityFeed.entry(interaction(createdAt: nil)).occurredAt == nil)
  }

  // MARK: stripPromptWrapper

  @Test func stripsTheWrapperCaseInsensitivelyAndTrims() {
    #expect(ActivityFeed.stripPromptWrapper("unified chat stream - domain: dining,  message:  seafood in Cascais  ") == "seafood in Cascais")
    #expect(ActivityFeed.stripPromptWrapper("Unified Chat Stream - Domain: general, Message: line one\nline two") == "line one\nline two")
  }

  @Test func leavesAMessageThatOnlyMentionsTheWrapper() {
    let text = "Why does it say Unified Chat Stream - Domain: x, Message: y?"
    #expect(ActivityFeed.stripPromptWrapper(text) == text)
    #expect(ActivityFeed.stripPromptWrapper("plain question") == "plain question")
  }

  // MARK: Paging

  @Test func hasMoreWhileTheServerCountsPastWhatLoaded() {
    var response = Loci_Recents_GetInteractionHistoryResponse()
    response.interactions = [interaction(), interaction()]
    response.totalCount = 3
    #expect(ActivityFeed.page(response, limit: 40).hasMore)
    response.totalCount = 2
    #expect(!ActivityFeed.page(response, limit: 40).hasMore)
  }

  @Test func limitGrowsByFortyAndStopsAtTheServerCap() {
    #expect(ActivityFeed.limit(pages: 1) == 40)
    #expect(ActivityFeed.limit(pages: 3) == 120)
    #expect(ActivityFeed.limit(pages: 9) == 200)
    var response = Loci_Recents_GetInteractionHistoryResponse()
    response.interactions = [interaction()]
    response.totalCount = 500
    #expect(!ActivityFeed.page(response, limit: 200).hasMore)
  }

  // MARK: Type chips

  private func entry(_ kind: ActivityKind, _ detail: String, label: String = "x", city: String = "Porto") -> ActivityEntry {
    ActivityEntry(id: UUID().uuidString, kind: kind, detail: detail, label: label, cityName: city, refId: "r", occurredAt: nil)
  }

  @Test func chipsMatchOnKindAndDetailTogether() {
    let entries = [
      entry(.prompt, "itinerary"), entry(.prompt, "itinerary"), entry(.savedItinerary, "itinerary"),
      entry(.favourite, "hotel"), entry(.prompt, "general"), entry(.prompt, "nearby"),
    ]
    let counts = ActivityFilter.counts(entries)
    #expect(counts["itinerary"] == 2)  // searches, not kept trips
    #expect(counts["saved"] == 1)
    #expect(counts["favourite"] == 1)
    #expect(counts["chat"] == 1)
    #expect(counts["nearby"] == 1)
    #expect(counts["dining"] == 0)
    #expect(counts["all"] == nil)
  }

  @Test func filterNarrowsByChipAndBySearchOverLabelAndCity() {
    let entries = [
      entry(.prompt, "dining", label: "seafood", city: "Cascais"),
      entry(.prompt, "itinerary", label: "three days", city: "Porto"),
      entry(.favourite, "poi", label: "Livraria Lello", city: "Porto"),
    ]
    #expect(ActivityFilter.apply(entries, typeId: "all", query: "").count == 3)
    #expect(ActivityFilter.apply(entries, typeId: "dining", query: "").map(\.label) == ["seafood"])
    #expect(ActivityFilter.apply(entries, typeId: "all", query: " porto ").count == 2)
    #expect(ActivityFilter.apply(entries, typeId: "favourite", query: "LELLO").count == 1)
    #expect(ActivityFilter.apply(entries, typeId: "saved", query: "").isEmpty)
  }

  @Test func badgesNameEachKindAndDomain() {
    #expect(ActivityBadge(entry(.savedItinerary, "itinerary")).label == "Saved")
    #expect(ActivityBadge(entry(.favourite, "hotel")).label == "Favourite")
    #expect(ActivityBadge(entry(.prompt, "general")).label == "Chat")
    #expect(ActivityBadge(entry(.prompt, "accommodation")).label == "Stays")
    #expect(ActivityBadge(entry(.prompt, "nearby")).label == "Nearby")
    #expect(ActivityBadge(entry(.prompt, "discover")).label == "Search")
  }

  // MARK: Cities

  @Test func extractMessageUnwrapsAndNamesTheCityOnce() {
    let wrapped = "Unified Chat Stream - Domain: itinerary, Message: "
    #expect(RecentCities.extractMessage("\(wrapped)Itinerary in Funchal.", cityName: "Funchal") == "Itinerary in Funchal.")
    #expect(RecentCities.extractMessage("\(wrapped)three days", cityName: "Porto") == "three days Porto")
    #expect(RecentCities.extractMessage("\(wrapped)Porto", cityName: "Porto") == "Porto")
    #expect(RecentCities.extractMessage("\(wrapped)three days", cityName: "") == "three days")
  }

  @Test func extractMessageReadsAPoiLookupPrompt() {
    let prompt = "Return ONLY JSON for \"Livraria Lello\" in Porto. No prose."
    #expect(RecentCities.extractMessage(prompt, cityName: "Porto") == "Looking up Livraria Lello in Porto")
  }

  @Test func extractMessageCutsLongTextAndFallsBackToTheCity() {
    let long = String(repeating: "a", count: 60)
    #expect(RecentCities.extractMessage(long, cityName: "Porto") == String(repeating: "a", count: 50) + "...")
    #expect(RecentCities.extractMessage("short", cityName: "Porto") == "short")
    #expect(RecentCities.extractMessage("", cityName: "Porto") == "Porto")
  }

  @Test func activityLevelThresholds() {
    #expect(CityActivityLevel(count: 10) == .high)
    #expect(CityActivityLevel(count: 9) == .medium)
    #expect(CityActivityLevel(count: 5) == .medium)
    #expect(CityActivityLevel(count: 4) == .low)
    #expect(CityActivityLevel(count: 0).label == "Visited")
  }

  @Test func citiesSortNewestFirstWithANameTiebreak() {
    func summary(_ name: String, _ seconds: TimeInterval?) -> Loci_Recents_CityInteractionSummary {
      var summary = Loci_Recents_CityInteractionSummary()
      summary.cityName = name
      summary.interactionCount = 1
      if let seconds { summary.latestInteraction = Google_Protobuf_Timestamp(date: Date(timeIntervalSince1970: seconds)) }
      return summary
    }
    var response = Loci_Recents_GetRecentInteractionsResponse()
    response.citySummaries = [summary("Sintra", 100), summary("Undated", nil), summary("Porto", 200), summary("Lisbon", 200)]
    #expect(RecentCities.cities(response).map(\.name) == ["Lisbon", "Porto", "Sintra", "Undated"])
  }

  @Test func cityMappingKeepsItsPromptsReadable() {
    var summary = Loci_Recents_CityInteractionSummary()
    summary.cityName = "Porto"
    summary.interactionCount = 2
    let wrapped = "Unified Chat Stream - Domain: accommodation, Message: hotel near Ribeira"
    summary.recentInteractions = [interaction(entityType: "hotel", description: wrapped)]
    let city = RecentCities.city(summary)
    #expect(city.interactions.first?.prompt == "hotel near Ribeira Porto")
    #expect(city.interactions.first?.badge.label == "Stays")
    #expect(city.lastActivity == nil)
    #expect(RecentCities.filter([city], query: "por").count == 1)
    let none = RecentCities.filter([city], query: "lis")
    #expect(none.isEmpty)
  }
}

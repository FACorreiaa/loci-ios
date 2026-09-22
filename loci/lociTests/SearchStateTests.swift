import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Stream events as the server sends them.
enum Events {
  static func start(_ session: String, domain: Loci_Chat_DomainType, city: String? = nil, id: String = "e0") -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.start.sessionID = session
    event.start.domain = domain
    if let city { event.start.cityName = city }
    return event
  }

  static func token(_ text: String, id: String) -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.token.text = text
    return event
  }

  static func hotels(_ names: [String], id: String) -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.hotels.pois = names.map { name in
      var poi = Loci_Poi_POIDetailedInfo()
      poi.name = name
      return poi
    }
    return event
  }

  static func complete(_ session: String, id: String) -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.complete.sessionID = session
    return event
  }

  static func error(_ message: String, id: String) -> Loci_Chat_StreamEvent {
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.error.userMessage = message
    event.error.retryable = true
    return event
  }
}

struct SearchStateTests {
  @Test func startNamesTheSessionAndRoutesByDomain() {
    var state = SearchState()
    let effect = state.apply(Events.start("s1", domain: .accommodation, city: "Porto"))
    #expect(effect == .started(SessionLink(destination: .hotels, sessionId: "s1", cityName: "Porto", domain: "accommodation")))
    #expect(state.status == .streaming)
  }

  @Test func tokensAppendInOrder() {
    var state = SearchState()
    state.apply(Events.start("s1", domain: .itinerary))
    state.apply(Events.token("Three days ", id: "e1"))
    state.apply(Events.token("in Lisbon", id: "e2"))
    #expect(state.text == "Three days in Lisbon")
    #expect(state.lastEventId == "e2")
  }

  @Test func replayedEventsAreIgnored() {
    var state = SearchState()
    state.apply(Events.start("s1", domain: .itinerary))
    state.apply(Events.token("once", id: "e1"))
    state.apply(Events.token("once", id: "e1"))
    #expect(state.text == "once")
  }

  /// The server gives several events the same id (chat_process_stream.go);
  /// dropping by id alone would lose the hotels.
  @Test func sameIdDifferentPayloadIsKept() {
    var state = SearchState()
    state.apply(Events.start("s1", domain: .accommodation))
    state.apply(Events.token("x", id: "run-1"))
    state.apply(Events.hotels(["Hotel A"], id: "run-1"))
    #expect(state.hotels.map(\.name) == ["Hotel A"])
    #expect(state.places.map(\.name) == ["Hotel A"])
  }

  @Test func completeAndErrorEndTheSearch() {
    var done = SearchState()
    done.apply(Events.start("s1", domain: .itinerary))
    #expect(done.apply(Events.complete("s1", id: "e9")) == .completed)
    #expect(done.status == .completed)
    #expect(!done.isActive)

    var failed = SearchState()
    failed.apply(Events.start("s2", domain: .itinerary))
    #expect(failed.apply(Events.error("Model busy", id: "e3")) == .failed(message: "Model busy", retryable: true))
    #expect(failed.status == .failed("Model busy"))
  }
}

struct SearchStoreTests {
  private func makeEnvelope(domain: String?) -> SearchEnvelope {
    SearchEnvelope(
      sessionId: "s1",
      requestId: "r1",
      profileId: "p1",
      lastEventId: "e4",
      query: "tapas",
      cityName: "Seville",
      domain: domain,
      latitude: 37.39,
      longitude: -5.98,
      startedAt: Date(timeIntervalSince1970: 1000),
      finished: false,
      notified: false
    )
  }

  private func temporaryStore() -> SearchStore {
    SearchStore(directory: FileManager.default.temporaryDirectory.appending(path: "search-tests-\(UUID().uuidString)"))
  }

  @Test func envelopeRoundTrips() {
    let store = temporaryStore()
    let envelope = makeEnvelope(domain: "dining")
    store.save(envelope)
    #expect(store.loadEnvelope() == envelope)
    store.clearEnvelope()
    #expect(store.loadEnvelope() == nil)
  }

  @Test func finishedHotelSearchRestoresFromThisPhone() {
    let store = temporaryStore()
    var state = SearchState()
    state.apply(Events.start("s1", domain: .accommodation, city: "Porto"))
    state.apply(Events.hotels(["Hotel A", "Hotel B"], id: "e1"))
    state.apply(Events.complete("s1", id: "e2"))
    store.saveResult(state)

    let link = SessionLink(destination: .hotels, sessionId: "s1", cityName: "Porto", domain: "accommodation")
    let restored = store.loadResult(for: link)
    #expect(restored?.places.map(\.name) == ["Hotel A", "Hotel B"])
    #expect(restored?.status == .completed)
  }

  @MainActor @Test func resumeRequestCarriesSessionAndToken() {
    let envelope = makeEnvelope(domain: nil)
    let fresh = SearchSessionController.request(from: envelope, resuming: false)
    #expect(!fresh.hasResumeToken)
    #expect(fresh.message == "tapas" && fresh.cityName == "Seville" && fresh.profileID == "p1" && fresh.requestID == "r1")
    #expect(fresh.userLocation.latitude == 37.39)

    let resumed = SearchSessionController.request(from: envelope, resuming: true)
    #expect(resumed.sessionID == "s1")
    #expect(resumed.resumeToken == "e4")
  }

  @Test func notificationTitlesNameTheResult() {
    let link = SessionLink(destination: .restaurants, sessionId: "s", cityName: "Rome")
    #expect(SearchNotifier.title(for: link, succeeded: true) == "Restaurants for Rome are ready")
    #expect(SearchNotifier.title(for: link, succeeded: false) == "Your search for Rome didn't finish")
  }
}

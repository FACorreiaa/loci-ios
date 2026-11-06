import Foundation
import LociConnectProto
import SwiftProtobuf
import Testing

@testable import loci

private func storedProfile(needs: Loci_Profile_AccessibilityNeeds?, consented: Bool = true) -> Loci_Profile_UserPreferenceProfile {
  var profile = Loci_Profile_UserPreferenceProfile()
  profile.id = "p1"
  profile.profileName = "Lisbon"
  if var needs {
    if consented { needs.consentAt = Google_Protobuf_Timestamp(date: Date(timeIntervalSince1970: 1_790_000_000)) }
    profile.accessibilityNeeds = needs
  }
  return profile
}

private var wheelchair: Loci_Profile_AccessibilityNeeds {
  var needs = Loci_Profile_AccessibilityNeeds()
  needs.mobility = .manualWheelchair
  needs.maxWalkMinutesPerLeg = 10
  needs.stepFreeOnly = true
  return needs
}

@MainActor @Suite("Accessibility needs on a travel profile") struct AccessibilityProfileTests {
  @Test func untouchedFormSendsNoNeeds() {
    let draft = TravelProfileDraft()
    #expect(!draft.canEditAccessibility, "fields stay locked until consent")
    #expect(!draft.createRequest().hasAccessibilityNeeds)
    #expect(!draft.createRequest().accessibilityConsentGiven)
  }

  @Test func needsWithoutConsentAreNeverSent() {
    var draft = TravelProfileDraft()
    draft.accessibility.mobility = .powerWheelchair
    #expect(!draft.createRequest().hasAccessibilityNeeds, "needs typed without consent must not leave the phone")
  }

  @Test func consentedNeedsAreSentWithTheConsentFlag() {
    var draft = TravelProfileDraft()
    draft.accessibilityConsentGiven = true
    draft.accessibility.mobility = .manualWheelchair
    draft.accessibility.notes = "  Transfers need a firm seat  "
    let request = draft.createRequest()
    #expect(request.hasAccessibilityNeeds)
    #expect(request.accessibilityConsentGiven)
    #expect(request.accessibilityNeeds.mobility == .manualWheelchair)
    #expect(request.accessibilityNeeds.notes == "Transfers need a firm seat")
  }

  @Test func consentAloneSendsNothing() {
    var draft = TravelProfileDraft()
    draft.accessibilityConsentGiven = true
    #expect(!draft.createRequest().hasAccessibilityNeeds, "consent with no needs is not worth storing")
  }

  @Test func storedNeedsLoadUnlocked() {
    let draft = TravelProfileDraft(storedProfile(needs: wheelchair))
    #expect(draft.hasStoredAccessibility)
    #expect(draft.canEditAccessibility)
    #expect(draft.accessibility.mobility == .manualWheelchair)
    #expect(draft.accessibility.maxWalkPerLeg == 10)
  }

  @Test func needsWithoutAConsentTimeAreIgnored() {
    let draft = TravelProfileDraft(storedProfile(needs: wheelchair, consented: false))
    #expect(!draft.hasStoredAccessibility)
    #expect(draft.accessibility == AccessibilityNeedsDraft())
  }

  @Test func unchangedStoredNeedsAreNotResent() {
    let request = TravelProfileDraft(storedProfile(needs: wheelchair)).updateRequest(id: "p1")
    #expect(!request.hasAccessibilityNeeds, "an absent message leaves the stored needs alone")
    #expect(!request.clearAccessibilityNeeds_p)
  }

  @Test func editedStoredNeedsAreSentWithoutFreshConsent() {
    var draft = TravelProfileDraft(storedProfile(needs: wheelchair))
    draft.accessibility.needsAccessibleToilet = true
    let request = draft.updateRequest(id: "p1")
    #expect(request.hasAccessibilityNeeds)
    #expect(request.accessibilityNeeds.needsAccessibleToilet)
    #expect(!request.accessibilityConsentGiven, "the stored consent stands")
  }

  @Test func deleteClearsAndLocks() {
    var draft = TravelProfileDraft(storedProfile(needs: wheelchair))
    draft.deleteAccessibility()
    #expect(!draft.canEditAccessibility, "after a delete, editing needs consent again")
    let request = draft.updateRequest(id: "p1")
    #expect(request.clearAccessibilityNeeds_p)
    #expect(!request.hasAccessibilityNeeds, "clear and needs are never sent together")
  }

  @Test func emptyingStoredNeedsDeletesThem() {
    var draft = TravelProfileDraft(storedProfile(needs: wheelchair))
    draft.accessibility = AccessibilityNeedsDraft()
    #expect(draft.updateRequest(id: "p1").clearAccessibilityNeeds_p)
  }

  @Test func reconsentAfterDeleteSendsNewNeeds() {
    var draft = TravelProfileDraft(storedProfile(needs: wheelchair))
    draft.deleteAccessibility()
    draft.accessibilityConsentGiven = true
    draft.accessibility.blind = true
    let request = draft.updateRequest(id: "p1")
    #expect(request.hasAccessibilityNeeds && request.accessibilityNeeds.blind)
    #expect(request.accessibilityConsentGiven)
    #expect(!request.clearAccessibilityNeeds_p, "the server applies clear over needs, so it must not be sent")
  }

  @Test func deletingNeverStoredNeedsSendsNoClear() {
    var draft = TravelProfileDraft(storedProfile(needs: nil))
    draft.accessibilityConsentGiven = true
    draft.accessibility.blind = true
    draft.deleteAccessibility()
    let request = draft.updateRequest(id: "p1")
    #expect(!request.clearAccessibilityNeeds_p && !request.hasAccessibilityNeeds)
  }

  @Test func draftRoundTripsEveryField() {
    var needs = Loci_Profile_AccessibilityNeeds()
    needs.mobility = .mobilityScooter
    needs.maxWalkMinutesPerLeg = 15
    needs.maxWalkMinutesPerDay = 90
    needs.stepFreeOnly = true
    needs.maxIncline = .pct6
    needs.restEveryMinutes = 45
    needs.needsSeatingAtStops = true
    needs.needsAccessibleToilet = true
    needs.avoidCobbles = true
    needs.lowVision = true
    needs.blind = true
    needs.deafOrHardOfHearing = true
    needs.sensorySensitive = true
    needs.prefersQuietTimes = true
    needs.needsPredictablePlan = true
    needs.fatigueOrChronicPain = true
    needs.serviceAnimal = true
    needs.stroller = true
    needs.travellingWithCompanion = true
    needs.notes = "Notes"
    #expect(AccessibilityNeedsDraft(needs).proto == needs, "a field dropped here is a need the planner never hears")
  }

  @Test func inactiveMatchesTheServer() {
    var draft = AccessibilityNeedsDraft()
    #expect(!draft.isActive)
    draft.notes = "   "
    #expect(!draft.isActive, "whitespace is not a need")
    draft.stroller = true
    #expect(draft.isActive && draft.needsStepFree)
  }
}

@MainActor @Suite("Accessibility in search results") struct AccessibilityResultsTests {
  private func routeEvent(day: Int32, id: String, minutes: Int32) -> Loci_Chat_StreamEvent {
    var leg = Loci_Chat_WalkingLeg()
    leg.fromPoiID = "a"
    leg.toPoiID = "b"
    leg.durationMin = minutes
    var event = Loci_Chat_StreamEvent()
    event.eventID = id
    event.accessibleRoute.day = day
    event.accessibleRoute.legs = [leg]
    event.accessibleRoute.totalWalkMinutes = minutes
    return event
  }

  @Test func accessibleRouteEventsAreKeptPerDay() {
    var state = SearchState()
    state.apply(Events.start("s1", domain: .itinerary, city: "Lisbon"))
    state.apply(routeEvent(day: 1, id: "r1", minutes: 12))
    state.apply(routeEvent(day: 2, id: "r2", minutes: 30))
    #expect(state.accessibleRoutes[1]?.totalWalkMinutes == 12)
    #expect(state.accessibleRoutes[2]?.totalWalkMinutes == 30)
    state.apply(routeEvent(day: 1, id: "r3", minutes: 14))
    #expect(state.accessibleRoutes[1]?.totalWalkMinutes == 14, "a later event for a day replaces it")
  }

  @Test func legMatchesTheStopItArrivesAt() {
    var leg = Loci_Chat_WalkingLeg()
    leg.toPoiID = "poi-2"
    var named = Loci_Chat_WalkingLeg()
    named.toPoiID = "Unsaved café"
    var route = Loci_Chat_AccessibleRoutePayload()
    route.legs = [leg, named]

    var stored = Loci_Poi_POIDetailedInfo()
    stored.id = "poi-2"
    var unsaved = Loci_Poi_POIDetailedInfo()
    unsaved.name = "Unsaved café"
    var first = Loci_Poi_POIDetailedInfo()
    first.id = "poi-1"

    #expect(route.leg(arrivingAt: stored)?.toPoiID == "poi-2")
    #expect(route.leg(arrivingAt: unsaved)?.toPoiID == "Unsaved café")
    #expect(route.leg(arrivingAt: first) == nil, "the first stop of a day has no leg")
  }

  @Test func notesSortBarriersFirstAndEvidenceBeforeEstimates() {
    func note(_ text: String, _ severity: Loci_Poi_AccessibilityNoteSeverity, _ source: Loci_Poi_AccessibilityNoteSource)
      -> Loci_Poi_AccessibilityNote
    {
      var n = Loci_Poi_AccessibilityNote()
      n.text = text
      n.severity = severity
      n.source = source
      return n
    }
    let sorted = [
      note("Lift", .info, .verifiedCrowd), note("Maybe steep", .caution, .aiEstimate), note("Steps only", .barrier, .openData),
      note("Cobbles", .caution, .routed),
    ].bySeverity.map(\.text)
    #expect(sorted == ["Steps only", "Cobbles", "Maybe steep", "Lift"])
  }

  @Test func sourceLabelsNameTheirOrigin() {
    var open = Loci_Poi_AccessibilityNote()
    open.source = .openData
    open.sourceLicence = "ODbL-1.0"
    var estimate = Loci_Poi_AccessibilityNote()
    estimate.source = .aiEstimate
    #expect(open.sourceLabel == "Open data · ODbL-1.0")
    #expect(estimate.sourceLabel.contains("AI estimate"))
    #expect(estimate.isEstimate && !open.isEstimate)
  }
}

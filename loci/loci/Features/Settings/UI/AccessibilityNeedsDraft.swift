import Foundation
import LociConnectProto

/// Form state for a traveller's access needs (profile.proto AccessibilityNeeds).
///
/// These are functional needs, never diagnoses, and they are GDPR Article 9
/// health data: the server stores them only with explicit consent, so the
/// editor keeps them locked until the traveller agrees (see
/// TravelProfileDraft.accessibilityConsentGiven).
struct AccessibilityNeedsDraft: Equatable {
  /// Minutes between two stops; 0 is "no limit".
  static let legChoices = [0, 5, 10, 15, 20, 30, 45, 60]
  /// Minutes in a whole day; 0 is "no limit".
  static let dayChoices = [0, 30, 60, 90, 120, 180, 240]
  /// Minutes between seated rests; 0 is "no rule".
  static let restChoices = [0, 20, 30, 45, 60, 90]
  /// The server's limit on the free-text note.
  static let notesLimit = 500

  static let mobilityChoices: [Loci_Profile_MobilityLevel] = [
    Loci_Profile_MobilityLevel.none, .limitedWalking, .walkingAid, .manualWheelchair, .powerWheelchair, .mobilityScooter,
  ]
  static let inclineChoices: [Loci_Profile_MaxIncline] = [.any, .pct10, .pct6, .pct3]

  var mobility = Loci_Profile_MobilityLevel.none
  var maxWalkPerLeg = 0
  var maxWalkPerDay = 0
  var stepFreeOnly = false
  var maxIncline = Loci_Profile_MaxIncline.any
  var restEvery = 0
  var needsSeating = false
  var needsAccessibleToilet = false
  var avoidCobbles = false
  var lowVision = false
  var blind = false
  var deafOrHardOfHearing = false
  var sensorySensitive = false
  var prefersQuietTimes = false
  var needsPredictablePlan = false
  var fatigue = false
  var serviceAnimal = false
  var stroller = false
  var travellingWithCompanion = false
  var notes = ""

  init() {}

  init(_ needs: Loci_Profile_AccessibilityNeeds) {
    mobility = needs.mobility == .unspecified ? Loci_Profile_MobilityLevel.none : needs.mobility
    maxWalkPerLeg = Int(needs.maxWalkMinutesPerLeg)
    maxWalkPerDay = Int(needs.maxWalkMinutesPerDay)
    stepFreeOnly = needs.stepFreeOnly
    maxIncline = needs.maxIncline == .unspecified ? .any : needs.maxIncline
    restEvery = Int(needs.restEveryMinutes)
    needsSeating = needs.needsSeatingAtStops
    needsAccessibleToilet = needs.needsAccessibleToilet
    avoidCobbles = needs.avoidCobbles
    lowVision = needs.lowVision
    blind = needs.blind
    deafOrHardOfHearing = needs.deafOrHardOfHearing
    sensorySensitive = needs.sensorySensitive
    prefersQuietTimes = needs.prefersQuietTimes
    needsPredictablePlan = needs.needsPredictablePlan
    fatigue = needs.fatigueOrChronicPain
    serviceAnimal = needs.serviceAnimal
    stroller = needs.stroller
    travellingWithCompanion = needs.travellingWithCompanion
    notes = needs.notes
  }

  var proto: Loci_Profile_AccessibilityNeeds {
    var needs = Loci_Profile_AccessibilityNeeds()
    needs.mobility = mobility
    needs.maxWalkMinutesPerLeg = Int32(maxWalkPerLeg)
    needs.maxWalkMinutesPerDay = Int32(maxWalkPerDay)
    needs.stepFreeOnly = stepFreeOnly
    needs.maxIncline = maxIncline
    needs.restEveryMinutes = Int32(restEvery)
    needs.needsSeatingAtStops = needsSeating
    needs.needsAccessibleToilet = needsAccessibleToilet
    needs.avoidCobbles = avoidCobbles
    needs.lowVision = lowVision
    needs.blind = blind
    needs.deafOrHardOfHearing = deafOrHardOfHearing
    needs.sensorySensitive = sensorySensitive
    needs.prefersQuietTimes = prefersQuietTimes
    needs.needsPredictablePlan = needsPredictablePlan
    needs.fatigueOrChronicPain = fatigue
    needs.serviceAnimal = serviceAnimal
    needs.stroller = stroller
    needs.travellingWithCompanion = travellingWithCompanion
    needs.notes = String(notes.trimmingCharacters(in: .whitespacesAndNewlines).prefix(Self.notesLimit))
    return needs
  }

  /// Whether the needs say anything. Matches the server's
  /// AccessibilityNeeds.Active: "no mobility constraint" and "any slope" are
  /// the same as unset, so an untouched form is "no needs".
  var isActive: Bool { proto != Self().proto }

  /// Wheels or a stroller mean step-free routing, as on the server.
  var needsStepFree: Bool { stepFreeOnly || stroller || [.manualWheelchair, .powerWheelchair, .mobilityScooter].contains(mobility) }
}

extension Loci_Profile_MobilityLevel {
  var label: String {
    switch self {
    case .limitedWalking: "I can walk short distances"
    case .walkingAid: "I use a cane, crutches or a walker"
    case .manualWheelchair: "I use a manual wheelchair"
    case .powerWheelchair: "I use a power wheelchair"
    case .mobilityScooter: "I use a mobility scooter"
    default: "No mobility needs"
    }
  }
}

extension Loci_Profile_MaxIncline {
  var label: String {
    switch self {
    case .pct3: "Gentle slopes only (3%)"
    case .pct6: "Moderate slopes (6%)"
    case .pct10: "Steeper slopes are fine (10%)"
    default: "Any slope"
    }
  }
}

extension Int {
  /// "No limit" for 0, otherwise "15 min".
  var minutesLimitLabel: String { self == 0 ? "No limit" : "\(self) min" }
}

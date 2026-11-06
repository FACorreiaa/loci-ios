import LociConnectProto
import SwiftUI

/// The travel profile's access needs, behind an explicit consent.
///
/// Needs are health data (GDPR Art. 9). Nothing here is editable, and nothing
/// is sent, until the traveller turns on the consent toggle — it starts off and
/// stays a separate choice from everything else in the form. A profile that
/// already holds consented needs opens unlocked, with a way to delete them.
struct AccessibilityNeedsSection: View {
  @Binding var draft: TravelProfileDraft

  var body: some View {
    consent
    Group {
      gettingAround
      restAndComfort
      senses
      company
      ownWords
    }.disabled(!draft.canEditAccessibility)
    if draft.hasStoredAccessibility { deletion }
  }

  private var needs: Binding<AccessibilityNeedsDraft> { $draft.accessibility }

  static let consentExplanation = """
    Tell Loci what you need, such as step-free routes, rest breaks or an accessible toilet, \
    and plans are built around it. This is health information: it is kept on this profile only, \
    never shown to other travellers or used for ads, and you can delete it at any time.
    """

  // MARK: - Consent

  @ViewBuilder private var consent: some View {
    if !draft.hasStoredAccessibility || draft.clearAccessibility {
      SwiftUI.Section {
        Toggle("Let Loci store my accessibility needs", isOn: $draft.accessibilityConsentGiven).accessibilityIdentifier("accessibility.consent")
      } header: {
        Text("Plans that work for you")
      } footer: {
        Text(Self.consentExplanation)
      }
    }
  }

  // MARK: - Needs

  private var gettingAround: some View {
    SwiftUI.Section("Getting around") {
      Picker("Mobility", selection: needs.mobility) { ForEach(AccessibilityNeedsDraft.mobilityChoices, id: \.self) { Text($0.label).tag($0) } }
      Picker("Longest walk between stops", selection: needs.maxWalkPerLeg) {
        ForEach(AccessibilityNeedsDraft.legChoices, id: \.self) { Text($0.minutesLimitLabel).tag($0) }
      }
      Picker("Walking in a whole day", selection: needs.maxWalkPerDay) {
        ForEach(AccessibilityNeedsDraft.dayChoices, id: \.self) { Text($0.minutesLimitLabel).tag($0) }
      }
      Toggle("Step-free routes and entrances only", isOn: needs.stepFreeOnly)
      Toggle("Travelling with a stroller", isOn: needs.stroller)
      if draft.accessibility.needsStepFree {
        Picker("Slopes", selection: needs.maxIncline) { ForEach(AccessibilityNeedsDraft.inclineChoices, id: \.self) { Text($0.label).tag($0) } }
      }
      Toggle("Avoid cobblestones", isOn: needs.avoidCobbles)
    }
  }

  private var restAndComfort: some View {
    SwiftUI.Section("Rest and comfort") {
      Picker("Seated rest every", selection: needs.restEvery) {
        ForEach(AccessibilityNeedsDraft.restChoices, id: \.self) { Text($0 == 0 ? "No need" : "\($0) min").tag($0) }
      }
      Toggle("Somewhere to sit at each stop", isOn: needs.needsSeating)
      Toggle("An accessible toilet nearby", isOn: needs.needsAccessibleToilet)
      Toggle("I tire quickly or live with pain", isOn: needs.fatigue)
    }
  }

  private var senses: some View {
    SwiftUI.Section("Seeing, hearing and senses") {
      Toggle("Low vision", isOn: needs.lowVision)
      Toggle("Blind", isOn: needs.blind)
      Toggle("Deaf or hard of hearing", isOn: needs.deafOrHardOfHearing)
      Toggle("Noise, crowds or bright light are hard", isOn: needs.sensorySensitive)
      Toggle("Prefer quiet, off-peak times", isOn: needs.prefersQuietTimes)
      Toggle("A predictable plan helps me", isOn: needs.needsPredictablePlan)
    }
  }

  private var company: some View {
    SwiftUI.Section("Travelling with") {
      Toggle("A service animal", isOn: needs.serviceAnimal)
      Toggle("A companion or carer", isOn: needs.travellingWithCompanion)
    }
  }

  private var ownWords: some View {
    SwiftUI.Section {
      TextField("Anything else Loci should know", text: needs.notes, axis: .vertical).lineLimit(2...5).onChange(of: draft.accessibility.notes) {
        _,
        value in
        if value.count > AccessibilityNeedsDraft.notesLimit { draft.accessibility.notes = String(value.prefix(AccessibilityNeedsDraft.notesLimit)) }
      }
    } header: {
      Text("In your own words")
    } footer: {
      Text("\(draft.accessibility.notes.count)/\(AccessibilityNeedsDraft.notesLimit)").accessibilityLabel(
        "\(draft.accessibility.notes.count) of \(AccessibilityNeedsDraft.notesLimit) characters"
      )
    }
  }

  // MARK: - Deletion

  private var deletion: some View {
    SwiftUI.Section {
      if draft.clearAccessibility {
        Label("Your accessibility needs will be deleted when you save.", systemImage: "trash").foregroundStyle(.secondary)
      } else {
        Button("Delete my accessibility info", role: .destructive) { draft.deleteAccessibility() }.accessibilityIdentifier("accessibility.delete")
      }
    } footer: {
      Text("Deleting also withdraws your consent. Loci will ask again before storing needs.")
    }
  }
}

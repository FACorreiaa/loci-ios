import LociConnectProto
import SwiftUI

/// Taste and privacy (web: TasteAndPrivacy). RecommendationService:
/// GetPersonalizationSettings, UpdatePersonalizationSettings, GetTasteProfile,
/// ResetTasteProfile{confirmation: "RESET"}.
struct PersonalizationSettingsView: View {
  @State private var settings: Loci_Recommendation_PersonalizationSettings?
  @State private var taste: Loci_Recommendation_TasteProfile?
  @State private var confirmReset = false
  @State private var error: String?

  var body: some View {
    Form {
      if let settings {
        Section {
          Toggle("Personalise my results", isOn: binding(settings.personalizationEnabled) { $0.personalizationEnabled = $1 })
          Toggle(
            "Contribute anonymously to city trends",
            isOn: binding(settings.contributeAggregate) { $0.contributeAggregate = $1 }
          )
        } footer: {
          Text("Loci learns from what you save and skip. Turn this off and results stop adapting to you.")
        }
      }

      Section("What Loci has learned") {
        if let taste, !taste.traits.isEmpty {
          ForEach(taste.traits, id: \.key) { trait in
            LabeledContent(trait.label) { Text(trait.score, format: .number.precision(.fractionLength(2))).font(.lociCoord(12)) }
          }
          Text("Based on \(taste.feedbackCount) signals").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        } else {
          Text("Nothing yet. Save or skip a few places and this fills in.").foregroundStyle(Color.lociMutedInk)
        }
      }

      Section {
        Button("Reset taste profile", role: .destructive) { confirmReset = true }
      }
    }
    .settingsStyle("Taste and privacy")
    .confirmationDialog("Forget everything Loci has learned about your taste?", isPresented: $confirmReset, titleVisibility: .visible) {
      Button("Reset", role: .destructive) { Task { await reset() } }
    }
    .errorAlert($error)
    .task { await load() }
  }

  private func binding(
    _ value: Bool,
    _ apply: @escaping (inout Loci_Recommendation_UpdatePersonalizationSettingsRequest, Bool) -> Void
  ) -> Binding<Bool> {
    Binding(get: { value }, set: { newValue in Task { await update(newValue, apply) } })
  }

  private func load() async {
    do {
      async let settingsCall = rpc("Could not load your settings.") {
        await SettingsClients.recommendation.getPersonalizationSettings(request: .init(), headers: [:])
      }
      async let tasteCall = rpc("Could not load your taste profile.") {
        await SettingsClients.recommendation.getTasteProfile(request: .init(), headers: [:])
      }
      settings = try await settingsCall
      taste = try await tasteCall
    } catch { self.error = error.userMessage }
  }

  /// The request carries every flag, so send the current values with one changed.
  private func update(_ value: Bool, _ apply: (inout Loci_Recommendation_UpdatePersonalizationSettingsRequest, Bool) -> Void) async {
    guard let settings else { return }
    var request = Loci_Recommendation_UpdatePersonalizationSettingsRequest()
    request.personalizationEnabled = settings.personalizationEnabled
    request.contributeAggregate = settings.contributeAggregate
    request.disclosureSeen = true
    apply(&request, value)
    do {
      self.settings = try await rpc("Could not save.", request) {
        await SettingsClients.recommendation.updatePersonalizationSettings(request: $0, headers: [:])
      }
    } catch { self.error = error.userMessage }
  }

  private func reset() async {
    var request = Loci_Recommendation_ResetTasteProfileRequest()
    request.confirmation = "RESET"
    do {
      _ = try await rpc("Could not reset.", request) { await SettingsClients.recommendation.resetTasteProfile(request: $0, headers: [:]) }
      await load()
    } catch { self.error = error.userMessage }
  }
}

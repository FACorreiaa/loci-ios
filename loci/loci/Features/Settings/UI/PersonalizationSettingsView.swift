import LociConnectProto
import SwiftUI

/// Taste and privacy (web: TasteAndPrivacy). RecommendationService:
/// GetPersonalizationSettings, UpdatePersonalizationSettings, GetTasteProfile,
/// ResetTasteProfile{confirmation: "RESET"}.
struct PersonalizationSettingsView: View {
  @State private var settings: Loci_Recommendation_PersonalizationSettings?
  @State private var taste: Loci_Recommendation_TasteProfile?
  /// Bumped per save, so only the newest reply (or failure) lands when flips overlap.
  @State private var saveGeneration = 0
  @State private var confirmReset = false
  @State private var error: String?

  var body: some View {
    Form {
      if settings != nil {
        Section {
          Toggle("Personalise my results", isOn: binding(\.personalizationEnabled))
          Toggle("Contribute anonymously to city trends", isOn: binding(\.contributeAggregate))
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

  /// Flips the switch at once and saves from the updated settings, so a quick
  /// second flip builds on the first rather than on stale values.
  private func binding(_ flag: WritableKeyPath<Loci_Recommendation_PersonalizationSettings, Bool>) -> Binding<Bool> {
    Binding(
      get: { settings?[keyPath: flag] ?? false },
      set: { newValue in
        guard let previous = settings else { return }
        var updated = previous
        updated[keyPath: flag] = newValue
        settings = updated
        saveGeneration += 1
        let generation = saveGeneration
        Task { await update(updated, generation: generation, rollback: previous) }
      }
    )
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

  /// The request carries every flag, so send the updated values; a failure puts the switch back.
  private func update(
    _ updated: Loci_Recommendation_PersonalizationSettings,
    generation: Int,
    rollback previous: Loci_Recommendation_PersonalizationSettings
  ) async {
    var request = Loci_Recommendation_UpdatePersonalizationSettingsRequest()
    request.personalizationEnabled = updated.personalizationEnabled
    request.contributeAggregate = updated.contributeAggregate
    request.disclosureSeen = true
    do {
      let saved = try await rpc("Could not save.", request) {
        await SettingsClients.recommendation.updatePersonalizationSettings(request: $0, headers: [:])
      }
      if generation == saveGeneration { settings = saved }
    } catch {
      guard generation == saveGeneration else { return }
      settings = previous
      self.error = error.userMessage
    }
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

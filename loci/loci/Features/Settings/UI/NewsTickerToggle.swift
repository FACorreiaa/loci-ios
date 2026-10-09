import LociConnectProto
import SwiftUI

/// The travel-news strip on/off switch (web: NewsTickerToggle).
/// LocalContextService.GetNewsTicker reads the state; SetNewsTickerEnabled{enabled} writes it.
struct NewsTickerToggle: View {
  @State private var enabled: Bool?
  /// Bumped per save, so only the newest reply (or failure) lands when flips overlap.
  @State private var saveGeneration = 0
  @State private var error: String?

  var body: some View {
    Toggle(isOn: isOn) {
      Label("Travel news strip", systemImage: "newspaper")
    }
    .disabled(enabled == nil)
    .errorAlert($error)
    .task { await load() }
  }

  /// Flips at once; a failed save puts it back.
  private var isOn: Binding<Bool> {
    Binding(
      get: { enabled ?? false },
      set: { value in
        guard let previous = enabled else { return }
        enabled = value
        saveGeneration += 1
        let generation = saveGeneration
        Task { await set(value, generation: generation, rollback: previous) }
      }
    )
  }

  private func load() async {
    var request = Loci_Localcontext_GetNewsTickerRequest()
    request.limit = 1
    do {
      enabled = try await rpc("Could not load the news strip setting.", request) {
        await SettingsClients.localContext.getNewsTicker(request: $0, headers: [:])
      }.enabled
    } catch { self.error = error.userMessage }
  }

  private func set(_ value: Bool, generation: Int, rollback previous: Bool) async {
    var request = Loci_Localcontext_SetNewsTickerEnabledRequest()
    request.enabled = value
    do {
      let saved = try await rpc("Could not change the news strip.", request) {
        await SettingsClients.localContext.setNewsTickerEnabled(request: $0, headers: [:])
      }.enabled
      if generation == saveGeneration { enabled = saved }
    } catch {
      guard generation == saveGeneration else { return }
      enabled = previous
      self.error = error.userMessage
    }
  }
}

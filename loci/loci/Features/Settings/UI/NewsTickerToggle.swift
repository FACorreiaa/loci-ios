import LociConnectProto
import SwiftUI

/// The travel-news strip on/off switch (web: NewsTickerToggle).
/// LocalContextService.GetNewsTicker reads the state; SetNewsTickerEnabled{enabled} writes it.
struct NewsTickerToggle: View {
  @State private var enabled: Bool?
  @State private var error: String?

  var body: some View {
    Toggle(isOn: Binding(get: { enabled ?? false }, set: { value in Task { await set(value) } })) {
      Label("Travel news strip", systemImage: "newspaper")
    }
    .disabled(enabled == nil)
    .errorAlert($error)
    .task { await load() }
  }

  private func load() async {
    var request = Loci_Localcontext_GetNewsTickerRequest()
    request.limit = 1
    enabled = try? await rpc("", request) { await SettingsClients.localContext.getNewsTicker(request: $0, headers: [:]) }.enabled
  }

  private func set(_ value: Bool) async {
    var request = Loci_Localcontext_SetNewsTickerEnabledRequest()
    request.enabled = value
    do {
      enabled = try await rpc("Could not change the news strip.", request) {
        await SettingsClients.localContext.setNewsTickerEnabled(request: $0, headers: [:])
      }.enabled
    } catch { self.error = error.userMessage }
  }
}

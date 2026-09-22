import LociConnectProto
import SwiftUI

/// The subscribable calendar of the user's trips (CalendarService.GetTripCalendarFeedUrl).
struct TripCalendarFeedSection: View {
  @State private var url: URL?
  @State private var error: String?

  var body: some View {
    Section {
      if let url {
        ShareLink(item: url) { Label("Share feed link", systemImage: "square.and.arrow.up") }
        if let webcal = Self.webcal(url) { Link("Subscribe on this iPhone", destination: webcal) }
      } else {
        Button("Get my trips feed") { Task { await load() } }
      }
    } header: {
      Text("Trips feed")
    } footer: {
      Text("A private link any calendar app can subscribe to. Your trips stay up to date there.")
    }
    .errorAlert($error)
  }

  /// Calendar apps subscribe through webcal://.
  static func webcal(_ url: URL) -> URL? {
    var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
    components?.scheme = "webcal"
    return components?.url
  }

  private func load() async {
    do {
      let response = try await rpc("Could not get the feed link.") {
        await SettingsClients.calendar.getTripCalendarFeedURL(request: .init(), headers: [:])
      }
      url = URL(string: response.url)
    } catch { self.error = error.userMessage }
  }
}

import Connect
import CoreLocation
import LociConnectProto
import SwiftUI

/// Where the traveller is standing (web: HereNowBand). Loads only when location
/// is already authorised — Discover never raises the permission prompt; Nearby does.
@MainActor @Observable
final class HereBriefModel {
  var brief: Loci_Localcontext_HereBrief?

  var placeName: String {
    guard let place = brief?.place else { return "" }
    return place.locality.isEmpty ? place.region : place.locality
  }

  var hasAnything: Bool {
    guard let b = brief else { return false }
    return !(b.weather.isEmpty && b.alerts.isEmpty && b.local.isEmpty && b.disruption.isEmpty && b.whatsOn.isEmpty)
  }

  func load() async {
    let status = CLLocationManager().authorizationStatus
    guard status == .authorizedWhenInUse || status == .authorizedAlways else { return }
    guard let coord = try? await CurrentLocation.fetch(timeout: .seconds(8)) else { return }
    var req = Loci_Localcontext_GetHereBriefRequest()
    req.latitude = (coord.latitude * 100).rounded() / 100
    req.longitude = (coord.longitude * 100).rounded() / 100
    let res = await SettingsClients.localContext.getHereBrief(request: req, headers: [:])
    if let message = res.message { brief = message }
  }
}

struct HereBriefSection: View {
  let model: HereBriefModel
  @Environment(\.openURL) private var openURL

  var body: some View {
    if model.hasAnything, let brief = model.brief {
      VStack(alignment: .leading, spacing: 16) {
        Text(model.placeName.isEmpty ? "Here now" : "Here now · \(model.placeName)")
          .font(.lociHeadline())
          .foregroundStyle(Color.lociInk)
        today(brief)
        list("Around you", brief.local)
        list("Getting around", brief.disruption)
        list("What's on", brief.whatsOn)
        if brief.stale {
          Text("Some sources delayed").font(.lociCaption(11)).foregroundStyle(.secondary)
        }
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.lociCard, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
      .overlay(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).stroke(Color.lociBorder))
    }
  }

  @ViewBuilder private func today(_ brief: Loci_Localcontext_HereBrief) -> some View {
    if let t = brief.weather.first {
      HStack(alignment: .firstTextBaseline, spacing: 8) {
        Text("\(Int(t.highC.rounded()))° / \(Int(t.lowC.rounded()))°").font(.lociBody()).monospacedDigit()
        Text(brief.weatherIsEstimated ? "\(t.condition) · estimated" : t.condition)
          .font(.lociCaption(13)).foregroundStyle(.secondary)
      }
    }
    ForEach(Array(brief.alerts.prefix(3).enumerated()), id: \.offset) { _, alert in
      Label(alert.title, systemImage: "exclamationmark.triangle")
        .font(.lociCaption(13))
        .foregroundStyle(alert.severity >= 0.6 ? Color.red : Color.lociInk)
    }
  }

  @ViewBuilder private func list(_ title: String, _ items: [Loci_Localcontext_NewsTickerItem]) -> some View {
    if !items.isEmpty {
      VStack(alignment: .leading, spacing: 8) {
        Text(title.uppercased()).font(.lociCaption(11)).tracking(1.2).foregroundStyle(.secondary)
        ForEach(items.prefix(3), id: \.id) { item in
          Button {
            if let url = URL(string: item.url) { openURL(url) }
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(item.title).font(.lociBody()).foregroundStyle(Color.lociInk).lineLimit(2).multilineTextAlignment(.leading)
              Text(item.source).font(.lociCaption(11)).foregroundStyle(.secondary)
            }
          }
          .buttonStyle(.plain)
        }
      }
    }
  }
}

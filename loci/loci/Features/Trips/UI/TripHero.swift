import LociConnectProto
import SwiftUI

/// The trip masthead (web: components/trip/TripHero.tsx): "Route · N days",
/// the title, the city and the date range. The trip's `version` is not shown;
/// it is concurrency bookkeeping, not something a traveller uses.
struct TripHero: View {
  let trip: Loci_Trip_TripDraft

  private static let fill = LinearGradient(
    colors: [Color(hex: 0x214D3C), Color(hex: 0x2F7D6E)],
    startPoint: .topLeading,
    endPoint: .bottomTrailing
  )

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(TripFormat.heroEyebrow(dayCount: trip.days.count).uppercased())
        .font(.lociCoord(10)).tracking(2)
        .foregroundStyle(LociTheme.stampInk.opacity(0.7))
      Text(trip.title.isEmpty ? trip.cityName : trip.title)
        .font(.lociDisplay(28)).foregroundStyle(LociTheme.stampInk)
        .fixedSize(horizontal: false, vertical: true)
      ViewThatFits(in: .horizontal) {
        HStack(spacing: 16) { details }
        VStack(alignment: .leading, spacing: 6) { details }
      }
      .foregroundStyle(LociTheme.stampInk.opacity(0.8))
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(20)
    .background(Self.fill, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadiusHero, style: .continuous))
    .accessibilityElement(children: .combine)
  }

  @ViewBuilder private var details: some View {
    if !trip.cityName.isEmpty {
      Label(trip.cityName, systemImage: "mappin.and.ellipse").font(.lociCaption(14))
    }
    if let dates = TripFormat.tripDates(trip.days) {
      Label(dates.uppercased(), systemImage: "calendar").font(.lociCoord(11)).tracking(1)
    }
  }
}

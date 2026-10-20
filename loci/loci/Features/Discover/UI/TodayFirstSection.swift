import LociConnectProto
import SwiftUI

/// Leads Discover on a trip day (web: TodayBand on the dashboard): which day
/// it is, the stop to head for next, and the way into the day.
struct TodayFirstSection: View {
  let today: TodayFirst

  private var city: String { today.day.cityName.isEmpty ? today.trip.cityName : today.day.cityName }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text("Today · Day \(today.day.dayNumber) in \(city)").lociCoordStyle(10)
      Text(today.trip.title.isEmpty ? city : today.trip.title).font(.lociDisplay(26)).foregroundStyle(Color.lociInk)
      if let next = today.next {
        HStack(spacing: 12) {
          Image(systemName: "mappin.and.ellipse").font(.title3).foregroundStyle(Color.lociForest).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 2) {
            Text("Next").lociCoordStyle(10)
            Text(next.name).font(.lociHeadline(16)).foregroundStyle(Color.lociInk).lineLimit(2)
            if next.hasStartMinute { Text(Self.clock(next.startMinute)).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
          }
          Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.lociSage.opacity(0.5), in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
      }
      Text("^[\(today.day.stops.count) stop](inflect: true) planned today").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
      NavigationLink(value: AppRoute.trip(id: today.trip.id)) {
        Label("Open today", systemImage: "arrow.right.circle")
      }
      .buttonStyle(MusePillButtonStyle())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .lociCard()
  }

  /// 840 → "14:00".
  nonisolated static func clock(_ minute: Int32) -> String {
    String(format: "%02d:%02d", Int(minute) / 60 % 24, Int(minute) % 60)
  }
}

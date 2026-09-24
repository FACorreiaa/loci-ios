import LociConnectProto
import SwiftUI

/// "Today" above the trips list when a cached trip has a day dated today:
/// the city, the first stops, and the way into the Live Activity.
struct TodayBand: View {
  let trip: Loci_Trip_TripDraft
  let day: Loci_Trip_TripDay

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Today · \(day.cityName.isEmpty ? trip.cityName : day.cityName)").lociCoordStyle(10)
      Text(trip.title.isEmpty ? "Day \(day.dayNumber)" : trip.title).font(.lociHeadline(17)).foregroundStyle(Color.lociInk)
      ForEach(day.stops.prefix(3), id: \.id) { stop in
        Label(stop.name, systemImage: "mappin").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk).lineLimit(1)
      }
      TodayControls(trip: trip, day: day, showsOpen: true)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .lociCard()
  }
}

/// Start / Next / Done for the trip-day activity; shared by the band and the
/// editor's day header.
struct TodayControls: View {
  let trip: Loci_Trip_TripDraft
  let day: Loci_Trip_TripDay
  var showsOpen = false
  private let controller = TripDayActivityController.shared

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack(spacing: 8) {
        if controller.isRunning, controller.running?.dayId == day.id {
          if showsOpen { NavigationLink(value: trip.id) { Label("Open today", systemImage: "arrow.right.circle") } }
          Button("Next", systemImage: "forward.end") { Task { await controller.advance() } }
          Button("Done", systemImage: "checkmark") { Task { await controller.end() } }
        } else {
          Button("Start today", systemImage: "play.fill") { Task { await controller.start(trip: trip, day: day) } }
            .disabled(!controller.liveActivitiesEnabled)
        }
      }
      .buttonStyle(MusePillButtonStyle())
      if !controller.liveActivitiesEnabled {
        Text("Turn on Live Activities for Loci in Settings to follow the day from the Lock Screen.")
          .font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
      }
    }
  }
}

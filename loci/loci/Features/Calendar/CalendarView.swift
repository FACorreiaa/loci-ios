import Connect
import LociConnectProto
import SwiftProtobuf
import SwiftUI

public struct CalendarView: View {
  @State private var trips: [Loci_Trip_TripDraft] = []
  @State private var isLoading = false
  @State private var errorMessage: String?
  @State private var cursor = Date()
  @State private var selectedKey: String = CalendarMath.dateKey(Date())
  @State private var pinning: Loci_Trip_TripDraft?
  @State private var pinStart = Date()
  @State private var appleTitles: [String] = []

  private let client: Loci_Trip_TripServiceClient

  public init(client: Loci_Trip_TripServiceClient = Loci_Trip_TripServiceClient(client: ConnectTransport.shared.protocolClient)) {
    self.client = client
  }

  private var calendar: Calendar { Calendar.current }

  private var year: Int { calendar.component(.year, from: cursor) }
  private var month: Int { calendar.component(.month, from: cursor) }

  private var cells: [MonthCell] { CalendarMath.monthCells(year: year, month: month) }

  private var blocks: [CalendarTripBlock] {
    trips.flatMap { trip in
      trip.days.compactMap { day -> CalendarTripBlock? in
        guard day.hasDate else { return nil }
        let date = Date(timeIntervalSince1970: TimeInterval(day.date.seconds))
        return CalendarTripBlock(
          tripId: trip.id,
          title: trip.title.isEmpty ? (trip.cityName.isEmpty ? "Untitled trip" : "Trip to \(trip.cityName)") : trip.title,
          cityName: day.cityName.isEmpty ? trip.cityName : day.cityName,
          dayNumber: day.dayNumber,
          dateKey: CalendarMath.dateKey(date)
        )
      }
    }
  }

  private var unscheduled: [Loci_Trip_TripDraft] {
    trips.filter { trip in !trip.days.contains(where: { $0.hasDate }) }
  }

  private func blocks(on key: String) -> [CalendarTripBlock] { blocks.filter { $0.dateKey == key } }

  public var body: some View {
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          monthHeader
          weekdayHeader
          monthGrid
          agenda
          unscheduledSection
        }.padding(.horizontal, 16).padding(.bottom, 24)
      }.background(Color.lociPaper.ignoresSafeArea()).navigationTitle("Calendar").toolbar {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink { TripsView() } label: { Image(systemName: "list.bullet") }
        }
        ToolbarItem(placement: .primaryAction) {
          Button { loadTrips() } label: { Image(systemName: "arrow.clockwise") }
        }
      }.task {
        loadTrips()
        refreshApple()
      }.sheet(item: $pinning) { trip in
        pinSheet(trip)
      }
    }
  }

  private var monthHeader: some View {
    HStack {
      Button { shiftMonth(-1) } label: { Image(systemName: "chevron.left") }
      Spacer()
      Text(cursor, format: .dateTime.month(.wide).year()).font(.title2.weight(.semibold)).foregroundColor(.lociInk)
      Spacer()
      Button { shiftMonth(1) } label: { Image(systemName: "chevron.right") }
    }.foregroundColor(.lociCoral)
  }

  private var weekdayHeader: some View {
    HStack(spacing: 0) {
      ForEach(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], id: \.self) { day in
        Text(day).font(.caption2.weight(.semibold)).foregroundColor(.lociInk.opacity(0.5)).frame(maxWidth: .infinity)
      }
    }
  }

  private var monthGrid: some View {
    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
      ForEach(cells, id: \.dateKey) { cell in
        let dayBlocks = blocks(on: cell.dateKey)
        Button {
          selectedKey = cell.dateKey
          refreshApple()
        } label: {
          VStack(alignment: .leading, spacing: 2) {
            Text("\(cell.day)").font(.caption.weight(.medium)).foregroundColor(
              cell.inMonth ? .lociInk : .lociInk.opacity(0.35)
            )
            ForEach(Array(dayBlocks.prefix(2))) { block in
              Text(block.title).font(.system(size: 9, weight: .semibold)).foregroundColor(.white).lineLimit(1)
                .padding(.horizontal, 3).padding(.vertical, 1).background(Color.lociCoral).cornerRadius(3)
            }
          }.frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading).padding(4).background(
            selectedKey == cell.dateKey ? Color.lociCoral.opacity(0.15) : Color.lociCard
          ).cornerRadius(8).overlay(
            RoundedRectangle(cornerRadius: 8).stroke(
              selectedKey == cell.dateKey ? Color.lociCoral : Color.lociBorder.opacity(0.5),
              lineWidth: LociTheme.borderWidth
            )
          )
        }
      }
    }
  }

  private var agenda: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(agendaTitle).font(.headline).foregroundColor(.lociInk)
      let dayBlocks = blocks(on: selectedKey)
      if dayBlocks.isEmpty && appleTitles.isEmpty {
        Text("No Loci trips on this day.").font(.subheadline).foregroundColor(.lociInk.opacity(0.6))
      } else {
        ForEach(dayBlocks) { block in
          VStack(alignment: .leading, spacing: 4) {
            Text(block.title).font(.subheadline.weight(.semibold)).foregroundColor(.lociInk)
            Text("\(block.cityName) · Day \(block.dayNumber)").font(.caption).foregroundColor(.lociInk.opacity(0.6))
            if AppleCalendar.shared.isAuthorized, let trip = trips.first(where: { $0.id == block.tripId }) {
              Button("Add to Apple Calendar") { try? AppleCalendar.shared.writeTrip(trip) }.font(.caption).foregroundColor(
                .lociCoral
              )
            }
          }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(Color.lociCard).cornerRadius(
            LociTheme.cornerRadius
          )
        }
        ForEach(appleTitles, id: \.self) { title in
          Text(title).font(.subheadline).foregroundColor(.lociInk.opacity(0.8)).padding(12).frame(
            maxWidth: .infinity,
            alignment: .leading
          ).background(Color.lociSage.opacity(0.2)).cornerRadius(LociTheme.cornerRadius)
        }
      }
    }
  }

  private var unscheduledSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Unscheduled").font(.headline).foregroundColor(.lociInk)
      Text("Trips without calendar dates yet.").font(.caption).foregroundColor(.lociInk.opacity(0.6))
      if unscheduled.isEmpty {
        Text("Everything has a date.").font(.subheadline).foregroundColor(.lociInk.opacity(0.6))
      } else {
        ForEach(unscheduled, id: \.id) { trip in
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(trip.title.isEmpty ? (trip.cityName.isEmpty ? "Untitled trip" : trip.cityName) : trip.title).font(
                .subheadline.weight(.semibold)
              )
              Text("\(trip.days.count) days").font(.caption).foregroundColor(.lociInk.opacity(0.6))
            }
            Spacer()
            Button("Pin dates") {
              pinning = trip
              pinStart = CalendarMath.parseDateKey(selectedKey) ?? Date()
            }.foregroundColor(.lociCoral)
          }.padding(12).background(Color.lociCard).cornerRadius(LociTheme.cornerRadius)
        }
      }
    }
  }

  private func pinSheet(_ trip: Loci_Trip_TripDraft) -> some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Text("Day 1 of this trip will start on the date you pick. Later days follow in order.").font(.subheadline)
          .foregroundColor(.lociInk.opacity(0.7))
        DatePicker("Starts", selection: $pinStart, displayedComponents: .date)
        Spacer()
      }.padding().navigationTitle("Pin dates").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pinning = nil } }
        ToolbarItem(placement: .confirmationAction) { Button("Save") { savePinned(trip) } }
      }
    }.presentationDetents([.medium])
  }

  private var agendaTitle: String {
    guard let date = CalendarMath.parseDateKey(selectedKey) else { return selectedKey }
    return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
  }

  private func shiftMonth(_ delta: Int) {
    if let next = calendar.date(byAdding: .month, value: delta, to: cursor) { cursor = next }
  }

  private func refreshApple() {
    guard let day = CalendarMath.parseDateKey(selectedKey) else {
      appleTitles = []
      return
    }
    let start = calendar.startOfDay(for: day)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
    appleTitles = AppleCalendar.shared.events(from: start, to: end).compactMap(\.title)
  }

  private func loadTrips() {
    isLoading = true
    errorMessage = nil
    Task {
      let headers: Connect.Headers = [:]
      let response = await client.listTrips(request: Loci_Trip_ListTripsRequest(), headers: headers)
      await MainActor.run {
        isLoading = false
        if let error = response.error { errorMessage = error.message } else if let message = response.message {
          trips = message.trips
        }
      }
    }
  }

  private func savePinned(_ trip: Loci_Trip_TripDraft) {
    var updated = trip
    let origin = calendar.startOfDay(for: pinStart)
    updated.days = trip.days.map { day in
      var copy = day
      let shifted = calendar.date(byAdding: .day, value: Int(day.dayNumber - 1), to: origin) ?? origin
      var ts = SwiftProtobuf.Google_Protobuf_Timestamp()
      ts.seconds = Int64(shifted.timeIntervalSince1970)
      copy.date = ts
      return copy
    }
    Task {
      let headers: Connect.Headers = [:]
      var req = Loci_Trip_SaveTripRequest()
      req.trip = updated
      req.baseVersion = trip.version
      _ = await client.saveTrip(request: req, headers: headers)
      await MainActor.run {
        pinning = nil
        loadTrips()
      }
    }
  }
}

extension Loci_Trip_TripDraft: @retroactive Identifiable {}

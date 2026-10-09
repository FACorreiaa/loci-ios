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
  @State private var isPinSaving = false
  @State private var pinError: String?
  @State private var appleTitles: [String] = []
  @State private var linked: AppLink?
  private let router = AppRouter.shared

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

  /// Weekday names in the grid's Monday-first order (`CalendarMath.monthCells`),
  /// from the user's locale rather than hard-coded English.
  private var weekdaySymbols: [String] {
    let symbols = calendar.shortStandaloneWeekdaySymbols
    return Array(symbols.dropFirst()) + Array(symbols.prefix(1))
  }

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
      }.background { Color.lociPaper.ignoresSafeArea() }.navigationTitle("Calendar").toolbar {
        ToolbarItem(placement: .topBarLeading) {
          NavigationLink(value: AppRoute.trips) { Label("Trips", systemImage: "list.bullet") }
        }
        ToolbarItem(placement: .primaryAction) {
          if isLoading {
            ProgressView()
          } else {
            Button("Reload", systemImage: "arrow.clockwise") { loadTrips() }
          }
        }
      }.task {
        loadTrips()
        refreshApple()
      }.sheet(item: $pinning) { trip in
        pinSheet(trip)
      }
      .errorAlert($errorMessage)
      .appRouteDestinations()
      .navigationDestination(item: $linked) { AppLinkDestination(link: $0) }
      .onAppear(perform: openPending)
      .onChange(of: router.pendingLink) { openPending() }
    }
  }

  /// A `/trips/:id` link opens the trip editor over the calendar.
  private func openPending() {
    if let link = router.takeLink(for: .calendar) { linked = link }
  }

  private var monthHeader: some View {
    HStack {
      Button("Previous month", systemImage: "chevron.left") { shiftMonth(-1) }.labelStyle(.iconOnly)
      Spacer()
      Text(cursor, format: .dateTime.month(.wide).year()).font(.title2.weight(.semibold)).foregroundStyle(Color.lociInk)
      Spacer()
      Button("Next month", systemImage: "chevron.right") { shiftMonth(1) }.labelStyle(.iconOnly)
    }.foregroundStyle(Color.lociCoral)
  }

  private var weekdayHeader: some View {
    let symbols = weekdaySymbols
    return HStack(spacing: 0) {
      ForEach(symbols.indices, id: \.self) { index in
        Text(symbols[index]).font(.caption2.weight(.semibold)).foregroundStyle(Color.lociInk.opacity(0.5))
          .frame(maxWidth: .infinity)
      }
    }
  }

  private var monthGrid: some View {
    // Grouped once per redraw, not filtered again for every cell.
    let byDay: [String: [CalendarTripBlock]] = Dictionary(grouping: blocks) { $0.dateKey }
    return LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
      ForEach(cells, id: \.dateKey) { cell in
        dayCell(cell, blocks: byDay[cell.dateKey] ?? [])
      }
    }
  }

  private func dayCell(_ cell: MonthCell, blocks dayBlocks: [CalendarTripBlock]) -> some View {
    let isSelected = selectedKey == cell.dateKey
    let fill: Color = isSelected ? Color.lociCoral.opacity(0.15) : Color.lociCard
    let stroke: Color = isSelected ? Color.lociCoral : Color.lociBorder.opacity(0.5)
    let dayColor: Color = cell.inMonth ? Color.lociInk : Color.lociInk.opacity(0.35)
    let traits: AccessibilityTraits = isSelected ? .isSelected : []
    return Button {
      selectedKey = cell.dateKey
      refreshApple()
    } label: {
      VStack(alignment: .leading, spacing: 2) {
        Text("\(cell.day)").font(.caption.weight(.medium)).foregroundStyle(dayColor)
        ForEach(Array(dayBlocks.prefix(2))) { block in
          Text(block.title).font(.caption2.weight(.semibold)).foregroundStyle(.white).lineLimit(1)
            .padding(.horizontal, 3).padding(.vertical, 1)
            .background(Color.lociCoralFill, in: RoundedRectangle(cornerRadius: 3))
        }
      }
      .frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading).padding(4)
      .background(fill, in: RoundedRectangle(cornerRadius: 8))
      .overlay { RoundedRectangle(cornerRadius: 8).stroke(stroke, lineWidth: LociTheme.borderWidth) }
    }
    .accessibilityLabel(accessibleDate(cell.dateKey))
    .accessibilityValue(dayBlocks.map(\.title).joined(separator: ", "))
    .accessibilityAddTraits(traits)
  }

  private func accessibleDate(_ key: String) -> String {
    guard let date = CalendarMath.parseDateKey(key) else { return key }
    return date.formatted(.dateTime.weekday(.wide).day().month(.wide))
  }

  private var agenda: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(agendaTitle).font(.headline).foregroundStyle(Color.lociInk)
      let dayBlocks = blocks.filter { $0.dateKey == selectedKey }
      if dayBlocks.isEmpty && appleTitles.isEmpty {
        Text("No Loci trips on this day.").font(.subheadline).foregroundStyle(Color.lociInk.opacity(0.6))
      } else {
        ForEach(dayBlocks) { block in
          VStack(alignment: .leading, spacing: 4) {
            Text(block.title).font(.subheadline.weight(.semibold)).foregroundStyle(Color.lociInk)
            Text("\(block.cityName) · Day \(block.dayNumber)").font(.caption).foregroundStyle(Color.lociInk.opacity(0.6))
            if AppleCalendar.shared.isAuthorized, let trip = trips.first(where: { $0.id == block.tripId }) {
              Button("Add to Apple Calendar") { addToAppleCalendar(trip) }.font(.caption).foregroundStyle(Color.lociCoral)
            }
          }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.lociCard, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius))
        }
        ForEach(appleTitles, id: \.self) { title in
          Text(title).font(.subheadline).foregroundStyle(Color.lociInk.opacity(0.8)).padding(12).frame(
            maxWidth: .infinity,
            alignment: .leading
          ).background(Color.lociSage.opacity(0.2), in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius))
        }
      }
    }
  }

  private var unscheduledSection: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text("Unscheduled").font(.headline).foregroundStyle(Color.lociInk)
      Text("Trips without calendar dates yet.").font(.caption).foregroundStyle(Color.lociInk.opacity(0.6))
      if unscheduled.isEmpty {
        Text("Everything has a date.").font(.subheadline).foregroundStyle(Color.lociInk.opacity(0.6))
      } else {
        ForEach(unscheduled, id: \.id) { trip in
          HStack {
            VStack(alignment: .leading, spacing: 4) {
              Text(trip.title.isEmpty ? (trip.cityName.isEmpty ? "Untitled trip" : trip.cityName) : trip.title).font(
                .subheadline.weight(.semibold)
              )
              Text("^[\(trip.days.count) day](inflect: true)").font(.caption).foregroundStyle(Color.lociInk.opacity(0.6))
            }
            Spacer()
            Button("Pin dates") {
              pinning = trip
              pinStart = CalendarMath.parseDateKey(selectedKey) ?? Date()
            }.foregroundStyle(Color.lociCoral)
          }.padding(12).background(Color.lociCard, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius))
        }
      }
    }
  }

  private func pinSheet(_ trip: Loci_Trip_TripDraft) -> some View {
    NavigationStack {
      VStack(alignment: .leading, spacing: 16) {
        Text("Day 1 of this trip will start on the date you pick. Later days follow in order.").font(.subheadline)
          .foregroundStyle(Color.lociInk.opacity(0.7))
        DatePicker("Starts", selection: $pinStart, displayedComponents: .date)
        Spacer()
      }.padding().navigationTitle("Pin dates").toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { pinning = nil } }
        ToolbarItem(placement: .confirmationAction) {
          if isPinSaving {
            ProgressView()
          } else {
            Button("Save") { savePinned(trip) }
          }
        }
      }
      // Presented from the sheet: the calendar beneath can't show an alert while it's up.
      .errorAlert($pinError)
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

  /// Writing again replaces the trip's earlier events (`AppleCalendar.writeTrip`),
  /// so a second tap doesn't double them.
  private func addToAppleCalendar(_ trip: Loci_Trip_TripDraft) {
    do {
      try AppleCalendar.shared.writeTrip(trip)
      refreshApple()
    } catch {
      errorMessage = error.userMessage
    }
  }

  private func loadTrips() {
    isLoading = true
    errorMessage = nil
    Task {
      let headers: Connect.Headers = [:]
      let response = await client.listTrips(request: Loci_Trip_ListTripsRequest(), headers: headers)
      isLoading = false
      if let error = response.error {
        errorMessage = error.message ?? "Couldn't load your trips. Try again."
      } else if let message = response.message {
        trips = message.trips
      }
    }
  }

  /// A refused save keeps the sheet up with the reason, rather than closing as
  /// if the dates were pinned.
  private func savePinned(_ trip: Loci_Trip_TripDraft) {
    let req = CalendarPin.saveRequest(trip, start: pinStart, calendar: calendar)
    isPinSaving = true
    Task {
      let headers: Connect.Headers = [:]
      let response = await client.saveTrip(request: req, headers: headers)
      isPinSaving = false
      if let error = response.error {
        pinError = error.message ?? "Couldn't pin those dates. Try again."
        return
      }
      pinning = nil
      loadTrips()
    }
  }
}

extension Loci_Trip_TripDraft: @retroactive Identifiable {}

/// The SaveTrip that pins a trip's days to dates from `start`. SaveTrip
/// replaces the whole trip, so everything else goes back exactly as read,
/// legs included with their ids: the server keeps a leg's id only when the
/// client sends it back (or the hop is unchanged), and the globe keys its arcs
/// on that id.
nonisolated enum CalendarPin {
  static func saveRequest(_ trip: Loci_Trip_TripDraft, start: Date, calendar: Calendar = .current) -> Loci_Trip_SaveTripRequest {
    var updated = trip
    let origin = calendar.startOfDay(for: start)
    updated.days = trip.days.map { day in
      var copy = day
      let shifted = calendar.date(byAdding: .day, value: Int(day.dayNumber - 1), to: origin) ?? origin
      // Midnight UTC of the chosen day, the shape web writes and DayTimeline reads.
      let pinned = DayTimeline.utcMidnight(ofDayContaining: shifted, calendar: calendar) ?? shifted
      var ts = SwiftProtobuf.Google_Protobuf_Timestamp()
      ts.seconds = Int64(pinned.timeIntervalSince1970)
      copy.date = ts
      return copy
    }
    var request = Loci_Trip_SaveTripRequest()
    request.trip = updated
    request.baseVersion = trip.version
    return request
  }
}

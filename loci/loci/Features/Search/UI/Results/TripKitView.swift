import CoreLocation
import LociConnectProto
import MapKit
import SwiftUI

/// Web's `TripKit`: route in Apple Maps or Google Maps, one calendar event per
/// stop, both for the days between From and To, and a PDF from ExportService. Free plans
/// get Day 1 only, as on web; a one-day list is therefore free in full.
struct TripKitView: View {
  let groups: [DayGroup]
  let cityName: String
  let title: String
  let summary: String
  let side: ResultsSideData
  /// Lets a later export of a day replace this one's events.
  var sessionID: String?
  /// The trip this itinerary was saved as: a pinned one prefills Trip starts.
  var tripID: String?

  @Environment(\.openURL) private var openURL
  @State private var startDate = CalendarSchedule.defaultStartDate()
  /// nil until the range is touched: every day, however many there turn out to be.
  @State private var pickedRange: TripDateRange?
  @State private var calendarStatus: String?
  @State private var pdfURL: URL?
  @State private var makingPDF = false
  @State private var error: String?

  private var unlocked: [DayGroup] { ProGate.unlocked(groups, isPro: side.isPro) }
  private var range: TripDateRange { (pickedRange ?? .all(dayCount: unlocked.count)).fitted(dayCount: unlocked.count) }
  /// The days the range covers: what Maps and Calendar export.
  private var selected: [DayGroup] { range.slice(unlocked) }
  /// With plan gating off nothing here depends on the plan, so the view
  /// neither waits for it nor mentions it.
  private var gated: Bool { !ProGate.entitled(isPro: side.isPro) && groups.count > 1 }
  private var checking: Bool { PlanGating.enabled && !side.planChecked }

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Label("Trip Kit", systemImage: "backpack").lociCoordStyle(10)
        Spacer()
        if checking { Text("Checking your plan…").lociCoordStyle(9) }
      }
      dates
      routes
      calendar
      pdf
      if gated {
        VStack(alignment: .leading, spacing: 2) {
          Text("Day 1 is included on the free plan.").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
          Link("Unlock the full Trip Kit with Pro", destination: ProGate.pricingURL).font(.lociCaption(12))
        }
      } else if PlanGating.enabled, !side.isPro, side.planChecked, groups.count == 1 {
        Text("Everything here is on the free plan.").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
      }
    }
    .lociCard()
    .disabled(checking)
    .errorAlert($error)
    .task { await side.loadPlan() }
    .task(id: tripID) { await prefillPinnedStart() }
    .onChange(of: startDate) { calendarStatus = nil }
    .onChange(of: range) { calendarStatus = nil }
  }

  // MARK: - Dates

  /// Trip starts dates Day 1; From and To choose the days Maps and Calendar
  /// export. A one-day plan has nothing to choose.
  private var dates: some View {
    VStack(alignment: .leading, spacing: 6) {
      DatePicker("Trip starts", selection: $startDate, displayedComponents: .date)
      if unlocked.count > 1 {
        DatePicker("From · Day \(dayNumber(at: range.from))", selection: fromDate, in: firstDay...lastDay, displayedComponents: .date)
        DatePicker("To · Day \(dayNumber(at: range.to))", selection: toDate, in: date(at: range.from)...lastDay, displayedComponents: .date)
      }
    }
    .font(.lociCaption(13)).tint(.lociForest)
  }

  private var firstDay: Date { date(at: 0) }
  private var lastDay: Date { date(at: max(unlocked.count - 1, 0)) }
  private func date(at index: Int) -> Date { TripDateRange.date(ofDay: index, start: startDate) }
  private func dayNumber(at index: Int) -> Int { unlocked.indices.contains(index) ? unlocked[index].number : index + 1 }

  private func dayLabel(_ group: DayGroup) -> String {
    let index = unlocked.firstIndex { $0.number == group.number } ?? 0
    return "Day \(group.number) · \(date(at: index).formatted(.dateTime.weekday(.abbreviated).day().month(.abbreviated)))"
  }

  private var fromDate: Binding<Date> {
    Binding(get: { date(at: range.from) }) { picked in
      let index = TripDateRange.dayIndex(of: picked, start: startDate, dayCount: unlocked.count)
      pickedRange = range.moving(from: index, dayCount: unlocked.count)
    }
  }

  private var toDate: Binding<Date> {
    Binding(get: { date(at: range.to) }) { picked in
      let index = TripDateRange.dayIndex(of: picked, start: startDate, dayCount: unlocked.count)
      pickedRange = range.moving(to: index, dayCount: unlocked.count)
    }
  }

  /// A trip already pinned to dates starts there, unless Trip starts has been
  /// changed by hand in the meantime.
  private func prefillPinnedStart() async {
    guard let tripID, !ResultsSideData.isOffline else { return }
    let untouched = startDate
    guard let trip = try? await TripAPI.trip(id: tripID), let pinned = CalendarSchedule.pinnedStart(of: trip) else { return }
    if startDate == untouched { startDate = pinned }
  }

  // MARK: - Routes

  @ViewBuilder private var routes: some View {
    HStack(spacing: 8) {
      if selected.count > 1 {
        Menu {
          ForEach(selected, id: \.number) { group in
            Button(dayLabel(group)) { openAppleMaps(group.stops) }
          }
        } label: {
          Label("Apple Maps", systemImage: "map").fixedSize()
        }
      } else if let only = selected.first {
        Button { openAppleMaps(only.stops) } label: { Label("Apple Maps", systemImage: "map").fixedSize() }
      }
      if selected.count > 1 {
        Menu {
          ForEach(selected, id: \.number) { group in
            if let url = GoogleMapsRoute.url(for: group.stops, cityName: cityName) {
              Button(dayLabel(group)) { openURL(url) }
            }
          }
        } label: {
          Label("Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond").fixedSize()
        }
      } else if let only = selected.first, let url = GoogleMapsRoute.url(for: only.stops, cityName: cityName) {
        Button { openURL(url) } label: { Label("Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond").fixedSize() }
      }
    }
    .buttonStyle(MusePillButtonStyle())
  }

  // MARK: - Calendar

  private var calendar: some View {
    VStack(alignment: .leading, spacing: 6) {
      Button { Task { await addToCalendar() } } label: {
        Label(calendarStatus ?? "Add to Calendar", systemImage: "calendar.badge.plus").fixedSize()
      }
      .buttonStyle(MusePillButtonStyle())
      .disabled(calendarStatus != nil)
      Text("^[\(selected.reduce(0) { $0 + $1.stops.count }) event](inflect: true), 09:00 start").lociCoordStyle(9)
    }
  }

  private func addToCalendar() async {
    do {
      let store = AppleCalendar.shared
      if !store.isAuthorized, try await !store.requestAccess() {
        throw APIError.custom("Allow calendar access in Settings to add the trip.")
      }
      let events = CalendarSchedule.events(groups: selected, startDate: date(at: range.from), cityName: cityName, summary: summary)
      let count = try store.writeStops(events, sessionID: sessionID)
      calendarStatus = String(AttributedString(localized: "Added ^[\(count) event](inflect: true)").characters)
    } catch { self.error = error.userMessage }
  }

  // MARK: - PDF

  @ViewBuilder private var pdf: some View {
    HStack(spacing: 8) {
      if let pdfURL {
        ShareLink(item: pdfURL) { Label("Share PDF", systemImage: "doc.richtext") }
      } else {
        Button(makingPDF ? "Building PDF…" : "PDF", systemImage: "doc.richtext") { Task { await makePDF() } }.disabled(makingPDF)
      }
    }
    .buttonStyle(MusePillButtonStyle())
  }

  private func makePDF() async {
    makingPDF = true
    defer { makingPDF = false }
    do {
      pdfURL = try await ResultsAPI.pdf(title: title, summary: summary, cityName: cityName, groups: unlocked)
    } catch { self.error = error.userMessage }
  }

  // MARK: - Apple Maps

  private func openAppleMaps(_ stops: [Loci_Poi_POIDetailedInfo]) {
    let items = stops.filter(GoogleMapsRoute.hasCoordinate).map { stop -> MKMapItem in
      let location = CLLocation(latitude: stop.latitude, longitude: stop.longitude)
      let item = MKMapItem(location: location, address: stop.address.isEmpty ? nil : MKAddress(fullAddress: stop.address, shortAddress: nil))
      item.name = stop.name
      return item
    }
    guard !items.isEmpty else {
      error = "These stops have no coordinates yet."
      return
    }
    MKMapItem.openMaps(with: items, launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeWalking])
  }
}

nonisolated extension ProGate {
  static let pricingURL = URL(string: "https://lociai.fyi/pricing") ?? URL(fileURLWithPath: "/")
}

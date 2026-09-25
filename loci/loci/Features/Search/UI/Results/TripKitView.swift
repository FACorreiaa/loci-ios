import CoreLocation
import LociConnectProto
import MapKit
import SwiftUI

/// Web's `TripKit`: route in Apple Maps or Google Maps, one calendar event per
/// stop from a chosen start date, and a PDF from ExportService. Free plans
/// get Day 1 only, as on web; a one-day list is therefore free in full.
struct TripKitView: View {
  let groups: [DayGroup]
  let cityName: String
  let title: String
  let summary: String
  let side: ResultsSideData

  @Environment(\.openURL) private var openURL
  @State private var startDate = CalendarSchedule.defaultStartDate()
  @State private var calendarStatus: String?
  @State private var pdfURL: URL?
  @State private var makingPDF = false
  @State private var error: String?

  private var unlocked: [DayGroup] { ProGate.unlocked(groups, isPro: side.isPro) }
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
  }

  // MARK: - Routes

  @ViewBuilder private var routes: some View {
    HStack(spacing: 8) {
      if unlocked.count > 1 {
        Menu {
          ForEach(unlocked, id: \.number) { group in
            Button("Day \(group.number)") { openAppleMaps(group.stops) }
          }
        } label: {
          Label("Apple Maps", systemImage: "map").fixedSize()
        }
      } else if let only = unlocked.first {
        Button { openAppleMaps(only.stops) } label: { Label("Apple Maps", systemImage: "map").fixedSize() }
      }
      if unlocked.count > 1 {
        Menu {
          ForEach(unlocked, id: \.number) { group in
            if let url = GoogleMapsRoute.url(for: group.stops, cityName: cityName) {
              Button("Day \(group.number)") { openURL(url) }
            }
          }
        } label: {
          Label("Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond").fixedSize()
        }
      } else if let only = unlocked.first, let url = GoogleMapsRoute.url(for: only.stops, cityName: cityName) {
        Button { openURL(url) } label: { Label("Google Maps", systemImage: "arrow.triangle.turn.up.right.diamond").fixedSize() }
      }
    }
    .buttonStyle(MusePillButtonStyle())
  }

  // MARK: - Calendar

  private var calendar: some View {
    VStack(alignment: .leading, spacing: 6) {
      DatePicker("Trip starts", selection: $startDate, in: Date()..., displayedComponents: .date)
        .font(.lociCaption(13)).tint(.lociForest)
      Button { Task { await addToCalendar() } } label: {
        Label(calendarStatus ?? "Add to Calendar", systemImage: "calendar.badge.plus").fixedSize()
      }
      .buttonStyle(MusePillButtonStyle())
      .disabled(calendarStatus != nil)
      Text("\(unlocked.reduce(0) { $0 + $1.stops.count }) events, 09:00 start").lociCoordStyle(9)
    }
  }

  private func addToCalendar() async {
    do {
      let store = AppleCalendar.shared
      if !store.isAuthorized, try await !store.requestAccess() {
        throw APIError.custom("Allow calendar access in Settings to add the trip.")
      }
      let events = CalendarSchedule.events(groups: unlocked, startDate: startDate, cityName: cityName, summary: summary)
      let count = try store.writeStops(events)
      calendarStatus = "Added \(count) events"
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

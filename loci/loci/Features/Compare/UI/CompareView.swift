import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Weekend compare (web: /compare). CompareService.CompareWeekend{originCity,
/// candidateCityNames (2+), startDate, endDate}; "Save as trip" builds the same
/// TripDraft web builds and calls TripService.SaveTrip{trip, baseVersion: 0}.
struct CompareView: View {
  /// web: lib/compare-presets.ts COMPARE_PRESETS
  static let presets: [(origin: String, candidates: [String])] = [
    ("Porto", ["Évora", "Beja"]), ("Lisbon", ["Sintra", "Óbidos"]), ("Madrid", ["Toledo", "Segovia"]),
  ]

  @State private var origin = ""
  @State private var candidates: [String] = []
  @State private var newCandidate = ""
  @State private var window = CompareView.defaultWeekend()
  @State private var result: Loci_Compare_V1_CompareWeekendResponse?
  @State private var isComparing = false
  @State private var savedTrip: Loci_Trip_TripDraft?
  @State private var error: String?

  init() {}

  #if DEBUG
    /// A finished compare, for `-designPreview compare`.
    init(preview: Loci_Compare_V1_CompareWeekendResponse, origin: String, candidates: [String]) {
      _origin = State(initialValue: origin)
      _candidates = State(initialValue: candidates)
      _result = State(initialValue: preview)
    }
  #endif

  private var canCompare: Bool {
    !origin.trimmingCharacters(in: .whitespaces).isEmpty && candidates.count >= 2 && window.end > window.start && !isComparing
  }

  var body: some View {
    Form {
      Section {
        TextField("From (e.g. Porto)", text: $origin).textContentType(.addressCity)
        DatePicker("Leave", selection: $window.start, displayedComponents: .date)
        DatePicker("Back", selection: $window.end, in: window.start..., displayedComponents: .date)
      } header: {
        Text("Weekend")
      }

      Section {
        ForEach(candidates, id: \.self) { city in
          Text(city).swipeActions { Button("Remove", role: .destructive) { candidates.removeAll { $0 == city } } }
        }
        HStack {
          TextField("Add a city", text: $newCandidate).textContentType(.addressCity).onSubmit(addCandidate)
          Button("Add", action: addCandidate).disabled(newCandidate.trimmingCharacters(in: .whitespaces).isEmpty)
        }
      } header: {
        Text("Candidates (2 or more)")
      } footer: {
        Text("Free plans compare two cities. Pro compares up to eight and plans a multi-city route.")
      }

      if result == nil {
        Section("One-tap presets") {
          ForEach(Self.presets, id: \.origin) { preset in
            Button("\(preset.origin) → \(preset.candidates.joined(separator: " or "))") {
              origin = preset.origin
              candidates = preset.candidates
              Task { await compare() }
            }
          }
        }
      }

      Section {
        Button {
          Task { await compare() }
        } label: {
          HStack {
            Text("Compare")
            if isComparing { Spacer(); ProgressView() }
          }
        }.disabled(!canCompare)
      }

      if let result { results(result) }
    }
    .settingsStyle("Compare")
    .navigationDestination(item: $savedTrip) { TripEditorView(tripID: $0.id) }
    .errorAlert($error)
  }

  // MARK: - Results

  @ViewBuilder private func results(_ result: Loci_Compare_V1_CompareWeekendResponse) -> some View {
    if !result.recommendationReason.isEmpty {
      Section("Loci's pick") {
        Text(recommendationTitle(result)).font(.lociHeadline())
        Text(result.recommendationReason).font(.lociBody())
      }
    }
    ForEach(Array(result.columns.enumerated()), id: \.offset) { _, column in
      Section {
        LabeledContent("Distance", value: "\(Int(column.distanceKm)) km · \(column.travelMins / 60)h \(column.travelMins % 60)m")
        if column.hasGoScore { LabeledContent("GoScore", value: "\(column.goScore.score) · \(column.goScore.verdict)") }
        if !column.weather.isEmpty {
          LabeledContent(column.weatherIsEstimated ? "Weather (typical)" : "Weather") {
            Text(column.weather.map { "\(Int($0.highC))°" }.joined(separator: " / "))
          }
        }
        ForEach(column.pros, id: \.self) { Label($0, systemImage: "plus.circle").foregroundStyle(Color.lociForest) }
        ForEach(column.cons, id: \.self) { Label($0, systemImage: "minus.circle").foregroundStyle(Color.lociDestructive) }
        if !column.staySnippet.isEmpty { Text(column.staySnippet).font(.lociCaption()) }
        if !column.eatSnippet.isEmpty { Text(column.eatSnippet).font(.lociCaption()) }
        ForEach(column.topPois.prefix(3), id: \.stableID) { Text("• \($0.name)").font(.lociCaption()) }
        ForEach(column.transportOptions, id: \.url) { option in
          if let url = URL(string: option.url) { Link("\(option.mode.capitalized): \(option.summary)", destination: url) }
        }
        ForEach(column.bookingOptions, id: \.url) { option in
          if let url = URL(string: option.url) { Link(option.label, destination: url) }
        }
        Button("Save \(column.cityName) as a trip") { Task { await save(column: column, dual: false, columns: result.columns) } }
      } header: {
        Text("\(column.cityName), \(column.country)").font(.lociTitle(18)).textCase(nil)
      }
    }
    if result.hasDualCityOption, result.dualCityOption.feasible, result.columns.count >= 2 {
      Section("Both in one weekend") {
        Text(result.dualCityOption.outline).font(.lociBody())
        if result.dualCityOption.proOnly {
          Text("Pro plans both cities in one weekend.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        } else {
          Button("Save both as one trip") { Task { await save(column: result.columns[0], dual: true, columns: result.columns) } }
        }
      }
    }
    if result.hasMultiCityPlan, result.multiCityPlan.feasible {
      Section("Multi-city route") {
        Text(result.multiCityPlan.outline).font(.lociBody())
        ForEach(result.multiCityPlan.warnings, id: \.self) { Text($0).font(.lociCaption()).foregroundStyle(Color.lociMutedInk) }
        if result.multiCityPlan.proOnly {
          Text("Pro plans multi-city routes.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
        } else {
          Button("Save the route as a trip") { Task { await save(plan: result.multiCityPlan) } }
        }
      }
    }
  }

  private func recommendationTitle(_ result: Loci_Compare_V1_CompareWeekendResponse) -> String {
    let names = result.columns.map(\.cityName)
    switch result.recommendation {
    case .first: return names.first ?? "First"
    case .second: return names.count > 1 ? names[1] : "Second"
    case .both: return names.prefix(2).joined(separator: " + ")
    default: return "No clear winner"
    }
  }

  // MARK: - Actions

  private func addCandidate() {
    let city = newCandidate.trimmingCharacters(in: .whitespaces)
    guard !city.isEmpty, !candidates.contains(city), city.caseInsensitiveCompare(origin) != .orderedSame else { return }
    candidates.append(city)
    newCandidate = ""
  }

  private func compare() async {
    isComparing = true
    defer { isComparing = false }
    var request = Loci_Compare_V1_CompareWeekendRequest()
    request.originCity = origin.trimmingCharacters(in: .whitespaces)
    request.candidateCityNames = candidates
    request.startDate = Google_Protobuf_Timestamp(date: window.start)
    request.endDate = Google_Protobuf_Timestamp(date: window.end)
    do {
      result = try await rpc("Could not compare those cities.", request) {
        await Loci_Compare_V1_CompareServiceClient(client: ConnectTransport.shared.protocolClient).compareWeekend(request: $0, headers: [:])
      }
    } catch { self.error = error.userMessage }
  }

  /// web: routes/compare/index.tsx save handlers (CompareTripBuilder).
  private func save(column: Loci_Compare_V1_CityCompareColumn, dual: Bool, columns: [Loci_Compare_V1_CityCompareColumn]) async {
    let userID = AuthSessionManager.shared.currentUserID
    await saveTrip(CompareTripBuilder.weekend(column: column, dual: dual, columns: columns, userID: userID))
  }

  private func save(plan: Loci_Compare_V1_MultiCityPlan) async {
    guard let trip = CompareTripBuilder.multiCity(plan: plan, userID: AuthSessionManager.shared.currentUserID) else { return }
    await saveTrip(trip)
  }

  private func saveTrip(_ trip: Loci_Trip_TripDraft) async {
    var request = Loci_Trip_SaveTripRequest()
    request.trip = trip
    request.baseVersion = 0
    do {
      savedTrip = try await rpc("Could not save the trip.", request) {
        await Loci_Trip_TripServiceClient(client: ConnectTransport.shared.protocolClient).saveTrip(request: $0, headers: [:])
      }
    } catch { self.error = error.userMessage }
  }

  /// web: lib/compare-defaults.ts defaultWeekend — the coming Saturday to Sunday, always in the future.
  static func defaultWeekend(now: Date = Date(), calendar: Calendar = .current) -> DateWindow {
    let weekday = calendar.component(.weekday, from: now)  // 1 = Sunday … 7 = Saturday
    let jsDay = weekday - 1
    var daysUntilSaturday = (6 - jsDay + 7) % 7
    if daysUntilSaturday == 0 { daysUntilSaturday = 7 }
    let start = calendar.startOfDay(for: calendar.date(byAdding: .day, value: daysUntilSaturday, to: now) ?? now)
    let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
    return DateWindow(start: start, end: end)
  }
}

struct DateWindow: Equatable {
  var start: Date
  var end: Date
}

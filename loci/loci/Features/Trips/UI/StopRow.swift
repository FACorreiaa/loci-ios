import LociConnectProto
import SwiftUI

struct StopRow: View {
  let stop: Loci_Trip_TripStop
  let color: Color
  let isEditing: Bool
  let onDuration: (Int) -> Void

  @ScaledMetric(relativeTo: .caption) private var numberWidth = 20
  /// The stepper's value, shown at once; the server's copy catches up after
  /// the debounced edit lands.
  @State private var duration = 60
  @State private var pending: Task<Void, Never>?

  private var savedDuration: Int { stop.hasDurationMinutes ? Int(stop.durationMinutes) : 60 }

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      Text("\(stop.orderIndex + 1)").lociCoordStyle(11).frame(minWidth: numberWidth)
      VStack(alignment: .leading, spacing: 3) {
        Text(stop.name).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
        if !stop.notes.isEmpty { Text(stop.notes).font(.lociCaption()).foregroundStyle(Color.lociMutedInk).lineLimit(2) }
        if isEditing {
          Stepper("\(duration) min", value: $duration, in: 15...480, step: 15).font(.lociCaption())
        } else if stop.hasDurationMinutes {
          Text("\(stop.durationMinutes) min").lociCoordStyle(10)
        }
      }
    }
    .listRowBackground(Color.lociCard)
    .onAppear { duration = savedDuration }
    .onChange(of: savedDuration) { _, new in duration = new }
    // Debounced like the day window's TimeRow: a run of taps sends one edit,
    // not one per step racing the last for the trip's `version`.
    .onChange(of: duration) { _, new in
      pending?.cancel()
      guard new != savedDuration else { return }
      pending = Task {
        try? await Task.sleep(for: .milliseconds(700))
        guard !Task.isCancelled else { return }
        onDuration(new)
      }
    }
  }
}

/// Search canonical places in the trip's city (web: PlacePicker →
/// PoiService.SearchPOI{query, cityName, searchType: "semantic"}).
struct PlacePicker: View {
  let cityName: String
  let onSelect: (Loci_Poi_POIDetailedInfo) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var query = ""
  @State private var results: [Loci_Poi_POIDetailedInfo] = []
  @State private var isSearching = false
  @State private var error: String?

  var body: some View {
    NavigationStack {
      List {
        ForEach(results, id: \.stableID) { poi in
          Button {
            onSelect(poi)
            dismiss()
          } label: {
            VStack(alignment: .leading, spacing: 2) {
              Text(poi.name).foregroundStyle(Color.lociInk)
              if !poi.category.isEmpty { Text(poi.category).lociCoordStyle(10) }
            }
          }
        }
      }
      .overlay { if isSearching { ProgressView() } }
      .searchable(text: $query, prompt: cityName.isEmpty ? "Search places" : "Search places in \(cityName)")
      .onSubmit(of: .search) { Task { await search() } }
      .navigationTitle("Add a place").navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
      }
      .errorAlert($error)
    }
  }

  private func search() async {
    let text = query.trimmingCharacters(in: .whitespaces)
    guard !text.isEmpty else { return }
    isSearching = true
    defer { isSearching = false }
    var request = Loci_Poi_SearchPOIRequest()
    request.query = text
    request.cityName = cityName
    request.searchType = "semantic"
    do {
      results = Array(
        try await rpc("Search failed.", request) {
          await Loci_Poi_PoiserviceClient(client: ConnectTransport.shared.protocolClient).searchPoi(request: $0, headers: [:])
        }.pois.prefix(6)
      )
    } catch { self.error = error.userMessage }
  }
}

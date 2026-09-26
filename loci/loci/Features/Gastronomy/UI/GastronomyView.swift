import LociConnectProto
import SwiftUI

/// The gastronomy lookup behind the screen. A failure with an answer already
/// on screen for the same city is an alert and the answer stays.
@MainActor @Observable final class GastronomyStore {
  enum Phase: Equatable {
    case idle, loading, loaded
    case failed(String)
  }

  private(set) var gastronomy: Loci_Gastronomy_CityGastronomy?
  private(set) var phase = Phase.idle
  private(set) var city = ""
  var error: String?

  private let service: GastronomyService

  init(service: GastronomyService = ConnectGastronomyService()) { self.service = service }

  func load(city name: String) async {
    let requested = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !requested.isEmpty else { return }
    let isRefresh = requested.caseInsensitiveCompare(city) == .orderedSame && gastronomy != nil
    city = requested
    if !isRefresh {
      gastronomy = nil
      phase = .loading
    }
    do {
      let result = try await service.city(named: requested)
      // A newer city owns the screen now.
      guard requested == city else { return }
      gastronomy = result.dishes.isEmpty ? nil : result
      phase = .loaded
    } catch {
      guard !(error is CancellationError), (error as? APIError) != .cancelled, requested == city else { return }
      if isRefresh { self.error = error.userMessage } else { phase = .failed(error.userMessage) }
    }
  }
}

/// Typical gastronomy (web: /gastronomy): pick a city, see its signature
/// dishes and the well-known places to eat them. Entered from Discover.
struct GastronomyView: View {
  static let symbol = "fork.knife"
  static let suggestedCities = ["Lisbon", "Porto", "Madeira", "Naples", "Mexico City", "Tokyo"]

  @State var store: GastronomyStore
  @State private var query: String
  @FocusState private var fieldFocused: Bool

  init(store: GastronomyStore = GastronomyStore(), city: String = "") {
    _store = State(initialValue: store)
    _query = State(initialValue: city)
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        header
        searchField
        content
      }
      .padding(LociTheme.defaultPadding)
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .navigationTitle("Local food")
    .navigationBarTitleDisplayMode(.inline)
    .refreshable { await store.load(city: store.city) }
    .task { if !query.isEmpty, store.phase == .idle { await store.load(city: query) } }
    .errorAlert($store.error)
    .onAppear { Analytics.screen("gastronomy") }
  }

  private var header: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text("Typical gastronomy").lociCoordStyle(10)
      Text("What do people eat here?").font(.lociDisplay(28)).foregroundStyle(Color.lociInk)
      Text("Pick a city to see its signature dishes and the well-known places to try them.")
        .font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
    }
  }

  private var searchField: some View {
    HStack(spacing: 8) {
      Image(systemName: "magnifyingglass").foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
      TextField("Search a city", text: $query)
        .font(.lociBody(16))
        .textInputAutocapitalization(.words)
        .autocorrectionDisabled()
        .submitLabel(.search)
        .focused($fieldFocused)
        .onSubmit { search(query) }
    }
    .lociCard(padding: 12)
  }

  @ViewBuilder private var content: some View {
    switch store.phase {
    case .idle:
      VStack(alignment: .leading, spacing: 10) {
        Text("Or start with one of these").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        ScrollView(.horizontal, showsIndicators: false) {
          HStack(spacing: 8) {
            ForEach(Self.suggestedCities, id: \.self) { city in
              Button(city) { search(city) }.buttonStyle(MusePillButtonStyle())
            }
          }
        }
        .scrollClipDisabled()
      }
    case .loading:
      SkeletonCards().accessibilityElement(children: .ignore).accessibilityLabel("Loading dishes")
    case .failed(let message):
      ContentUnavailableView {
        Label("Could not load this city's food", systemImage: "exclamationmark.triangle")
      } description: {
        Text(message)
      } actions: {
        Button("Try again") { Task { await store.load(city: store.city) } }.lociProminentButton()
      }
    case .loaded:
      if let gastronomy = store.gastronomy {
        GastronomySection(gastronomy: gastronomy)
      } else {
        ContentUnavailableView(
          "Nothing found for \(store.city)",
          systemImage: GastronomyView.symbol,
          description: Text("Check the spelling, or try a nearby city.")
        )
      }
    }
  }

  private func search(_ city: String) {
    query = city
    fieldFocused = false
    Task { await store.load(city: city) }
  }
}

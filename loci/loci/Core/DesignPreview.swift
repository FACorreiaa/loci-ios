import LociConnectProto
import SwiftUI

/// Screens shown on their own when the app is launched with
/// `-designPreview <name>`, so a component can be looked at on a simulator
/// without signing in. Debug builds only; never set in normal use.
enum DesignPreview: String {
  case inSeason
  /// The Muse chat (SearchResultsView's pieces) with a finished answer.
  case museChat
  /// The Muse chat while tokens stream in ("is writing", ring turning).
  case museChatStreaming
  /// Stream open, nothing back yet: "is thinking".
  case museChatThinking
  /// The server named a stage: "is {stage}", cut at 32 characters.
  case museChatStage
  /// The stream let go and the server is still going.
  case museChatDetached
  /// The 1.2s after a search finishes.
  case museChatCelebrating
  /// The moment after a search fails.
  case museChatSnag
  /// The follow-up composer has the cursor.
  case museChatListening
  /// A pushed results page with the navigation bar hidden, for checking swipe-back.
  case museChatPush
  /// The same push with the bar showing: the control for the swipe-back check.
  case museChatPushBar
  /// A finished Rome itinerary: header, map hero, two days, "Show the rest", extras, Trip Kit.
  case results
  /// The same page scrolled to the days, and to the Trip Kit.
  case resultsDays
  case resultsKit
  /// A saved place pushed from Saved, opened on its snapshot: name-keyed, so
  /// there is nothing on the server to fill it in.
  case savedPlace

  static var requested: DesignPreview? {
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "-designPreview"), index + 1 < arguments.count else { return nil }
      return DesignPreview(rawValue: arguments[index + 1])
    #else
      return nil
    #endif
  }

  @ViewBuilder var body: some View {
    switch self {
    case .inSeason: InSeasonPreview()
    case .museChat: MuseChatPreview(state: .museSampleCompleted)
    case .museChatStreaming: MuseChatPreview(state: .museSampleStreaming)
    case .museChatThinking: MuseChatPreview(state: .museSampleThinking)
    case .museChatStage:
      MuseChatPreview(state: .museSampleThinking.with { $0.progressStage = "Checking opening hours and the tram timetable" })
    case .museChatDetached: MuseChatPreview(state: .museSampleStreaming.with { $0.status = .detached })
    case .museChatCelebrating: MuseChatPreview(state: .museSampleCompleted, flash: .celebrating(places: 2))
    case .museChatSnag:
      MuseChatPreview(state: .museSampleThinking.with { $0.status = .failed("The search failed. Try again in a moment.") }, flash: .snag)
    case .museChatListening: MuseChatPreview(state: .museSampleCompleted, isListening: true)
    case .museChatPush: MuseChatPushPreview()
    case .museChatPushBar: MuseChatPushPreview(hidesBar: false)
    case .results: MuseChatPreview(state: .resultsSample, caption: "Rome · 12 places")
    case .resultsDays: MuseChatPreview(state: .resultsSample, caption: "Rome · 12 places", scrollTo: ResultsPage.Anchor.days)
    case .resultsKit: MuseChatPreview(state: .resultsSample, caption: "Rome · 12 places", scrollTo: ResultsPage.Anchor.kit)
    case .savedPlace: NavigationStack { SavedPlaceDetailView(item: .savedPlaceSample) }
    }
  }
}

private struct InSeasonPreview: View {
  @State private var seed = ""
  @State private var text = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("Where to next?").font(.lociDisplay(30)).foregroundStyle(Color.lociInk)
        TextField("Ask Loci", text: $text)
          .font(.lociBody())
          .padding(.horizontal, 14).padding(.vertical, 10)
          .background(Color.lociCard, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).stroke(Color.lociBorder))
        InSeasonBand(seed: $seed)
      }
      .padding(LociTheme.defaultPadding)
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .onChange(of: seed) { _, value in
      guard !value.isEmpty else { return }
      text = value
      seed = ""
    }
  }
}

/// The Muse chat screen assembled from the real components with sample data,
/// so it can be screenshotted without signing in.
private struct MuseChatPreview: View {
  let state: SearchState
  /// Held for the screenshot instead of timing out.
  var flash: MuseActivity.Flash?
  var isListening = false
  var caption = "Lisbon"
  var scrollTo: String?

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        SearchTranscript(state: state, caption: caption)
          .padding(.horizontal, LociTheme.defaultPadding)
          .padding(.vertical, 12)
      }
      .task {
        guard let scrollTo else { return }
        try? await Task.sleep(for: .seconds(1))
        proxy.scrollTo(scrollTo, anchor: .top)
      }
    }
    .background(Color.museCanvas.ignoresSafeArea())
    .safeAreaInset(edge: .top, spacing: 0) {
      MuseChatHeader(activity: .resolve(state, flash: flash, isListening: isListening), leadingSystemImage: "chevron.left", leadingLabel: "Back")
    }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      PreviewComposer().padding(.horizontal, LociTheme.defaultPadding).padding(.vertical, 10).background(Color.museCanvas)
    }
  }
}

/// A root list pushing the Muse chat the way Ask Loci does (navigation bar
/// hidden on the pushed page), so swipe-back can be checked without signing in.
private struct MuseChatPushPreview: View {
  var hidesBar = true

  var body: some View {
    NavigationStack {
      List {
        NavigationLink("Open the chat", value: "chat")
      }
      .navigationTitle("Ask Loci")
      .navigationDestination(for: String.self) { _ in
        if hidesBar {
          MuseChatPreview(state: .museSampleCompleted)
            .toolbarVisibility(.hidden, for: .navigationBar)
            .interactivePopEnabled()
        } else {
          MuseChatPreview(state: .museSampleCompleted)
        }
      }
    }
  }
}

/// SearchComposer's Muse look without its session controller.
private struct PreviewComposer: View {
  @State private var text = ""
  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField("Ask a follow-up", text: $text)
        .font(.museBody)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.musePill, in: RoundedRectangle(cornerRadius: LociTheme.Muse.bubbleRadius, style: .continuous))
      Image(systemName: "arrow.up")
        .frame(width: LociTheme.minTapTarget, height: LociTheme.minTapTarget)
        .background(Color.lociForest, in: Circle()).foregroundStyle(Color.lociPaper)
    }
  }
}

extension SearchState {
  func with(_ change: (inout SearchState) -> Void) -> SearchState {
    var copy = self
    change(&copy)
    return copy
  }

  static var museSampleThinking: SearchState {
    museSampleStreaming.with { $0.text = "" }
  }

  static var museSampleStreaming: SearchState {
    var state = SearchState()
    state.cityName = "Lisbon"
    state.query = "3 days in Lisbon with kids, nothing too hilly"
    state.status = .streaming
    state.text =
      "Lisbon is steep, so I'm keeping each day to one neighbourhood: Belém by the river first,"
        + " then the flat Baixa grid, and a tram up to the castle for the one climb worth it."
    return state
  }

  static var museSampleCompleted: SearchState {
    var state = museSampleStreaming
    state.status = .completed
    var itinerary = Loci_Chat_AiCityResponse()
    itinerary.itineraryResponse.itineraryName = "Lisbon at a kid's pace"
    itinerary.itineraryResponse.overallDescription =
      "Three short days, one neighbourhood each, with a playground or a pastry stop every couple of hours."
    state.itinerary = itinerary
    var tower = Loci_Poi_POIDetailedInfo()
    tower.id = "sample-belem"
    tower.name = "Belém Tower"
    tower.category = "Landmark"
    tower.rating = 4.6
    tower.descriptionPoi = "A riverside fortress with a lawn for running around."
    var aquarium = Loci_Poi_POIDetailedInfo()
    aquarium.id = "sample-oceanario"
    aquarium.name = "Oceanário de Lisboa"
    aquarium.category = "Aquarium"
    aquarium.rating = 4.7
    aquarium.descriptionPoi = "One giant tank, sea otters, and step-free all the way round."
    state.itinerary?.itineraryResponse.pointsOfInterest = [tower, aquarium]
    return state
  }
}

extension SearchState {
  /// Three days in Rome with server-assigned days, one credited photo, an
  /// extra outside the plan, and city facts. Offline: image URLs are inert.
  static var resultsSample: SearchState {
    var state = SearchState()
    state.sessionId = "preview-rome"
    state.destination = .itinerary
    state.cityName = "Rome"
    state.query = "3 days in Rome, first time, lots of walking"
    state.status = .completed
    var city = Loci_City_GeneralCityData()
    city.city = "Rome"
    city.country = "Italy"
    city.description_p = "Layers of empire, church and café life stacked on seven hills; walk it and the city does the rest."
    city.population = "2.8M"
    city.area = "1,285 km²"
    city.language = "Italian"
    city.weather = "Mild, dry autumns"
    city.centerLatitude = 41.9028
    city.centerLongitude = 12.4964
    state.cityData = city
    var response = Loci_Chat_AiCityResponse()
    response.generalCityData = city
    response.itineraryResponse.itineraryName = "Rome on foot"
    response.itineraryResponse.overallDescription = "Ancient Rome first, then the Renaissance centre, then the Vatican and Trastevere."
    response.itineraryResponse.plannedDays = 3
    struct Seed {
      let name: String
      let category: String
      let lat: Double
      let lon: Double
      let day: Int
      let rating: Double
    }
    let plan = [
      Seed(name: "Colosseum", category: "Landmark", lat: 41.8902, lon: 12.4922, day: 1, rating: 4.8),
      Seed(name: "Roman Forum", category: "Historic site", lat: 41.8925, lon: 12.4853, day: 1, rating: 4.7),
      Seed(name: "Palatine Hill", category: "Park", lat: 41.8892, lon: 12.4875, day: 1, rating: 4.6),
      Seed(name: "Capitoline Museums", category: "Museum", lat: 41.8933, lon: 12.4829, day: 1, rating: 4.6),
      Seed(name: "Pantheon", category: "Landmark", lat: 41.8986, lon: 12.4769, day: 2, rating: 4.8),
      Seed(name: "Piazza Navona", category: "Square", lat: 41.8992, lon: 12.4731, day: 2, rating: 4.7),
      Seed(name: "Campo de' Fiori", category: "Market", lat: 41.8955, lon: 12.4722, day: 2, rating: 4.4),
      Seed(name: "Trevi Fountain", category: "Landmark", lat: 41.9009, lon: 12.4833, day: 2, rating: 4.7),
      Seed(name: "Vatican Museums", category: "Museum", lat: 41.9065, lon: 12.4536, day: 3, rating: 4.7),
      Seed(name: "St. Peter's Basilica", category: "Church", lat: 41.9022, lon: 12.4539, day: 3, rating: 4.8),
      Seed(name: "Trastevere", category: "Neighbourhood", lat: 41.8890, lon: 12.4694, day: 3, rating: 4.6),
    ]
    response.itineraryResponse.pointsOfInterest = plan.enumerated().map { offset, entry in
      var poi = Loci_Poi_POIDetailedInfo()
      poi.id = "preview-\(offset)"
      poi.name = entry.name
      poi.category = entry.category
      poi.latitude = entry.lat
      poi.longitude = entry.lon
      poi.day = Int32(entry.day)
      poi.priority = Int32(offset)
      poi.rating = entry.rating
      poi.descriptionPoi = "Worth the queue early; the light is best before ten and the crowds after."
      poi.address = "Rome, Italy"
      if offset == 0 {
        var credit = Loci_Poi_POIImage()
        credit.url = "https://upload.wikimedia.org/wikipedia/commons/thumb/d/de/Colosseo_2020.jpg/640px-Colosseo_2020.jpg"
        credit.attribution = "Wikimedia Commons"
        credit.licence = "CC BY-SA 4.0"
        poi.imageCredits = [credit]
      }
      return poi
    }
    var extra = Loci_Poi_POIDetailedInfo()
    extra.id = "preview-extra"
    extra.name = "Testaccio Market"
    extra.category = "Market"
    extra.latitude = 41.8770
    extra.longitude = 12.4760
    extra.rating = 4.5
    extra.descriptionPoi = "Where Romans actually eat lunch."
    response.pointsOfInterest = response.itineraryResponse.pointsOfInterest + [extra]
    state.adopt(response)
    return state
  }
}

extension Loci_Favorites_V1_FavoriteItem {
  static var savedPlaceSample: Self {
    var item = Self()
    item.id = "preview-saved"
    item.itemID = "Miradouro da Senhora do Monte|38.7193|-9.1327"
    item.itemName = "Miradouro da Senhora do Monte"
    item.contentType = .poi
    item.cityName = "Lisbon"
    item.category = "Viewpoint"
    item.rating = 4.8
    item.latitude = 38.7193
    item.longitude = -9.1327
    item.description_p = "The highest viewpoint in Lisbon, best just before sunset."
    item.notes = "Go on the way back from Graça."
    return item
  }
}

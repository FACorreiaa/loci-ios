import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Screens shown on their own when the app is launched with
/// `-designPreview <name>`, so a component can be looked at on a simulator
/// without signing in. Debug builds only; never set in normal use.
enum DesignPreview: String {
  case inSeason
  /// The notifications primer a first search raises, over an empty screen.
  case pushPrimer
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
  /// A finished answer followed by a proactive message with its caption, and a standing-task confirmation.
  case museProactive
  /// A standing request turned into a card: title, schedule, spec, Confirm / Not now.
  case museStandingCard
  /// The card after CreateWatch failed with ResourceExhausted.
  case museStandingCardLimit
  /// Ask Loci's conversation list with a proactive message on the newest thread.
  case museSessions
  /// Settings › Standing tasks with three tasks.
  case standingTasks
  /// A finished Rome itinerary: header, map hero, two days, "Show the rest", extras, Trip Kit.
  case results
  /// The same page scrolled to the days, and to the Trip Kit.
  case resultsDays
  case resultsKit
  /// The Trips list's Today band for a three-stop Rome day.
  case tripDay
  /// The same itinerary's full map: pitched 3D, flown to Day 1's first stop.
  case resultsFullMap
  /// A saved place pushed from Saved, opened on its snapshot: name-keyed, so
  /// there is nothing on the server to fill it in.
  case savedPlace
  /// Profile's About rows with the App Store rating link (as if an ID were
  /// set), and Settings' App section with the rating switch.
  case ratingRows
  /// Profile with its "You" hub rows above Settings (signed out, so the name reads "Traveler").
  case youHub
  /// Recents' feed with a day of each kind: chats, searches, a kept trip, favourites, Load more.
  case recents
  /// Recents' Cities view.
  case recentsCities
  /// One city from Recents: Overview with its stats and the latest prompts.
  case recentCity
  /// Profile › Lists: four lists (one public, one itinerary) with the tab chips.
  case lists
  /// One list: header, map card and four stop cards, one without a position.
  case listDetail
  /// A place's Add to list sheet over its detail.
  case addToList
  /// City Packs' catalog: filters, and a Free, a locked and a "✓ Yours" card.
  case packs
  /// A free pack: map hero, three days, one stop with no position, "Open as my trip".
  case packDetail
  /// A paid pack nobody owns: day one, "2 more days in this pack", no price.
  case packLocked
  /// A place's Reviews section: summary, star bars, three reviews, See all.
  case placeReviews
  /// The write/edit sheet, editing your own review, over the section.
  case reviewComposer
  /// Profile › My reviews: three of your reviews with the summary line.
  case myReviews
  /// A three-day trip page, offline, on a free plan: hero, preferences (open),
  /// days, the export menu, suggestions, packing and expenses.
  case tripExtras
  /// The same page scrolled to the checklists.
  case tripChecklists

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
    case .pushPrimer:
      Color.lociPaper.ignoresSafeArea().sheet(isPresented: .constant(true)) { PushPrimerSheet(primer: PushPrimer()) }
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
    case .museProactive:
      MuseChatPreview(state: .museSampleCompleted, thread: .preview(messages: MuseMessage.previewProactive), scrollTo: MuseChatPreview.threadEnd)
    case .museStandingCard:
      MuseChatPreview(
        state: .museSampleCompleted,
        thread: .preview(request: MuseMessage.previewRequest, card: .proposal(.preview)),
        scrollTo: MuseChatPreview.threadEnd
      )
    case .museStandingCardLimit:
      MuseChatPreview(
        state: .museSampleCompleted,
        thread: .preview(request: MuseMessage.previewRequest, card: .failed(.tooMany, proposal: .preview)),
        scrollTo: MuseChatPreview.threadEnd
      )
    case .museSessions: NavigationStack { MuseSessionsPreview() }
    case .standingTasks:
      NavigationStack { StandingTasksView(store: StandingTasksStore(service: PreviewStandingTaskService(), watches: Loci_Chat_Watch.previewList)) }
    case .museChatPush: MuseChatPushPreview()
    case .museChatPushBar: MuseChatPushPreview(hidesBar: false)
    case .results: MuseChatPreview(state: .resultsSample, caption: "Rome · 12 places")
    case .resultsDays: MuseChatPreview(state: .resultsSample, caption: "Rome · 12 places", scrollTo: ResultsPage.Anchor.days)
    case .resultsKit: MuseChatPreview(state: .resultsSample, caption: "Rome · 12 places", scrollTo: ResultsPage.Anchor.kit)
    case .tripDay: TripDayPreview()
    case .resultsFullMap: FullMapPreview(state: .resultsSample)
    case .savedPlace: NavigationStack { SavedPlaceDetailView(item: .savedPlaceSample) }
    case .ratingRows: NavigationStack { RatingRowsPreview() }
    case .youHub: ProfileView()
    case .recents: NavigationStack { RecentsView(store: RecentsStore(service: PreviewRecentsService())) }
    case .recentsCities: NavigationStack { RecentsView(store: RecentsStore(service: PreviewRecentsService()), segment: .cities) }
    case .recentCity: NavigationStack { RecentCityView(city: RecentCity.previewLisbon) }
    case .lists: NavigationStack { ListsView(store: ListsStore(service: PreviewListsService())) }
    case .listDetail: NavigationStack { ListDetailView(store: .preview) }
    case .addToList: AddToListPreview()
    case .packs: NavigationStack { PacksView(store: PacksStore(service: PreviewPacksService())) }
    case .packDetail: NavigationStack { PackDetailView(slug: PackSummary.previewLisbon.slug, service: PreviewPacksService()) }
    case .packLocked: NavigationStack { PackDetailView(slug: PackSummary.previewLocked.slug, service: PreviewPacksService()) }
    case .placeReviews: PlaceReviewsPreview()
    case .reviewComposer: ReviewComposerPreview()
    case .myReviews: NavigationStack { MyReviewsView(store: MyReviewsStore(service: PreviewReviewsService())) }
    case .tripExtras:
      NavigationStack {
        TripEditorView(
          tripID: Loci_Trip_TripDraft.previewLisbon.id,
          trip: .previewLisbon,
          checklist: .preview(tripID: Loci_Trip_TripDraft.previewLisbon.id),
          isOffline: true,
          expandsPreferences: true
        )
      }
    case .tripChecklists:
      NavigationStack {
        List { TripChecklistsSection(store: .preview(tripID: Loci_Trip_TripDraft.previewLisbon.id)) }.settingsStyle("Checklists")
      }
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

/// The rows the rating prompt adds, with a sample App Store ID so the Rate
/// row shows. The news switch is left out: it needs the server.
private struct RatingRowsPreview: View {
  var body: some View {
    List {
      Section("About") {
        ExternalLinkRow(title: "Loci Web", destination: URL(string: "https://lociai.fyi")!)
        ExternalLinkRow(title: "Rate Loci on the App Store", destination: URL(string: "https://apps.apple.com/app/id0000000000?action=write-review")!)
      }
      .listRowBackground(Color.lociCard)
      Section("App") {
        Label("Notifications", systemImage: "bell.badge")
        ReviewPromptToggle()
      }
    }
    .settingsStyle("Settings")
  }
}

/// The Muse chat screen assembled from the real components with sample data,
/// so it can be screenshotted without signing in.
private struct MuseChatPreview: View {
  static let threadEnd = "thread-end"

  let state: SearchState
  var thread: MuseThread?
  /// Held for the screenshot instead of timing out.
  var flash: MuseActivity.Flash?
  var isListening = false
  var caption = "Lisbon"
  var scrollTo: String?

  var body: some View {
    ScrollViewReader { proxy in
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          SearchTranscript(state: state, caption: caption)
          if let thread {
            MuseThreadTail(thread: thread, sessionId: "preview")
            Color.clear.frame(height: 1).id(Self.threadEnd)
          }
        }
        .padding(.horizontal, LociTheme.defaultPadding)
        .padding(.vertical, 12)
      }
      .task {
        guard let scrollTo else { return }
        try? await Task.sleep(for: .seconds(1))
        proxy.scrollTo(scrollTo, anchor: scrollTo == Self.threadEnd ? .bottom : .top)
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

/// FullMapView fed the way ResultsPage feeds it, with its own selection.
private struct FullMapPreview: View {
  let state: SearchState
  @State private var selectedID: String?

  var body: some View {
    let groups = state.dayGroups
    let sequence = DayGrouping.sequence(groups)
    let showsDays = state.destination == .itinerary
    FullMapView(
      data: ResultsMapData(groups: groups, extras: state.extras, sequence: sequence, showsDays: showsDays, alerts: []),
      groups: groups,
      sequence: sequence,
      destination: state.destination,
      showsDays: showsDays,
      title: state.cityName ?? "Rome",
      selectedID: $selectedID
    )
  }
}

/// Ask Loci's list rows with sample sessions: the newest carries a proactive message.
private struct MuseSessionsPreview: View {
  var body: some View {
    List {
      Section("Recent") {
        ForEach(Loci_Chat_ChatSession.previewList, id: \.id) { session in
          NavigationLink(value: session.id) { SessionRow(session: session) }
        }
      }
      .listRowBackground(Color.museAgentBubble)
    }
    .listStyle(.insetGrouped)
    .scrollContentBackground(.hidden)
    .background(Color.museCanvas.ignoresSafeArea())
    .safeAreaInset(edge: .top, spacing: 0) { MuseChatHeader(activity: .ready) }
    .toolbarVisibility(.hidden, for: .navigationBar)
    .navigationDestination(for: String.self) { Text($0) }
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

/// The Today band with a trip whose first day is today, so the controls show.
private struct TripDayPreview: View {
  var body: some View {
    let trip = Loci_Trip_TripDraft.previewRome
    NavigationStack {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text("My trips").font(.lociDisplay(28)).foregroundStyle(Color.lociInk)
          if let day = DayTimeline.today(in: trip) { TodayBand(trip: trip, day: day) }
        }
        .padding(LociTheme.defaultPadding)
      }
      .background(Color.lociPaper.ignoresSafeArea())
    }
  }
}

extension Loci_Trip_TripDraft {
  /// Three stops in Rome, dated today at midnight in the current calendar.
  static var previewRome: Loci_Trip_TripDraft {
    var trip = Loci_Trip_TripDraft()
    trip.id = "preview-rome"
    trip.cityName = "Rome"
    trip.title = "Rome on foot"
    var day = Loci_Trip_TripDay()
    day.id = "preview-day-1"
    day.dayNumber = 1
    day.cityName = "Rome"
    day.cityLat = 41.9028
    day.cityLon = 12.4964
    var utc = Calendar(identifier: .gregorian)
    utc.timeZone = TimeZone(identifier: "UTC") ?? .current
    let parts = Calendar.current.dateComponents([.year, .month, .day], from: Date())
    if let midnight = utc.date(from: DateComponents(year: parts.year, month: parts.month, day: parts.day)) {
      day.date = Google_Protobuf_Timestamp(date: midnight)
    }
    struct Seed {
      let name: String
      let lat: Double
      let lon: Double
    }
    let seeds = [
      Seed(name: "Colosseum", lat: 41.8902, lon: 12.4922), Seed(name: "Roman Forum", lat: 41.8925, lon: 12.4853),
      Seed(name: "Pantheon", lat: 41.8986, lon: 12.4769),
    ]
    day.stops = seeds.enumerated().map { offset, seed in
      var stop = Loci_Trip_TripStop()
      stop.id = "preview-stop-\(offset)"
      stop.name = seed.name
      stop.poi.name = seed.name
      stop.poi.latitude = seed.lat
      stop.poi.longitude = seed.lon
      return stop
    }
    trip.days = [day]
    return trip
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

// MARK: - Standing-task samples

/// Answers every call from fixed samples; the design previews never reach the network.
nonisolated struct PreviewStandingTaskService: StandingTaskService {
  func propose(text: String, timezone: String) async throws(WatchError) -> Loci_Chat_WatchProposal { .preview }
  func create(sessionId: String, proposal: Loci_Chat_WatchProposal) async throws(WatchError) -> Loci_Chat_CreateWatchResponse {
    var response = Loci_Chat_CreateWatchResponse()
    response.watch.id = "preview-watch"
    return response
  }
  func list(sessionId: String?) async throws(WatchError) -> [Loci_Chat_Watch] { Loci_Chat_Watch.previewList }
  func delete(id: String) async throws(WatchError) {}
  func history(sessionId: String) async throws(WatchError) -> [Loci_Chat_ConversationMessage] { [] }
}

extension Loci_Chat_WatchProposal {
  nonisolated static var preview: Loci_Chat_WatchProposal {
    var proposal = Loci_Chat_WatchProposal()
    proposal.title = "Rain in Lisbon tomorrow"
    proposal.scheduleHuman = "Every day at 08:00"
    proposal.intervalMinutes = 1440
    proposal.spec = "Check tomorrow's forecast for Lisbon and tell me if rain is likely, with an indoor swap for the plan if it is."
    return proposal
  }
}

extension MuseMessage {
  static let previewRequest = "Every morning at 8, tell me if it'll rain in Lisbon tomorrow"

  static var previewProactive: [MuseMessage] {
    [
      MuseMessage(
        id: "preview-confirm",
        role: .agent,
        text: "Got it — I'll watch the Lisbon forecast every morning at 08:00 and ping you when rain is likely.",
        origin: .proactive,
        sourceLabel: "Standing task"
      ),
      MuseMessage(
        id: "preview-run",
        role: .agent,
        text: "Showers are likely in Lisbon tomorrow from about 14:00. Swap the afternoon at Belém for the **Oceanário**, which is all indoors.",
        origin: .proactive,
        sourceLabel: "Standing task"
      ),
    ]
  }
}

extension Loci_Chat_Watch {
  nonisolated static var previewList: [Loci_Chat_Watch] {
    let now = Date()
    func watch(_ id: String, _ title: String, _ schedule: String, _ spec: String, nextIn hours: Double, enabled: Bool = true) -> Loci_Chat_Watch {
      var watch = Loci_Chat_Watch()
      watch.id = id
      watch.title = title
      watch.scheduleHuman = schedule
      watch.spec = spec
      watch.enabled = enabled
      watch.nextRunAt = .init(date: now.addingTimeInterval(hours * 3600))
      return watch
    }
    return [
      watch("w1", "Rain in Lisbon tomorrow", "Every day at 08:00", "Tell me if rain is likely in Lisbon tomorrow, with an indoor swap.", nextIn: 5),
      watch(
        "w2",
        "Late-night ramen near Shinjuku",
        "Every Friday at 18:00",
        "Find ramen places open after midnight within 10 minutes of my hotel.",
        nextIn: 50
      ),
      watch(
        "w3",
        "Porto festival dates",
        "Every week on Monday at 09:00",
        "Check whether São João 2027 dates and street closures are announced.",
        nextIn: 110
      ),
    ]
  }
}

extension Loci_Chat_ChatSession {
  nonisolated static var previewList: [Loci_Chat_ChatSession] {
    func message(_ role: Loci_Chat_MessageRole, _ text: String, origin: Loci_Chat_MessageOrigin = .reply, label: String = "") -> Loci_Chat_ConversationMessage {
      var message = Loci_Chat_ConversationMessage()
      message.id = UUID().uuidString
      message.role = role
      message.content = text
      message.origin = origin
      message.sourceLabel = label
      return message
    }
    var lisbon = Loci_Chat_ChatSession()
    lisbon.id = "s1"
    lisbon.cityName = "Lisbon"
    lisbon.updatedAt = .init(date: Date().addingTimeInterval(-3600))
    lisbon.conversationHistory = [
      message(.user, "3 days in Lisbon with kids, nothing too hilly"),
      message(.assistant, "Here is a gentle plan."),
      message(
        .assistant,
        "Showers are likely in Lisbon tomorrow from about 14:00. Swap Belém for the Oceanário.",
        origin: .proactive,
        label: "Standing task"
      ),
    ]
    var rome = Loci_Chat_ChatSession()
    rome.id = "s2"
    rome.cityName = "Rome"
    rome.updatedAt = .init(date: Date().addingTimeInterval(-86_400 * 2))
    rome.conversationHistory = [message(.user, "3 days in Rome, first time, lots of walking"), message(.assistant, "Rome on foot.")]
    return [lisbon, rome]
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

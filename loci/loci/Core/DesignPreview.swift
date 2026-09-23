import LociConnectProto
import SwiftUI

/// Screens shown on their own when the app is launched with
/// `-designPreview <name>`, so a component can be looked at on a simulator
/// without signing in. Debug builds only; never set in normal use.
enum DesignPreview: String {
  case inSeason
  /// The Muse chat (SearchResultsView's pieces) with a finished answer.
  case museChat
  /// The Muse chat while tokens stream in.
  case museChatStreaming

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
    case .museChatStreaming: MuseChatPreview(state: .museSampleStreaming, status: "Ready")
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
  var status = "Ready"

  var body: some View {
    ScrollView {
      SearchTranscript(state: state, caption: "Lisbon")
        .padding(.horizontal, LociTheme.defaultPadding)
        .padding(.vertical, 12)
    }
    .background(Color.museCanvas.ignoresSafeArea())
    .safeAreaInset(edge: .top, spacing: 0) { MuseChatHeader(status: status, leadingSystemImage: "chevron.left", leadingLabel: "Back") }
    .safeAreaInset(edge: .bottom, spacing: 0) {
      PreviewComposer().padding(.horizontal, LociTheme.defaultPadding).padding(.vertical, 10).background(Color.museCanvas)
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
  static var museSampleStreaming: SearchState {
    var state = SearchState()
    state.cityName = "Lisbon"
    state.query = "3 days in Lisbon with kids, nothing too hilly"
    state.status = .streaming
    state.text = "Lisbon is steep, so I'm keeping each day to one neighbourhood: Belém by the river first, then the flat Baixa grid, and a tram up to the castle for the one climb worth it."
    return state
  }

  static var museSampleCompleted: SearchState {
    var state = museSampleStreaming
    state.status = .completed
    var itinerary = Loci_Chat_AiCityResponse()
    itinerary.itineraryResponse.itineraryName = "Lisbon at a kid's pace"
    itinerary.itineraryResponse.overallDescription = "Three short days, one neighbourhood each, with a playground or a pastry stop every couple of hours."
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

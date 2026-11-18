import LociConnectProto
import SwiftUI

/// "Getting around from <stay>" under the trip's plan, one section per stay
/// (web: components/trip/StayTransportSection.tsx): the stops near it, the
/// airport, and what the map data cannot tell. Read-only, for every role.
struct StayTransportSections: View {
  let trip: Loci_Trip_TripDraft
  let model: StayTransportModel

  var body: some View {
    ForEach(trip.stays, id: \.cityName) { stay in
      if let phase = model.phase(for: stay.cityName) {
        StayTransportSection(stay: stay, phase: phase) { Task { await model.load(trip) } }
      }
    }
  }
}

struct StayTransportSection: View {
  let stay: Loci_Trip_TripStay
  let phase: StayTransportModel.Phase
  var onRetry: () -> Void = {}

  var body: some View {
    Section {
      switch phase {
      case .loading:
        HStack(spacing: 8) {
          ProgressView()
          Text("Looking for stops near \(Text(verbatim: stay.name))…").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
        }
      case .failed:
        VStack(alignment: .leading, spacing: 6) {
          Text("Couldn't load how to get around from this stay.").font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
          Button("Try again", action: onRetry).buttonStyle(.borderless).font(.lociCaption(13))
        }
      case .loaded(let transport):
        loaded(transport)
      }
    } header: {
      Text(verbatim: title).lociCoordStyle(11)
        // Counted when the section comes on screen with an answer in it.
        .task(id: viewed?.status) { if let viewed { HotelCompareAnalytics.transportViewed(viewed) } }
    }
  }

  private var viewed: Loci_Trip_StayTransport? {
    if case .loaded(let transport) = phase { transport } else { nil }
  }

  private var title: String {
    if case .loaded(let transport) = phase { return StayTransportFormat.title(transport, stayName: stay.name) }
    return StayTransportFormat.title(Loci_Trip_StayTransport(), stayName: stay.name)
  }

  @ViewBuilder private func loaded(_ transport: Loci_Trip_StayTransport) -> some View {
    if let message = StayTransportFormat.statusMessage(transport) {
      Text(verbatim: message).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
    }
    ForEach(StayTransportFormat.stopRows(transport)) { row in
      Label {
        AdaptiveStack(alignment: .firstTextBaseline, spacing: 8) {
          Text(verbatim: row.mode).font(.lociCaption(13).weight(.semibold)).foregroundStyle(Color.lociInk)
          Text(verbatim: row.line).font(.lociCaption(13)).foregroundStyle(Color.lociInk)
        }
      } icon: {
        Image(systemName: row.symbol).foregroundStyle(Color.lociMutedInk)
      }
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(Text(verbatim: row.spoken))
    }
    if transport.hasAirport { airport(transport.airport) }
    if !transport.stops.isEmpty {
      Text(verbatim: StayTransportFormat.footnote(transport)).font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
    }
  }

  private func airport(_ airport: Loci_Trip_AirportConnection) -> some View {
    AdaptiveStack(alignment: .firstTextBaseline, spacing: 8) {
      Label {
        Text("Airport \(Text(verbatim: StayTransportFormat.airportLine(airport)))").font(.lociCaption(13)).foregroundStyle(Color.lociInk)
      } icon: {
        Image(systemName: "airplane").foregroundStyle(Color.lociMutedInk)
      }
      Spacer(minLength: 0)
      DirectionsButton(
        links: StayTransportFormat.directions(apple: airport.appleDirectionsURL, google: airport.googleDirectionsURL),
        target: "airport",
        source: "trip",
        destination: airport.airportName
      )
    }
  }
}

/// "Directions": the journey in a maps app. One app opens straight away; with
/// both, a menu asks which.
struct DirectionsButton: View {
  let links: [StayTransportFormat.Directions]
  /// For analytics: what the journey is to (day | airport) and where it was opened.
  let target: String
  let source: String
  var suggestedMode: String?
  /// Named for VoiceOver, so a page of "Directions" buttons can be told apart.
  var destination = ""

  @Environment(\.openURL) private var openURL

  private var spoken: String {
    destination.isEmpty ? String(localized: "Directions") : String(localized: "Directions to \(destination)")
  }

  var body: some View {
    if links.count == 1, let only = links.first {
      Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") { open(only) }
        .modifier(DirectionsStyle(spoken: spoken))
    } else if !links.isEmpty {
      Menu {
        ForEach(links) { link in Button(link.label) { open(link) } }
      } label: {
        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond")
      }
      .modifier(DirectionsStyle(spoken: spoken))
    }
  }

  private func open(_ link: StayTransportFormat.Directions) {
    HotelCompareAnalytics.directionsOpened(target: target, provider: link.provider.rawValue, source: source, suggestedMode: suggestedMode)
    openURL(link.url)
  }
}

private struct DirectionsStyle: ViewModifier {
  let spoken: String

  func body(content: Content) -> some View {
    content
      .font(.lociCaption(13).weight(.semibold))
      .buttonStyle(.borderless)
      .tint(Color.lociForest)
      .frame(minHeight: LociTheme.minTapTarget)
      .contentShape(.rect)
      .accessibilityLabel(Text(verbatim: spoken))
  }
}

/// How a day begins from the stay: the walk to its first stop, or that public
/// transport is the better idea, with the journey a tap away. Worded like the
/// walking legs between stops (`WalkingLegRow`).
struct DayStartRow: View {
  let start: Loci_Trip_DayStart
  /// For analytics: "trip" or "itinerary".
  let source: String

  var body: some View {
    let links = StayTransportFormat.directions(apple: start.appleDirectionsURL, google: start.googleDirectionsURL)
    if let line = StayTransportFormat.dayStartLine(start) {
      AdaptiveStack(spacing: 8) {
        HStack(spacing: 8) {
          Image(systemName: StayTransportFormat.isTransitSuggested(start) ? "tram.fill" : "figure.walk")
            .foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
          VStack(alignment: .leading, spacing: 1) {
            Text(verbatim: line).font(.lociCaption(12).weight(.semibold)).foregroundStyle(Color.lociInk)
            if StayTransportFormat.isUnchecked(start) {
              Text("route not checked").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
            }
          }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: StayTransportFormat.spokenDayStart(start) ?? line))
        Spacer(minLength: 0)
        DirectionsButton(
          links: links,
          target: "day",
          source: source,
          suggestedMode: start.suggestedMode,
          destination: start.firstStopName
        )
      }
    } else if !links.isEmpty {
      AdaptiveStack(spacing: 8) {
        Text("From your hotel").font(.lociCaption(12).weight(.semibold)).foregroundStyle(Color.lociInk)
        Spacer(minLength: 0)
        DirectionsButton(links: links, target: "day", source: source, suggestedMode: start.suggestedMode, destination: start.firstStopName)
      }
    }
  }
}

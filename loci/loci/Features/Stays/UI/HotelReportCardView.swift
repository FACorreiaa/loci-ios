import LociConnectProto
import SwiftUI

/// Where "Add … to trip" stands on a report card.
nonisolated enum HotelReportAddState: Equatable, Sendable {
  case ready
  /// The hotel at this index is being added.
  case adding(Int)
  /// Done, in the words to show.
  case added(String)
  case failed(String)
}

/// A hotel comparison report (web: components/chat/HotelComparisonCard.tsx):
/// the verdict, the hotels side by side, what is good and what to watch out
/// for, what could not be checked, and one "Add … to trip" per hotel.
///
/// Every string in a report is drawn with `Text(verbatim:)`: some of it was
/// written from web pages, so none of it is read as markdown or made into a
/// link. The only things that open are a source's URL and a live rate's
/// booking URL, and only when they are https.
///
/// Pure rendering: the caller decides what Add does (`HotelReportCard`).
struct HotelReportCardView: View {
  let report: Loci_Chat_HotelComparisonReport
  var add: HotelReportAddState = .ready
  /// Shown in place of the Add buttons, when adding is not the caller's to do.
  var notice: String?
  var onAdd: (Int) -> Void = { _ in }
  var onOpenTrip: (() -> Void)?

  @Environment(\.openURL) private var openURL
  @Environment(\.dynamicTypeSize) private var typeSize

  private var names: [String] { HotelReport.names(report) }
  private var recommended: Int? { HotelReport.recommendedIndex(report) }
  /// Two hotels fit side by side on a phone; three, or large text, do not.
  private var sideBySide: Bool { report.hotels.count <= 2 && !typeSize.isAccessibilitySize }

  var body: some View {
    let rows = HotelReport.rows(report)
    let sources = HotelReport.sources(report)
    VStack(alignment: .leading, spacing: 14) {
      header
      verdict
      if !rows.isEmpty {
        if sideBySide { grid(rows) } else { stacked(rows) }
      }
      ForEach(Array(report.hotels.enumerated()), id: \.offset) { index, hotel in
        hotelBlock(hotel, at: index)
      }
      if !report.caveats.isEmpty { caveats }
      if !sources.isEmpty { sourceList(sources) }
      addArea
      if !report.attribution.isEmpty {
        Text(verbatim: report.attribution).font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  // MARK: - Verdict

  private var header: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(verbatim: HotelReport.title(report))
        .font(.lociHeadline(17))
        .accessibilityAddTraits(.isHeader)
      if let dates = HotelReport.dates(report) {
        Text(verbatim: dates).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
      }
    }
  }

  @ViewBuilder private var verdict: some View {
    if report.verdict.isEmpty {
      Text("No clear winner this time. Here is what we found for each.")
        .font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
    } else {
      Text(verbatim: report.verdict).font(.museBody)
    }
    if let recommended {
      Label {
        Text("Our pick: \(Text(verbatim: names[recommended]))")
      } icon: {
        Image(systemName: "checkmark.seal.fill")
      }
      .font(.lociCaption(13).weight(.semibold))
      .foregroundStyle(Color.lociForest)
    }
  }

  // MARK: - The table

  private func grid(_ rows: [HotelReport.Row]) -> some View {
    Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 8) {
      GridRow {
        Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]).accessibilityHidden(true)
        ForEach(Array(names.enumerated()), id: \.offset) { _, name in
          Text(verbatim: name).font(.lociCaption(12).weight(.semibold)).accessibilityHidden(true)
        }
      }
      Divider().accessibilityHidden(true)
      ForEach(rows) { row in
        GridRow {
          Text(verbatim: row.label).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
          ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
            Text(verbatim: value)
              .font(.lociCaption(13))
              .frame(maxWidth: .infinity, alignment: .leading)
              .accessibilityLabel(Text(verbatim: "\(row.label), \(names[index]): \(value)"))
          }
        }
      }
    }
  }

  private func stacked(_ rows: [HotelReport.Row]) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      ForEach(rows) { row in
        VStack(alignment: .leading, spacing: 2) {
          Text(verbatim: row.label).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).accessibilityAddTraits(.isHeader)
          ForEach(Array(row.values.enumerated()), id: \.offset) { index, value in
            Text(verbatim: "\(names[index]): \(value)").font(.lociCaption(13))
          }
        }
      }
    }
  }

  // MARK: - One hotel

  private func hotelBlock(_ hotel: Loci_Chat_ComparedHotel, at index: Int) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      AdaptiveStack(alignment: .firstTextBaseline, spacing: 8) {
        Text(verbatim: names[index]).font(.lociHeadline(15)).accessibilityAddTraits(.isHeader)
        if recommended == index {
          Label("Our pick", systemImage: "checkmark.seal.fill")
            .font(.lociCaption(12).weight(.semibold)).foregroundStyle(Color.lociForest)
        }
      }
      if !hotel.identified {
        Label(HotelReport.unidentifiedNote, systemImage: "questionmark.circle")
          .font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
      }
      if !hotel.neighbourhood.isEmpty { Text(verbatim: hotel.neighbourhood).font(.lociCaption(13)) }
      if !hotel.facilities.isEmpty {
        Text(verbatim: hotel.facilities.joined(separator: " · "))
          .font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
          .accessibilityLabel(Text(verbatim: hotel.facilities.joined(separator: ", ")))
      }
      ForEach(Array(hotel.nearby.enumerated()), id: \.offset) { _, highlight in
        Text(verbatim: HotelReport.nearbyLine(highlight)).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
      }
      points(hotel.pros, title: "Good", symbol: "plus.circle.fill", tint: .lociSuccess)
      points(hotel.cons, title: "Watch out", symbol: "exclamationmark.triangle.fill", tint: .lociLantern)
      if hotel.hasLivePrice { livePrice(hotel.livePrice) }
    }
    .padding(.top, 10)
    .overlay(alignment: .top) { Divider().accessibilityHidden(true) }
  }

  @ViewBuilder private func points(_ items: [String], title: LocalizedStringKey, symbol: String, tint: Color) -> some View {
    if !items.isEmpty {
      Text(title).font(.lociCaption(12).weight(.semibold)).foregroundStyle(Color.lociMutedInk).padding(.top, 2)
      ForEach(Array(items.enumerated()), id: \.offset) { _, item in
        Label {
          Text(verbatim: item).font(.lociCaption(13)).multilineTextAlignment(.leading)
        } icon: {
          Image(systemName: symbol).foregroundStyle(tint)
        }
        // The icon's meaning, said: colour and shape alone do not carry it.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("\(Text(title)): \(Text(verbatim: item))"))
      }
    }
  }

  @ViewBuilder private func livePrice(_ price: Loci_Chat_LivePrice) -> some View {
    if let line = HotelReport.livePrice(price) {
      Text("Rate when we looked: \(Text(verbatim: line))").font(.lociCaption(13))
      if let url = TransitFormat.httpsURL(price.bookingURL) {
        Button("See this rate", systemImage: "arrow.up.right") { openURL(url) }
          .buttonStyle(MusePillButtonStyle())
          .accessibilityHint("Opens the booking site")
      }
    }
  }

  // MARK: - Caveats and sources

  private var caveats: some View {
    VStack(alignment: .leading, spacing: 4) {
      Text("What we couldn't check").font(.lociCaption(12).weight(.semibold)).foregroundStyle(Color.lociMutedInk)
        .accessibilityAddTraits(.isHeader)
      ForEach(Array(report.caveats.enumerated()), id: \.offset) { _, caveat in
        Label {
          Text(verbatim: caveat).font(.lociCaption(13)).multilineTextAlignment(.leading)
        } icon: {
          Image(systemName: "minus").foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
        }
      }
    }
  }

  private func sourceList(_ sources: [HotelReport.Source]) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text("Sources").font(.lociCaption(12).weight(.semibold)).foregroundStyle(Color.lociMutedInk)
        .accessibilityAddTraits(.isHeader)
      ForEach(sources) { source in
        if let url = source.url {
          Button {
            openURL(url)
          } label: {
            Label {
              Text(verbatim: source.text).multilineTextAlignment(.leading)
            } icon: {
              Image(systemName: "arrow.up.right")
            }
            .font(.lociCaption(13))
            .frame(maxWidth: .infinity, minHeight: LociTheme.minTapTarget, alignment: .leading)
            .contentShape(.rect)
          }
          .buttonStyle(.plain)
          .foregroundStyle(Color.lociForest)
          .accessibilityHint("Opens in your browser")
        } else {
          Text(verbatim: source.text).font(.lociCaption(13))
        }
      }
    }
  }

  // MARK: - Add to trip

  private var isAdding: Bool { if case .adding = add { true } else { false } }

  @ViewBuilder private var addArea: some View {
    if case .added(let message) = add {
      Label {
        Text(verbatim: message)
      } icon: {
        Image(systemName: "checkmark.circle.fill")
      }
      .font(.lociBody(15).weight(.semibold))
      .foregroundStyle(Color.lociForest)
      if let onOpenTrip {
        Button("Open trip", systemImage: "arrow.right", action: onOpenTrip).buttonStyle(MusePillButtonStyle())
      }
    } else if let notice {
      Text(verbatim: notice).font(.lociCaption(13)).foregroundStyle(Color.lociMutedInk)
    } else {
      if case .failed(let text) = add {
        Text(verbatim: text).font(.lociCaption(13)).foregroundStyle(Color.lociDestructive)
      }
      VStack(alignment: .leading, spacing: 8) {
        ForEach(Array(report.hotels.enumerated()), id: \.offset) { index, hotel in
          if HotelReport.canAdd(hotel) {
            Button {
              onAdd(index)
            } label: {
              if add == .adding(index) {
                Text("Adding \(Text(verbatim: names[index]))…")
              } else {
                Text("Add \(Text(verbatim: names[index])) to trip")
              }
            }
            .buttonStyle(MusePillButtonStyle())
            .disabled(isAdding)
          } else {
            Text("\(Text(verbatim: names[index])) can't be added: we couldn't tell which hotel that link is.")
              .font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk)
          }
        }
      }
    }
  }
}

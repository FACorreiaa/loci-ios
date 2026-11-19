import LociConnectProto
import SwiftUI

/// The stamp under a stop: whether its place was found on a real map, and
/// what the map's hours say about the visit as planned.
///
/// The mark is boxed and the detail is plain text beside it, because they are
/// two facts: "Checked" must not read as covering hours nobody listed.
struct CheckStamp: View {
  let line: StopCheckLine

  private var ink: Color {
    switch line.tone {
    case .ok: .lociHolo
    case .attention: .lociLantern
    case .unknown: .lociMutedInk
    }
  }

  var body: some View {
    ViewThatFits(in: .horizontal) {
      HStack(alignment: .firstTextBaseline, spacing: 8) { mark; detail }
      VStack(alignment: .leading, spacing: 4) { mark; detail }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(line.explain)
  }

  private var mark: some View {
    HStack(spacing: 4) {
      Image(systemName: line.tone == .unknown ? "minus" : "checkmark")
        .font(.system(size: 8, weight: .heavy))
      Text(line.mark)
        .font(.lociCoord(10).weight(line.tone == .unknown ? .regular : .bold))
        .textCase(.uppercase)
        .tracking(1.2)
    }
    .foregroundStyle(ink)
    .padding(.horizontal, 6)
    .padding(.vertical, 3)
    .overlay {
      RoundedRectangle(cornerRadius: 2)
        .strokeBorder(ink, style: StrokeStyle(lineWidth: 1, dash: line.tone == .unknown ? [3, 2] : []))
    }
  }

  @ViewBuilder private var detail: some View {
    if !line.detail.isEmpty {
      Text(line.detail)
        .font(.lociCoord(10))
        .textCase(.uppercase)
        .tracking(1.2)
        .foregroundStyle(line.tone == .attention ? Color.lociInk : Color.lociMutedInk)
    }
  }
}

/// The credit OpenStreetMap asks for wherever its data is shown.
struct CheckSourceNote: View {
  var body: some View {
    if let url = URL(string: "https://www.openstreetmap.org/copyright") {
      Link("Stops checked against the map · © OpenStreetMap contributors", destination: url)
        .font(.lociCoord(10))
        .foregroundStyle(Color.lociMutedInk)
        .listRowBackground(Color.clear)
    }
  }
}

extension Loci_Trip_TripDraft {
  /// Whether any stop carries a check, so the credit is shown only with them.
  var hasStopChecks: Bool { days.contains { $0.stops.contains(where: \.hasCheck) } }
}

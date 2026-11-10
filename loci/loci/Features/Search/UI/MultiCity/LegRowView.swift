import LociConnectProto
import SwiftUI

/// Travel between two cities of a trip. An estimate from distance, and labelled one.
struct LegRowView: View {
  let leg: Loci_Trip_TripLeg

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: MultiCityFormat.symbol(leg)).foregroundStyle(Color.lociMutedInk)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(leg.fromName) → \(leg.toName)").font(.lociBody(15).weight(.medium)).foregroundStyle(Color.lociInk)
        Text(MultiCityFormat.leg(leg)).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
      Spacer()
      Text("Estimate").lociCoordStyle(10)
    }
    .padding(12)
    .background {
      RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous)
        .strokeBorder(Color.lociBorder, style: StrokeStyle(lineWidth: LociTheme.borderWidth, dash: [4, 3]))
    }
    .accessibilityElement(children: .combine)
  }
}

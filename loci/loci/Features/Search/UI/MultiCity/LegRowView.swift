import LociConnectProto
import SwiftUI

/// Travel between two cities of a trip. An estimate from distance, and labelled one.
struct LegRowView: View {
  let leg: Loci_Trip_TripLeg

  var body: some View {
    HStack(spacing: 10) {
      Image(systemName: MultiCityFormat.symbol(leg)).foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 2) {
        Text("\(leg.fromName) → \(leg.toName)").font(.subheadline.weight(.medium))
        Text(MultiCityFormat.leg(leg)).font(.caption).foregroundStyle(.secondary)
      }
      Spacer()
      Text("Estimate").font(.caption2).foregroundStyle(.secondary)
    }
    .padding(12)
    .background(
      RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous)
        .strokeBorder(Color.lociBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
    )
    .accessibilityElement(children: .combine)
  }
}

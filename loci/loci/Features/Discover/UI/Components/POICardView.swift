import SwiftUI
import LociConnectProto

public struct POICardView: View {
    public let poi: Loci_Poi_POIDetailedInfo
    public var onSelect: () -> Void = {}

    public init(poi: Loci_Poi_POIDetailedInfo, onSelect: @escaping () -> Void = {}) {
        self.poi = poi
        self.onSelect = onSelect
    }

    public var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    if !poi.category.isEmpty {
                        Text(poi.category.uppercased())
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(.lociForest)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.lociSage.opacity(0.4))
                            .cornerRadius(6)
                    }

                    Spacer()

                    if poi.rating > 0 {
                        HStack(spacing: 3) {
                            Image(systemName: "star.fill")
                                .font(.caption2)
                                .foregroundColor(.orange)
                            Text(String(format: "%.1f", poi.rating))
                                .font(.caption.weight(.semibold))
                                .foregroundColor(.lociInk)
                        }
                    }
                }

                Text(poi.name)
                    .font(.headline.weight(.semibold))
                    .foregroundColor(.lociInk)
                    .lineLimit(1)

                if poi.hasDescriptionPoi && !poi.descriptionPoi.isEmpty {
                    Text(poi.descriptionPoi)
                        .font(.subheadline)
                        .foregroundColor(.lociInk.opacity(0.7))
                        .lineLimit(2)
                }

                HStack {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.caption2)
                        .foregroundColor(.lociCoral)
                    Text(poi.city.isEmpty ? poi.address : "\(poi.name), \(poi.city)")
                        .font(.caption)
                        .foregroundColor(.lociInk.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .padding(16)
            .background(Color.lociCard)
            .cornerRadius(LociTheme.cornerRadius)
            .overlay(
                RoundedRectangle(cornerRadius: LociTheme.cornerRadius)
                    .stroke(Color.lociBorder.opacity(0.6), lineWidth: LociTheme.borderWidth)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

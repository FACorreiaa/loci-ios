import LociConnectProto
import SwiftUI

/// A profile's showcase (web: Showcase): up to four medallions, the newest
/// then the rarest, as the server picks them.
struct ShowcaseRow: View {
  let showcase: [Loci_Achievement_AchievementSummary]

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ForEach(showcase.prefix(4), id: \.id) { summary in
        VStack(spacing: 6) {
          MedallionView(summary, size: 52)
          Text(summary.label).font(.lociCaption(11)).foregroundStyle(Color.lociInk).multilineTextAlignment(.center).lineLimit(2)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
      }
    }
    .padding(.vertical, 6)
  }
}

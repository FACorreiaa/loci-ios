import LociConnectProto
import SwiftUI

/// A symbol on a ring (web: Medallion). Earned: the ring in the tier's metal
/// (the accent for a moment or a secret) over a tinted face. Not yet: a dashed
/// muted ring and a faded symbol.
struct MedallionView: View {
  let symbol: String
  let kind: AchievementKind
  let tier: AchievementTier
  let earned: Bool
  var size: CGFloat = 48

  var body: some View {
    ZStack {
      Circle().fill(earned ? ring.opacity(0.14) : Color.lociMuted)
      Circle().strokeBorder(earned ? ring : Color.lociBorder, style: StrokeStyle(lineWidth: 2, dash: earned ? [] : [4, 3]))
      Image(systemName: symbol)
        .font(.system(size: size * 0.42, weight: .semibold))
        .foregroundStyle(earned ? ring : Color.lociMutedInk.opacity(0.6))
    }
    .frame(width: size, height: size)
    .accessibilityHidden(true)
  }

  private var ring: Color { Self.ring(kind: kind, tier: tier) }

  static func ring(kind: AchievementKind, tier: AchievementTier) -> Color {
    guard kind == .track else { return .lociCoral }
    switch tier {
    case .bronze: return .lociBronze
    case .silver: return .lociSilver
    case .gold: return .lociGold
    case .platinum: return .lociPlatinum
    case .unranked: return .lociCoral
    }
  }
}

extension MedallionView {
  init(_ achievement: Loci_Achievement_Achievement, size: CGFloat = 48) {
    self.init(
      symbol: achievement.hidden ? "questionmark" : achievement.symbol,
      kind: achievement.kindValue,
      tier: achievement.tierValue,
      earned: achievement.isEarned,
      size: size
    )
  }

  init(_ summary: Loci_Achievement_AchievementSummary, size: CGFloat = 48) {
    self.init(symbol: summary.symbol, kind: summary.kindValue, tier: summary.tierValue, earned: true, size: size)
  }
}

import SwiftUI
import UIKit

/// Design tokens from loci-client/docs/NATIVE_DESIGN.md. Change them there first.
public enum LociTheme {
  // MARK: - Spacing & Corner Radius
  public static let cornerRadius: CGFloat = 12.8
  public static let cornerRadiusHero: CGFloat = 14.4
  public static let borderWidth: CGFloat = 1.0
  public static let defaultPadding: CGFloat = 16.0
  public static let cardPadding: CGFloat = 16.0
  public static let minTapTarget: CGFloat = 44.0

  // MARK: - Motion
  public static let defaultSpring = Animation.spring(response: 0.35, dampingFraction: 0.86)
  /// Streamed results arriving: 400ms, cubic-bezier(0.16, 1, 0.3, 1).
  public static let resultArrive = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.4)
  /// A selection settling: 250ms, cubic-bezier(0.22, 1, 0.36, 1).
  public static let selectionSettle = Animation.timingCurve(0.22, 1, 0.36, 1, duration: 0.25)
  /// What Reduce Motion falls back to: a short fade, no movement.
  public static let reducedFade = Animation.easeOut(duration: 0.2)
  /// The mascot's idle bob: 2pt, 4s round trip. Off under Reduce Motion.
  public static let mascotIdle = Animation.easeInOut(duration: 2).repeatForever(autoreverses: true)

  /// Map day colours, in order (day 1 first). Cycle past day 8.
  /// Web's `LOCI_DAY_COLORS` (loci-client/src/lib/theme-colors.ts), same order
  /// and the same indexing: the server's 1-based day picks `dayColors[day % 8]`,
  /// so Day 1 is pine teal on both, and a one-day list (day 0) is coral.
  public static let dayColors: [Color] = [0xE2664A, 0x2F7D6E, 0xB07A2A, 0x7A5CA8, 0x4A7CB0, 0x8C6248, 0x5E8C3A, 0xA34F72].map { Color(hex: $0) }
  public static let clusterColor = Color(hex: 0xAE3722)
  public static let ungroupedColor = Color(hex: 0x6E7A82)

  public static func dayColor(_ day: Int) -> Color { dayColors[max(day, 0) % dayColors.count] }
  /// Web's `colorForMapDay(0)`: the pins and stamps of a list that has no days.
  public static var listColor: Color { dayColor(0) }
  /// Text on a day-coloured stamp or pin: the light paper in both schemes, since the stamps stay dark.
  public static let stampInk = Color(hex: 0xFBF6EF)

  /// Muse chat metrics, from apps/_reviews/muse-chat-contract.md (shared across the four apps).
  public enum Muse {
    public static let bubbleRadius: CGFloat = 24
    public static let avatarSize: CGFloat = 110
    public static let headerButtonSize: CGFloat = 40
    /// Height of the canvas → clear gradient behind the header.
    public static let scrimHeight: CGFloat = 120
    /// Bubble max widths, as a fraction of the transcript's content width.
    public static let userBubbleWidth: CGFloat = 0.85
    public static let agentBubbleWidth: CGFloat = 0.94
    /// The working ring: its stroke, and how far outside the avatar it sits.
    public static let ringWidth: CGFloat = 3
    public static let ringInset: CGFloat = 5
  }
}

public extension Color {
  nonisolated init(hex: UInt32) {
    self.init(
      red: Double((hex >> 16) & 0xFF) / 255,
      green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255
    )
  }

  nonisolated private static func dynamic(light: UInt32, dark: UInt32) -> Color {
    Color(
      UIColor { trait in
        let hex = trait.userInterfaceStyle == .dark ? dark : light
        return UIColor(
          red: CGFloat((hex >> 16) & 0xFF) / 255,
          green: CGFloat((hex >> 8) & 0xFF) / 255,
          blue: CGFloat(hex & 0xFF) / 255,
          alpha: 1
        )
      }
    )
  }

  // MARK: - Tokens (NATIVE_DESIGN §1)
  // "Explore your way" (2026-10): obsidian / cream / signal coral, the same
  // sRGB as web themes.css. The old names (paper, ink, forest, sage, coral) are
  // kept so call sites and branches in flight still compile; each now carries
  // the new value, and the semantic names below point at them.
  /// background: cream / obsidian
  static let lociPaper = dynamic(light: 0xFBF6EF, dark: 0x11161D)
  /// foreground: ink / cream
  static let lociInk = dynamic(light: 0x151B23, dark: 0xF7F1E9)
  /// card: white / graphite
  static let lociCard = dynamic(light: 0xFFFFFF, dark: 0x1B222D)
  /// primary: signal coral. Deep coral on light (white label 5.4:1, 5.0:1 on
  /// cream), bright coral on dark (6.8:1 on obsidian, obsidian label).
  static let lociForest = dynamic(light: 0xB8452E, dark: 0xF47B5D)
  /// Text and icons on a `lociForest` fill: white on the deep coral (5.4:1),
  /// obsidian on the bright coral (6.8:1). White on the bright coral is 2.5:1.
  static let lociOnForest = dynamic(light: 0xFFFFFF, dark: 0x11161D)
  /// A primary fill for places the system forces a white label: swipe actions.
  /// The deep coral in both schemes, so white measures 5.4:1.
  static let lociForestFill = dynamic(light: 0xB8452E, dark: 0xB8452E)
  /// A coral fill for places that carry a white label: swipe actions,
  /// `.borderedProminent` buttons and chips tinted coral. Same deep coral as
  /// `lociForestFill`: white on it is 5.4:1 (WCAG AA) in both schemes.
  static let lociCoralFill = dynamic(light: 0xB8452E, dark: 0xB8452E)
  /// secondary (also the active tab fill)
  static let lociSage = dynamic(light: 0xF1EADF, dark: 0x232D38)
  /// muted
  static let lociMuted = dynamic(light: 0xF3ECE2, dark: 0x1D252F)
  /// mutedForeground: 5.6:1 on cream, 7.9:1 on obsidian
  static let lociMutedInk = dynamic(light: 0x5A6472, dark: 0xA4ACB7)
  /// The text/icon coral accent. Bright coral fails as text on cream (2.5:1),
  /// so light mode takes the deep coral, the same as primary.
  static let lociCoral = dynamic(light: 0xB8452E, dark: 0xF47B5D)
  /// border
  static let lociBorder = dynamic(light: 0xE4DACD, dark: 0x2A3441)
  /// destructive
  static let lociDestructive = dynamic(light: 0xB32D29, dark: 0xF0615C)
  /// Lantern (warm): discovery, in-season, achievements.
  static let lociLantern = dynamic(light: 0x9B5B17, dark: 0xFBBB7E)
  /// Holo (cool steel): info, spatial data, routes.
  static let lociHolo = dynamic(light: 0x3F6A92, dark: 0x7A9CC2)
  /// Confirmations.
  static let lociSuccess = dynamic(light: 0x1F7A4D, dark: 0x4CB882)

  // MARK: - Semantic names (prefer these in new code)
  static var lociPrimary: Color { lociForest }
  static var lociOnPrimary: Color { lociOnForest }
  static var lociPrimaryFill: Color { lociForestFill }
  /// Hero bands and the launch screen: obsidian in both schemes.
  static let lociObsidian = Color(hex: 0x11161D)
  /// Text on `lociObsidian` in both schemes.
  static let lociOnObsidian = Color(hex: 0xF7F1E9)

  // MARK: - Achievement tiers (web: --tier-* in styles/base.css)
  /// The metal of an earned track rung: a medallion's ring and tint.
  static let lociBronze = dynamic(light: 0xB16A2F, dark: 0xD8935A)
  static let lociSilver = dynamic(light: 0x7A8590, dark: 0xAFB8C0)
  static let lociGold = dynamic(light: 0xBD890F, dark: 0xF2C036)
  static let lociPlatinum = dynamic(light: 0x508C9B, dark: 0x94C7D1)

  // MARK: - Muse chat tokens (apps/_reviews/muse-chat-contract.md)
  /// Chat canvas: the page.
  static let museCanvas = lociPaper
  /// Agent bubble: a card.
  static let museAgentBubble = lociCard
  /// User bubble: primary, as on the web.
  static let museUserBubble = lociForest
  /// Ink on the user bubble: primary's own label colour.
  static let museUserText = lociOnForest
  /// Header pill, header buttons and the composer field.
  static let musePill = lociMuted
  static let museText = lociInk
  static let museTextSecondary = lociMutedInk
  /// The avatar's working ring: the app accent (the user bubble's coral).
  static let museRing = lociCoral
}

// MARK: - Type (NATIVE_DESIGN §2)

public extension Font {
  /// Outfit, the brand's display face (the wordmark's rounded geometry), for
  /// headlines and brand moments. Scales with Dynamic Type.
  static func lociDisplay(_ size: CGFloat = 34) -> Font {
    .custom("Outfit", size: size, relativeTo: .largeTitle).weight(.semibold)
  }
  static func lociTitle(_ size: CGFloat = 24) -> Font { .custom("Outfit", size: size, relativeTo: .title).weight(.semibold) }
  /// DM Sans, for UI text.
  static func lociHeadline(_ size: CGFloat = 17) -> Font {
    .custom("DM Sans", size: size, relativeTo: .headline).weight(.medium)
  }
  static func lociBody(_ size: CGFloat = 16) -> Font { .custom("DM Sans", size: size, relativeTo: .body) }
  static func lociCaption(_ size: CGFloat = 12) -> Font { .custom("DM Sans", size: size, relativeTo: .caption) }
  /// Space Mono, for coordinates, sequence numbers and status. Pair with `.textCase(.uppercase)` and tracking.
  static func lociCoord(_ size: CGFloat = 11) -> Font { .custom("Space Mono", size: size, relativeTo: .caption2) }

  /// Muse chat type. DM Sans at 17 has a ~22pt line, matching iOS `.body` 17/22.
  static let museBody = Font.custom("DM Sans", size: 17, relativeTo: .body)
  static let museName = Font.custom("DM Sans", size: 15, relativeTo: .subheadline).weight(.semibold)
  static let museStatus = Font.custom("DM Sans", size: 13, relativeTo: .footnote)
}

public extension View {
  /// A flat card: card fill, 1px border, NATIVE_DESIGN radius. No shadow.
  func lociCard(padding: CGFloat = LociTheme.cardPadding) -> some View {
    self.padding(padding).background(Color.lociCard)
      .clipShape(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
      .overlay {
        RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).stroke(Color.lociBorder, lineWidth: LociTheme.borderWidth)
      }
  }

  /// Space Mono label styling: uppercase with tracking.
  func lociCoordStyle(_ size: CGFloat = 11) -> some View {
    self.font(.lociCoord(size)).textCase(.uppercase).tracking(1.2).foregroundStyle(Color.lociMutedInk)
  }
}

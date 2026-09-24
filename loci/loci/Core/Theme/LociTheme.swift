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

  /// Map day colours, in order (day 1 first). Cycle past day 8.
  /// Web's `LOCI_DAY_COLORS` (loci-client/src/lib/theme-colors.ts), same order
  /// and the same indexing: the server's 1-based day picks `dayColors[day % 8]`,
  /// so Day 1 is pine teal on both, and a one-day list (day 0) is coral.
  public static let dayColors: [Color] = [0xE2664A, 0x2F7D6E, 0xB07A2A, 0x7A5CA8, 0x4A7CB0, 0x8C6248, 0x5E8C3A, 0xA34F72].map { Color(hex: $0) }
  public static let clusterColor = Color(hex: 0x294D3C)
  public static let ungroupedColor = Color(hex: 0x6E7A82)

  public static func dayColor(_ day: Int) -> Color { dayColors[max(day, 0) % dayColors.count] }
  /// Web's `colorForMapDay(0)`: the pins and stamps of a list that has no days.
  public static var listColor: Color { dayColor(0) }
  /// Text on a day-coloured stamp or pin: the light paper in both schemes, since the stamps stay dark.
  public static let stampInk = Color(hex: 0xF5F0E6)

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
  /// background
  static let lociPaper = dynamic(light: 0xF5F0E6, dark: 0x101A16)
  /// foreground
  static let lociInk = dynamic(light: 0x1A2E26, dark: 0xEDE8DC)
  /// card
  static let lociCard = dynamic(light: 0xFDFBF7, dark: 0x162019)
  /// primary
  static let lociForest = dynamic(light: 0x214D3C, dark: 0xA8B896)
  /// secondary (also the active tab fill)
  static let lociSage = dynamic(light: 0xD8E0D0, dark: 0x384840)
  /// muted. Dark value kept from the app's earlier palette; NATIVE_DESIGN gives none.
  static let lociMuted = dynamic(light: 0xE8E2D6, dark: 0x1F2923)
  /// mutedForeground. NATIVE_DESIGN gives no dark value; this one is web's (styles/base.css).
  static let lociMutedInk = dynamic(light: 0x5A6B62, dark: 0xB9AFA2)
  /// accent (terracotta)
  static let lociCoral = dynamic(light: 0xC76B4A, dark: 0xD4845C)
  /// border
  static let lociBorder = dynamic(light: 0xCFC5B5, dark: 0x384840)
  /// destructive. Dark value from web (styles/base.css), as above.
  static let lociDestructive = dynamic(light: 0xB33A32, dark: 0xDA534E)

  // MARK: - Muse chat tokens (apps/_reviews/muse-chat-contract.md)
  /// Chat canvas: #101A16 dark, lociPaper light.
  static let museCanvas = dynamic(light: 0xF5F0E6, dark: 0x101A16)
  /// Agent bubble: #162019 dark, lociCard light.
  static let museAgentBubble = dynamic(light: 0xFDFBF7, dark: 0x162019)
  /// User bubble: darkened coral in both schemes.
  static let museUserBubble = Color(hex: 0xD4845C)
  /// Ink on the user bubble. Always the dark ink: the light dark-mode ink fails contrast on coral.
  static let museUserText = Color(hex: 0x1A2E26)
  /// Header pill, header buttons and the composer field.
  static let musePill = lociMuted
  static let museText = lociInk
  static let museTextSecondary = lociMutedInk
  /// The avatar's working ring: the app accent (the user bubble's coral).
  static let museRing = lociCoral
}

// MARK: - Type (NATIVE_DESIGN §2)

public extension Font {
  /// Fraunces, for destination headlines. Scales with Dynamic Type.
  static func lociDisplay(_ size: CGFloat = 34) -> Font {
    .custom("Fraunces", size: size, relativeTo: .largeTitle).weight(.semibold)
  }
  static func lociTitle(_ size: CGFloat = 24) -> Font { .custom("Fraunces", size: size, relativeTo: .title).weight(.semibold) }
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
      .overlay(
        RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).stroke(Color.lociBorder, lineWidth: LociTheme.borderWidth)
      )
  }

  /// Space Mono label styling: uppercase with tracking.
  func lociCoordStyle(_ size: CGFloat = 11) -> some View {
    self.font(.lociCoord(size)).textCase(.uppercase).tracking(1.2).foregroundStyle(Color.lociMutedInk)
  }
}

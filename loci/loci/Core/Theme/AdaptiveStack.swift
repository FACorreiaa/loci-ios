import SwiftUI

/// An `HStack` at regular text sizes and a leading `VStack` at accessibility
/// sizes, for rows whose pieces stop fitting side by side once Dynamic Type
/// reaches AX1 and up (text otherwise wraps a letter per line).
struct AdaptiveStack<Content: View>: View {
  var alignment: VerticalAlignment = .center
  var spacing: CGFloat?
  @ViewBuilder var content: () -> Content

  @Environment(\.dynamicTypeSize) private var typeSize

  var body: some View {
    let layout =
      typeSize.isAccessibilitySize
      ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
      : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
    layout(content)
  }
}

/// Short facts joined with a middle dot as one run of text, so it wraps
/// between words at large sizes instead of squeezing each piece; VoiceOver
/// hears the pieces with a pause, not the dot.
struct MetaLine: View {
  let parts: [String]

  init(_ parts: String...) { self.parts = parts }
  init(parts: [String]) { self.parts = parts }

  private var visible: [String] { parts.filter { !$0.isEmpty } }

  var body: some View {
    Text(visible.joined(separator: " · ")).accessibilityLabel(visible.joined(separator: ", "))
  }
}

extension View {
  /// Sheet detents that open full height at accessibility text sizes, where
  /// a medium sheet shows a heading and little else.
  func adaptiveDetents(_ detents: Set<PresentationDetent>) -> some View {
    modifier(AdaptiveDetents(detents: detents))
  }
}

private struct AdaptiveDetents: ViewModifier {
  let detents: Set<PresentationDetent>

  @Environment(\.dynamicTypeSize) private var typeSize

  func body(content: Content) -> some View {
    content.presentationDetents(typeSize.isAccessibilitySize ? [.large] : detents)
  }
}

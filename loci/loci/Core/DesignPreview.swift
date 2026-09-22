import SwiftUI

/// Screens shown on their own when the app is launched with
/// `-designPreview <name>`, so a component can be looked at on a simulator
/// without signing in. Debug builds only; never set in normal use.
enum DesignPreview: String {
  case inSeason

  static var requested: DesignPreview? {
    #if DEBUG
      let arguments = ProcessInfo.processInfo.arguments
      guard let index = arguments.firstIndex(of: "-designPreview"), index + 1 < arguments.count else { return nil }
      return DesignPreview(rawValue: arguments[index + 1])
    #else
      return nil
    #endif
  }

  @ViewBuilder var body: some View {
    switch self {
    case .inSeason: InSeasonPreview()
    }
  }
}

private struct InSeasonPreview: View {
  @State private var seed = ""
  @State private var text = ""

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        Text("Where to next?").font(.lociDisplay(30)).foregroundStyle(Color.lociInk)
        TextField("Ask Loci", text: $text)
          .font(.lociBody())
          .padding(.horizontal, 14).padding(.vertical, 10)
          .background(Color.lociCard, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
          .overlay(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).stroke(Color.lociBorder))
        InSeasonBand(seed: $seed)
      }
      .padding(LociTheme.defaultPadding)
    }
    .background(Color.lociPaper.ignoresSafeArea())
    .onChange(of: seed) { _, value in
      guard !value.isEmpty else { return }
      text = value
      seed = ""
    }
  }
}

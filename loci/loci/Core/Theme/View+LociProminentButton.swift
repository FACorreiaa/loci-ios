import SwiftUI

extension View {
  /// The primary call to action: `.borderedProminent` filled with the forest
  /// token, labelled in `lociOnForest`. Use this instead of pairing
  /// `.borderedProminent` with `.tint(.lociForest)` by hand: the system picks a
  /// white label, which fails contrast on dark mode's sage forest.
  func lociProminentButton() -> some View {
    buttonStyle(.borderedProminent)
      .tint(Color.lociForest)
      .foregroundStyle(Color.lociOnForest)
  }
}

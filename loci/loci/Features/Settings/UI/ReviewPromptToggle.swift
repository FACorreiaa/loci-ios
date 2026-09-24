import SwiftUI

/// Lets the user stop Loci asking for a rating. Kept on this phone only;
/// ReviewPrompter reads it before every ask.
struct ReviewPromptToggle: View {
  @Bindable private var reviews = ReviewPrompter.shared

  var body: some View {
    Toggle(isOn: $reviews.isEnabled) {
      Label("Ask me to rate Loci", systemImage: "star.bubble")
    }
  }
}

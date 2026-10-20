import SwiftUI

/// Opt-in visit logging on trip days. Kept on this phone only; turning it on
/// asks for Always location, which iOS needs to report stays in the background.
struct VisitLoggingToggle: View {
  @AppStorage(VisitLogger.enabledKey) private var isOn = false

  var body: some View {
    Toggle(isOn: Binding(get: { isOn }, set: { VisitLogger.setEnabled($0) })) {
      Label {
        VStack(alignment: .leading, spacing: 2) {
          Text("Log places I visit on trips")
          Text(
            "On trip days, Loci asks \u{201C}Were you at\u{2026}?\u{201D} when you stop at a planned or saved place. "
              + "Nothing is logged until you say yes."
          )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
      } icon: {
        Image(systemName: "figure.walk.motion")
      }
    }
  }
}

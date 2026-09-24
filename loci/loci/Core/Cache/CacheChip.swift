import SwiftUI

/// The one line a page shows when it is drawing the phone's copy.
nonisolated enum CacheChipText {
  static func text(staleSince: Date?, isOffline: Bool, now: Date = Date()) -> String? {
    guard let staleSince else { return nil }
    let relative = RelativeDateTimeFormatter()
    relative.unitsStyle = .full
    let ago = relative.localizedString(for: staleSince, relativeTo: now)
    return isOffline ? "Offline · last updated \(ago)" : "Saved \(ago)"
  }
}

struct CacheChip<M: Sendable>: View {
  let loaded: Loaded<M>?

  var body: some View {
    if let loaded, let text = CacheChipText.text(staleSince: loaded.staleSince, isOffline: loaded.isOffline) {
      Label(text, systemImage: loaded.isOffline ? "wifi.slash" : "internaldrive")
        .lociCoordStyle(10)
        .accessibilityLabel(text)
    }
  }
}

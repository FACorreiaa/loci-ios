import SwiftUI

/// The one line a page shows when it is drawing the phone's copy.
nonisolated enum CacheChipText {
  static func text(staleSince: Date?, isOffline: Bool, now: Date = Date()) -> String? {
    guard let staleSince else { return nil }
    let ago = Date.AnchoredRelativeFormatStyle(anchor: staleSince, presentation: .numeric, unitsStyle: .wide).format(now)
    return isOffline ? "Offline · last updated \(ago)" : "Saved \(ago)"
  }
}

struct CacheChip<M: Sendable>: View {
  let loaded: Loaded<M>?

  var body: some View {
    if let loaded, let staleSince = loaded.staleSince {
      // Re-read every minute so "2 minutes ago" keeps counting while the page stays open.
      TimelineView(.everyMinute) { context in
        let text = CacheChipText.text(staleSince: staleSince, isOffline: loaded.isOffline, now: context.date) ?? ""
        Label(text, systemImage: loaded.isOffline ? "wifi.slash" : "internaldrive")
          .lociCoordStyle(10)
          .accessibilityLabel(text)
      }
    }
  }
}

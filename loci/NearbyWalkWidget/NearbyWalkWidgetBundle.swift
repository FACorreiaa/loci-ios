import SwiftUI
import WidgetKit

/// The extension that draws Loci's Live Activities. Only the Near me walk for now.
@main struct NearbyWalkWidgetBundle: WidgetBundle {
  var body: some Widget {
    NearbyWalkLiveActivity()
  }
}

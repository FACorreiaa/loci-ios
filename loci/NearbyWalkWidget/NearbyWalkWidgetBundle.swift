import SwiftUI
import WidgetKit

/// The extension that draws Loci's Live Activities: the Near me walk and a trip day.
@main struct NearbyWalkWidgetBundle: WidgetBundle {
  var body: some Widget {
    NearbyWalkLiveActivity()
    TripDayLiveActivity()
  }
}

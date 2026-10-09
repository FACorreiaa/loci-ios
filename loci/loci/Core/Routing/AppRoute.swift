import LociConnectProto
import SwiftUI

/// A page pushed inside a tab. Every tab's stack registers these once at its
/// root (`appRouteDestinations()`), so a page reachable from several tabs
/// (Boards, Recents, a pack) opens the same way from each.
enum AppRoute: Hashable {
  case nearby, compare, gastronomy, packs, boards, trips, settings, contactMatch, facebookFriends
  case pack(slug: String)
  case list(id: String)
  case trip(id: String)
  case recents(RecentsView.Segment)
  case you(YouDestination)
  case user(username: String)
  case sharedTrip(SharedTripSource)
  /// A place snapshot, opened as Saved opens one (a board attachment).
  case savedPlace(Loci_Favorites_V1_FavoriteItem)
  case myReports(RouteRef<ContributeStore>)
  case placeReviews(RouteRef<PlaceReviewsStore>)
  case board(slug: String, from: RouteRef<BoardsFeedStore>)
  case boardPost(id: String, feed: RouteRef<BoardsFeedStore>)
  case sanctions(RouteRef<BoardsFeedStore>)
}

/// The page for an `AppRoute`. Stores are made here, when the page is pushed.
private struct AppRouteDestination: View {
  let route: AppRoute

  var body: some View {
    switch route {
    case .nearby: NearbyView()
    case .compare: CompareView()
    case .gastronomy: GastronomyView()
    case .packs: PacksView()
    case .boards: BoardsHomeView()
    case .trips: TripsView()
    case .settings: SettingsView()
    case .contactMatch: ContactMatchView()
    case .facebookFriends: FacebookFriendsView()
    case .pack(let slug): PackDetailView(slug: slug)
    case .list(let id): ListDetailView(listID: id)
    case .trip(let id): TripEditorView(tripID: id)
    case .recents(let segment): RecentsView(segment: segment)
    case .you(let destination): destination.screen
    case .user(let username): UserProfileView(username: username)
    case .sharedTrip(let source): SharedTripView(source: source)
    case .savedPlace(let item): SavedPlaceDetailView(item: item)
    case .myReports(let contribute): MyReportsView(store: MyReportsStore(service: contribute.object.service))
    case .placeReviews(let reviews): PlaceReviewsListView(store: reviews.object)
    case .board(let slug, let from): BoardView(store: BoardsFeedStore(slug: slug, service: from.object.service))
    case .boardPost(let id, let feed): PostDetailView(store: BoardPostStore(postID: id, feed: feed.object))
    case .sanctions(let feed): SanctionsView(service: feed.object.service)
    }
  }
}

extension View {
  /// Every value a page in any tab can push, registered once at a stack root.
  /// A stack that pushes one of these needs it, or the link does nothing.
  func appRouteDestinations() -> some View {
    navigationDestination(for: AppRoute.self) { AppRouteDestination(route: $0) }
      .navigationDestination(for: SettingsRoute.self) { SettingsRouteDestination(route: $0) }
      .navigationDestination(for: SessionLink.self) { SearchResultsView(link: $0) }
      .navigationDestination(for: ActivityDestination.self) { ActivityDestinationView(destination: $0) }
      .navigationDestination(for: RecentCity.self) { RecentCityView(city: $0) }
  }
}

import LociConnectProto
import SwiftProtobuf
import SwiftUI

/// Three feed items from people you follow, static (a cheer tap here goes to the server).
struct FeedPreview: View {
  @State private var items: [Loci_Social_FeedItem] = Self.sample

  var body: some View {
    List {
      ForEach($items, id: \.id) { FeedItemSection(item: $0) }
    }
    .settingsStyle("People")
  }

  static var sample: [Loci_Social_FeedItem] {
    func person(_ username: String, _ name: String) -> Loci_Social_PublicUser {
      var user = Loci_Social_PublicUser()
      user.id = "preview-\(username)"
      user.username = username
      user.displayName = name
      return user
    }
    var achievement = Loci_Social_FeedItem()
    achievement.id = "f1"
    achievement.kind = .achievementUnlocked
    achievement.actor = person("ana", "Ana Ribeiro")
    achievement.createdAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-3600))
    var summary = Loci_Achievement_AchievementSummary()
    summary.id = "cartographer"
    summary.title = "Cartographer"
    summary.icon = "map"
    summary.kind = .track
    summary.tier = .silver
    achievement.achievement = summary
    achievement.cheerCount = 2
    achievement.cheeredByMe = true

    var city = Loci_Social_FeedItem()
    city.id = "f2"
    city.kind = .newCity
    city.actor = person("tomas", "Tomás Lima")
    city.createdAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-86_400))
    var place = Loci_Social_FeedCity()
    place.cityName = "Porto"
    place.country = "Portugal"
    city.city = place
    city.cheerCount = 1
    city.recentCheerers = [person("joana", "Joana Costa")]

    var trip = Loci_Social_FeedItem()
    trip.id = "f3"
    trip.kind = .tripShared
    trip.actor = person("joana", "Joana Costa")
    trip.createdAt = Google_Protobuf_Timestamp(date: Date().addingTimeInterval(-86_400 * 2))
    var shared = Loci_Social_FeedTrip()
    shared.tripID = "preview-trip"
    shared.title = "Three days in Rome"
    shared.cityName = "Rome"
    shared.days = 3
    trip.trip = shared
    return [achievement, city, trip]
  }
}

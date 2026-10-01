import Foundation
import LociConnectProto

/// Request builders and the file writer for ExportService PDFs (web:
/// lib/api/export.ts). Web maps only what its SelectionItem has; iOS has the
/// full POI, so phone, website, hours and prices travel too.
nonisolated enum PDFExport {
  // MARK: - Results pages

  static func poisRequest(_ stops: [Loci_Poi_POIDetailedInfo], title: String) -> Loci_Export_ExportPOIsRequest {
    var request = Loci_Export_ExportPOIsRequest()
    request.title = title
    request.format = .pdf
    request.pois = stops.map(poi)
    return request
  }

  static func hotelsRequest(_ stops: [Loci_Poi_POIDetailedInfo], title: String, cityName: String) -> Loci_Export_ExportHotelsRequest {
    var request = Loci_Export_ExportHotelsRequest()
    request.title = title
    request.cityName = cityName
    request.format = .pdf
    request.hotels = stops.map { stop in
      var h = Loci_Export_ExportHotel()
      h.id = stop.id
      h.name = stop.name
      h.description_p = copy(stop)
      h.address = stop.address
      h.latitude = stop.latitude
      h.longitude = stop.longitude
      h.rating = stop.rating
      h.starRating = stars(stop.starRating)
      h.priceRange = price(stop)
      h.amenities = list(stop.amenities)
      h.phone = stop.phoneNumber
      h.website = stop.website
      return h
    }
    return request
  }

  static func restaurantsRequest(_ stops: [Loci_Poi_POIDetailedInfo], title: String, cityName: String) -> Loci_Export_ExportRestaurantsRequest {
    var request = Loci_Export_ExportRestaurantsRequest()
    request.title = title
    request.cityName = cityName
    request.format = .pdf
    request.restaurants = stops.map { stop in
      var r = Loci_Export_ExportRestaurant()
      r.id = stop.id
      r.name = stop.name
      r.description_p = copy(stop)
      r.address = stop.address
      r.latitude = stop.latitude
      r.longitude = stop.longitude
      r.rating = stop.rating
      r.cuisineType = stop.cuisineType
      r.priceRange = price(stop)
      r.phone = stop.phoneNumber
      r.website = stop.website
      r.openingHours = hours(stop)
      return r
    }
    return request
  }

  static func activitiesRequest(_ stops: [Loci_Poi_POIDetailedInfo], title: String, cityName: String) -> Loci_Export_ExportActivitiesRequest {
    var request = Loci_Export_ExportActivitiesRequest()
    request.title = title
    request.cityName = cityName
    request.format = .pdf
    request.activities = stops.map { stop in
      var a = Loci_Export_ExportActivity()
      a.id = stop.id
      a.name = stop.name
      a.description_p = copy(stop)
      a.address = stop.address
      a.latitude = stop.latitude
      a.longitude = stop.longitude
      a.rating = stop.rating
      a.category = stop.category
      a.priceRange = price(stop)
      return a
    }
    return request
  }

  // MARK: - Lists

  /// Entries bucket by their content type; itinerary stops are places.
  static func listRequest(_ detail: ListDetail) -> Loci_Export_ExportListRequest {
    var request = Loci_Export_ExportListRequest()
    request.listID = detail.list.id
    request.listName = detail.list.name
    request.format = .pdf
    let hotels = detail.entries.filter { $0.contentType == .hotel }.map(\.stop)
    let restaurants = detail.entries.filter { $0.contentType == .restaurant }.map(\.stop)
    let places = detail.entries.filter { $0.contentType != .hotel && $0.contentType != .restaurant }.map(\.stop)
    request.pois = places.map(poi)
    request.hotels = hotelsRequest(hotels, title: "", cityName: "").hotels
    request.restaurants = restaurantsRequest(restaurants, title: "", cityName: "").restaurants
    return request
  }

  // MARK: - Files

  /// Writes the bytes to a temporary file for `ShareLink`. The server's name
  /// is kept without any path it may carry; an empty PDF is an error.
  static func file(from response: Loci_Export_ExportPDFResponse, fallback: String) throws -> URL {
    guard !response.pdfData.isEmpty else { throw APIError.custom("The PDF came back empty.") }
    let base = response.filename.split(separator: "/").last.map(String.init)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    let name = base.isEmpty || base == "." || base == ".." ? fallback : base
    let url = FileManager.default.temporaryDirectory.appending(path: name)
    try response.pdfData.write(to: url, options: .atomic)
    return url
  }

  /// "loci-sao-paulo-hotels.pdf"
  static func fallbackName(surface: String, cityName: String) -> String {
    let city = cityName.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
      .lowercased()
      .replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
      .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
    return ["loci", city, surface].filter { !$0.isEmpty }.joined(separator: "-") + ".pdf"
  }

  /// The `surface` property on trip_exported, and the file name's last word.
  static func surface(for destination: SearchDestination) -> String {
    switch destination {
    case .hotels: "hotels"
    case .restaurants: "restaurants"
    case .activities: "activities"
    case .itinerary: "itinerary"
    }
  }

  // MARK: - Field helpers

  private static func poi(_ stop: Loci_Poi_POIDetailedInfo) -> Loci_Export_ExportPOI {
    var p = Loci_Export_ExportPOI()
    p.id = stop.id
    p.name = stop.name
    p.category = stop.category
    p.description_p = copy(stop)
    p.address = stop.address
    p.latitude = stop.latitude
    p.longitude = stop.longitude
    p.rating = stop.rating
    p.priceRange = price(stop)
    p.phone = stop.phoneNumber
    p.website = stop.website
    p.openingHours = hours(stop)
    return p
  }

  private static func copy(_ stop: Loci_Poi_POIDetailedInfo) -> String {
    stop.hasDescriptionPoi && !stop.descriptionPoi.isEmpty ? stop.descriptionPoi : stop.description_p
  }

  private static func price(_ stop: Loci_Poi_POIDetailedInfo) -> String {
    stop.priceRange.isEmpty ? stop.priceLevel : stop.priceRange
  }

  /// "Mon: 9–18; Tue: closed", days sorted so the line is stable.
  private static func hours(_ stop: Loci_Poi_POIDetailedInfo) -> String {
    stop.openingHours.sorted { $0.key < $1.key }.map { "\($0.key): \($0.value)" }.joined(separator: "; ")
  }

  /// "4 stars" → 4; anything without a leading number → 0.
  private static func stars(_ raw: String) -> Int32 {
    let digits = raw.trimmingCharacters(in: .whitespaces).prefix { $0.isNumber }
    return Int32(digits) ?? 0
  }

  private static func list(_ raw: String) -> [String] {
    raw.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
  }
}

import Foundation
import LociConnectProto
import Testing

@testable import loci

/// Pass 3, Phase 4: PDFs for results pages and lists (web: lib/api/export.ts).
struct PDFExportTests {
  private func stop(_ id: String, _ name: String, category: String = "", price: String = "", level: String = "", hours: [String: String] = [:]) -> Loci_Poi_POIDetailedInfo {
    var p = Loci_Poi_POIDetailedInfo()
    p.id = id
    p.name = name
    p.category = category
    p.address = "\(name) street 1"
    p.latitude = 38.7
    p.longitude = -9.1
    p.rating = 4.4
    p.priceRange = price
    p.priceLevel = level
    p.openingHours = hours
    p.phoneNumber = "+351 1"
    p.website = "https://x.pt"
    p.descriptionPoi = "poi copy"
    p.description_p = "generic copy"
    return p
  }

  @Test func poisRequestKeepsOrderAndMapsWhatWebMapsAndMore() {
    let stops = [stop("a", "Alpha", category: "museum", price: "€€"), stop("b", "Beta", level: "cheap", hours: ["Mon": "9–18", "Tue": "closed"])]
    let request = PDFExport.poisRequest(stops, title: "Lisbon places")
    #expect(request.title == "Lisbon places")
    #expect(request.format == .pdf)
    #expect(request.pois.map(\.id) == ["a", "b"])
    #expect(request.pois[0].category == "museum")
    #expect(request.pois[0].description_p == "poi copy", "the POI-specific copy wins over the generic one")
    #expect(request.pois[0].priceRange == "€€")
    #expect(request.pois[1].priceRange == "cheap", "price level stands in when there is no range")
    #expect(request.pois[1].openingHours == "Mon: 9–18; Tue: closed", "days sorted, one line")
    #expect(request.pois[0].phone == "+351 1")
    #expect(request.pois[0].website == "https://x.pt")
    #expect(request.pois[0].latitude == 38.7)
  }

  @Test func hotelsParseStarsAndSplitAmenities() {
    var h = stop("h", "Hotel")
    h.starRating = "4 stars"
    h.amenities = "pool, wifi ,  spa"
    let request = PDFExport.hotelsRequest([h], title: "Hotels", cityName: "Lisbon")
    #expect(request.cityName == "Lisbon")
    #expect(request.hotels[0].starRating == 4)
    #expect(request.hotels[0].amenities == ["pool", "wifi", "spa"])
    var none = stop("n", "No stars")
    none.starRating = ""
    #expect(PDFExport.hotelsRequest([none], title: "Hotels", cityName: "").hotels[0].starRating == 0)
  }

  @Test func restaurantsAndActivitiesCarryTheirOwnFields() {
    var r = stop("r", "Tasca", category: "restaurant")
    r.cuisineType = "Portuguese"
    #expect(PDFExport.restaurantsRequest([r], title: "Restaurants", cityName: "Lisbon").restaurants[0].cuisineType == "Portuguese")
    let a = stop("a", "Hike", category: "outdoors")
    #expect(PDFExport.activitiesRequest([a], title: "Activities", cityName: "Lisbon").activities[0].category == "outdoors")
  }

  @Test func listRequestBucketsEntriesByContentType() {
    let list = LociList(id: "l1", name: "Lisbon weekend")
    let entries = [
      ListEntry(itemID: "i1", contentType: .poi, notes: "", stop: stop("p", "Place")),
      ListEntry(itemID: "i2", contentType: .hotel, notes: "", stop: stop("h", "Hotel")),
      ListEntry(itemID: "i3", contentType: .restaurant, notes: "", stop: stop("r", "Tasca")),
      ListEntry(itemID: "i4", contentType: .itinerary, notes: "", stop: stop("x", "Stop")),
    ]
    let request = PDFExport.listRequest(ListDetail(list: list, entries: entries))
    #expect(request.listID == "l1")
    #expect(request.listName == "Lisbon weekend")
    #expect(request.pois.map(\.id) == ["p", "x"], "itinerary stops are places")
    #expect(request.hotels.map(\.id) == ["h"])
    #expect(request.restaurants.map(\.id) == ["r"])
  }

  @Test func fallbackFileNamesAreLowercaseAndSlugged() {
    #expect(PDFExport.fallbackName(surface: "hotels", cityName: "São Paulo") == "loci-sao-paulo-hotels.pdf")
    #expect(PDFExport.fallbackName(surface: "list", cityName: "") == "loci-list.pdf")
  }

  @Test func fileWriterUsesTheServerNameButNeverAPath() throws {
    var response = Loci_Export_ExportPDFResponse()
    response.pdfData = Data([0x25, 0x50, 0x44, 0x46])
    response.filename = "../evil/lisbon-hotels.pdf"
    let url = try PDFExport.file(from: response, fallback: "loci-hotels.pdf")
    #expect(url.lastPathComponent == "lisbon-hotels.pdf")
    #expect(try Data(contentsOf: url) == response.pdfData)
    response.filename = ""
    #expect(try PDFExport.file(from: response, fallback: "loci-hotels.pdf").lastPathComponent == "loci-hotels.pdf")
    response.pdfData = Data()
    #expect(throws: APIError.self) { try PDFExport.file(from: response, fallback: "x.pdf") }
  }

  @Test func surfaceNamesFollowTheDestination() {
    #expect(PDFExport.surface(for: .hotels) == "hotels")
    #expect(PDFExport.surface(for: .restaurants) == "restaurants")
    #expect(PDFExport.surface(for: .activities) == "activities")
    #expect(PDFExport.surface(for: .itinerary) == "itinerary")
  }
}

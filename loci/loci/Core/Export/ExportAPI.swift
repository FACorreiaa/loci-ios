import Connect
import Foundation
import LociConnectProto

/// ExportService, one static func per PDF, each returning a temporary file
/// for `ShareLink`. The itinerary PDF stays in `ResultsAPI.pdf` (Trip Kit).
nonisolated enum ExportAPI {
  private static let client = Loci_Export_ExportServiceClient(client: ConnectTransport.shared.protocolClient)

  /// A results page: the builder follows the destination.
  static func results(_ destination: SearchDestination, stops: [Loci_Poi_POIDetailedInfo], title: String, cityName: String) async throws -> URL {
    let fallback = PDFExport.fallbackName(surface: PDFExport.surface(for: destination), cityName: cityName)
    let response: Loci_Export_ExportPDFResponse
    switch destination {
    case .hotels:
      response = try await rpc("Could not build the PDF.", PDFExport.hotelsRequest(stops, title: title, cityName: cityName)) {
        await client.exportHotelsToPdf(request: $0, headers: [:])
      }
    case .restaurants:
      response = try await rpc("Could not build the PDF.", PDFExport.restaurantsRequest(stops, title: title, cityName: cityName)) {
        await client.exportRestaurantsToPdf(request: $0, headers: [:])
      }
    case .activities:
      response = try await rpc("Could not build the PDF.", PDFExport.activitiesRequest(stops, title: title, cityName: cityName)) {
        await client.exportActivitiesToPdf(request: $0, headers: [:])
      }
    case .itinerary:
      response = try await rpc("Could not build the PDF.", PDFExport.poisRequest(stops, title: title)) {
        await client.exportPoisToPdf(request: $0, headers: [:])
      }
    }
    return try PDFExport.file(from: response, fallback: fallback)
  }

  /// web: exportListToPDF.
  static func list(_ detail: ListDetail) async throws -> URL {
    let response = try await rpc("Could not build the PDF.", PDFExport.listRequest(detail)) {
      await client.exportListToPdf(request: $0, headers: [:])
    }
    return try PDFExport.file(from: response, fallback: PDFExport.fallbackName(surface: "list", cityName: detail.list.name))
  }
}

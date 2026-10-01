import LociConnectProto
import SwiftUI

/// "PDF" on a results page's share row (web: TripExportMenu on results). One
/// tap builds the file; the same spot then offers the system share sheet.
/// Hotels, restaurants, activities and places are free; the itinerary page
/// goes through Trip Kit, which already has its PDF and the day gate.
struct ResultsExportButton: View {
  let destination: SearchDestination
  let stops: [Loci_Poi_POIDetailedInfo]
  let title: String
  let cityName: String
  @Binding var error: String?

  @State private var url: URL?
  @State private var making = false

  var body: some View {
    if let url {
      ShareLink(item: url) { Label("Share PDF", systemImage: "doc.richtext") }
    } else {
      Button(making ? "Building PDF…" : "PDF", systemImage: "doc.richtext") { Task { await make() } }
        .disabled(making || stops.isEmpty)
    }
  }

  private func make() async {
    making = true
    defer { making = false }
    do {
      url = try await ExportAPI.results(destination, stops: stops, title: title, cityName: cityName)
      Analytics.capture(.tripExported, ["format": "pdf", "surface": PDFExport.surface(for: destination), "count": stops.count])
    } catch {
      if !error.isCancellation { self.error = error.userMessage }
    }
  }
}

/// The same for a list's detail page (web: exportListToPDF).
struct ListExportButton: View {
  let detail: ListDetail
  @Binding var error: String?

  @State private var url: URL?
  @State private var making = false

  var body: some View {
    if let url {
      ShareLink(item: url) { Label("Share PDF", systemImage: "doc.richtext") }
    } else {
      Button(making ? "Building PDF…" : "PDF", systemImage: "doc.richtext") { Task { await make() } }
        .disabled(making || detail.entries.isEmpty)
    }
  }

  private func make() async {
    making = true
    defer { making = false }
    do {
      url = try await ExportAPI.list(detail)
      Analytics.capture(.tripExported, ["format": "pdf", "surface": "list", "count": detail.entries.count])
    } catch {
      if !error.isCancellation { self.error = error.userMessage }
    }
  }
}

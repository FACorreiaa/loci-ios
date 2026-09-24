import Foundation
import LociConnectProto

/// Offline sample data for `-designPreview packs`, `packDetail` and
/// `packLocked`. Details go through the same proto mapping the live screen
/// uses, so the preview shows what `PackDetail(_:)` makes of a real response.
nonisolated struct PreviewPacksService: PacksService {
  func list(_ filters: PackFilters) async throws -> PackPage {
    let packs = PackSummary.previewCatalog.filter { pack in
      (filters.theme.map { $0.rawValue == pack.theme } ?? true) && (filters.month.map { pack.months.isEmpty || pack.months.contains($0) } ?? true)
        && (!filters.onlyFree || !pack.isPaid)
    }
    return PackPage(packs: packs, total: packs.count)
  }

  func detail(slug: String) async throws -> PackDetail { PackDetail(slug == PackSummary.previewLocked.slug ? .previewLocked : .previewLisbon) }

  func claim(bundleId: String) async throws -> String { "preview-trip" }
}

nonisolated extension PackSummary {
  static let previewLocked = PackSummary(
    id: "b-porto",
    slug: "porto-winter-wine",
    title: "Port lodges and river light",
    summary: "Three winter days between the Ribeira and Gaia, built around the lodges that still open their cellars.",
    cityName: "Porto",
    theme: "food",
    months: [11, 12, 1, 2],
    dayCount: 3,
    stopCount: 11,
    isPaid: true
  )

  static let previewLisbon = PackSummary(
    id: "b-lisbon",
    slug: "lisbon-tiles-tascas",
    title: "Three slow days of tiles and tascas",
    summary: "Alfama in the morning, Graça at sunset, and the tascas the neighbours keep to themselves.",
    cityName: "Lisbon",
    theme: "local_life",
    months: [4, 5, 6],
    dayCount: 3,
    stopCount: 9
  )

  static let previewSintra = PackSummary(
    id: "b-sintra",
    slug: "sintra-gardens",
    title: "Sintra beyond the palace queue",
    summary: "Gardens, a hill walk and a lunch worth the bus.",
    cityName: "Sintra",
    theme: "outdoors",
    months: [3, 4, 5, 9, 10],
    dayCount: 1,
    stopCount: 5,
    isPaid: true,
    owned: true
  )

  static let previewMadrid = PackSummary(
    id: "b-madrid",
    slug: "madrid-museums",
    title: "The golden triangle, without the fatigue",
    cityName: "Madrid",
    theme: "art",
    dayCount: 2,
    stopCount: 8
  )

  static let previewCatalog = [previewLisbon, previewLocked, previewSintra, previewMadrid]
}

nonisolated extension Loci_Bundle_V1_BundleDetail {
  private static func stop(_ id: String, _ name: String, _ notes: String, _ category: String, _ at: (Double, Double)?, minutes: Int32? = nil)
    -> Loci_Trip_TripStop
  {
    var stop = Loci_Trip_TripStop()
    stop.id = id
    stop.name = name
    stop.notes = notes
    if let minutes { stop.durationMinutes = minutes }
    if let at {
      stop.poiID = "00000000-0000-4000-8000-0000000000\(id.suffix(2))"
      stop.poi.name = name
      stop.poi.category = category
      stop.poi.latitude = at.0
      stop.poi.longitude = at.1
    }
    return stop
  }

  private static func day(_ number: Int32, _ title: String, _ stops: [Loci_Trip_TripStop]) -> Loci_Bundle_V1_BundleDay {
    var day = Loci_Bundle_V1_BundleDay()
    day.dayNumber = number
    day.title = title
    day.stops = stops
    return day
  }

  private static func bundle(_ pack: PackSummary) -> Loci_Bundle_V1_Bundle {
    var bundle = Loci_Bundle_V1_Bundle()
    bundle.id = pack.id
    bundle.slug = pack.slug
    bundle.title = pack.title
    bundle.summary = pack.summary
    bundle.cityName = pack.cityName
    bundle.theme = pack.theme
    bundle.months = pack.months.map(Int32.init)
    bundle.dayCount = Int32(pack.dayCount)
    bundle.stopCount = Int32(pack.stopCount)
    bundle.isPaid = pack.isPaid
    bundle.owned = pack.owned || !pack.isPaid
    return bundle
  }

  /// A free pack: every day, one stop with no position yet.
  static var previewLisbon: Loci_Bundle_V1_BundleDetail {
    var detail = Loci_Bundle_V1_BundleDetail()
    detail.bundle = bundle(PackSummary.previewLisbon)
    detail.days = [
      day(
        1,
        "Alfama before the crowds",
        [
          stop("s01", "Miradouro de Santa Luzia", "Tiles and the river before 9.", "Viewpoint", (38.7115, -9.1300), minutes: 30),
          stop("s02", "Sé de Lisboa", "The cloister dig shows three cities stacked on each other.", "Cathedral", (38.7098, -9.1334), minutes: 45),
          stop("s03", "Tasca do Chico", "Fado after dinner; arrive by 21:00 or stand.", "Restaurant", (38.7131, -9.1440), minutes: 90),
        ]
      ),
      day(
        2,
        "Graça and the tram line",
        [
          stop("s04", "Miradouro da Senhora do Monte", "The highest viewpoint in the old city.", "Viewpoint", (38.7191, -9.1325), minutes: 30),
          stop("s05", "Feira da Ladra", "Tuesday and Saturday flea market.", "Market", (38.7153, -9.1270), minutes: 60),
          stop("s06", "A Voz do Operário", "A workers' hall with a café on the ground floor.", "Cafe", nil),
        ]
      ),
      day(
        3,
        "Belém by the water",
        [
          stop("s07", "Mosteiro dos Jerónimos", "Book the first slot; the queue doubles by 11.", "Monument", (38.6979, -9.2068), minutes: 90),
          stop("s08", "Pastéis de Belém", "Take them to the garden across the road.", "Bakery", (38.6975, -9.2032), minutes: 20),
          stop("s09", "MAAT", "Walk the roof at sunset.", "Museum", (38.6958, -9.1941), minutes: 60),
        ]
      ),
    ]
    return detail
  }

  /// A paid pack nobody on this phone owns: day 1 only, two more locked.
  static var previewLocked: Loci_Bundle_V1_BundleDetail {
    var detail = Loci_Bundle_V1_BundleDetail()
    detail.bundle = bundle(PackSummary.previewLocked)
    let stops = [
      stop("p01", "Cais da Ribeira", "Start on the quay while the boats are still tied up.", "Waterfront", (41.1407, -8.6130), minutes: 30),
      stop("p02", "Ponte Luís I", "Cross on the upper deck for the view back.", "Bridge", (41.1399, -8.6094), minutes: 20),
      stop("p03", "Taylor's", "The tasting room looks over the whole river.", "Wine cellar", (41.1343, -8.6139), minutes: 75),
    ]
    detail.days = [day(1, "Ribeira and the first lodge", stops)]
    detail.lockedDayCount = 2
    return detail
  }
}

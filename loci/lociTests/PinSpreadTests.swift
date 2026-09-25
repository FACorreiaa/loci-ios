import CoreLocation
import MapKit
import Testing

@testable import loci

/// Crowded map pins (pack detail showed 1 under 2 and 7 under 8): pins that
/// would overlap at the current zoom are pushed apart until they touch.
struct PinSpreadTests {
  private func pin(_ id: String, _ lat: Double, _ lon: Double) -> PinSpread.Input {
    PinSpread.Input(id: id, coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
  }

  private func screenDistance(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, scale: Double) -> Double {
    let pa = MKMapPoint(a)
    let pb = MKMapPoint(b)
    return hypot(pa.x - pb.x, pa.y - pb.y) / scale
  }

  /// Lisbon, roughly a 4 km card wide at ~13 map points per screen point.
  private let scale = 40.0

  @Test func pinsWithRoomAreLeftAlone() {
    let pins = [pin("a", 38.71, -9.14), pin("b", 38.72, -9.12)]
    #expect(PinSpread.coordinates(for: pins, mapPointsPerPoint: scale).isEmpty)
  }

  @Test func twoCrowdedPinsEndUpOneDiameterApart() throws {
    let pins = [pin("1", 38.71, -9.14), pin("2", 38.71001, -9.13999), pin("far", 38.75, -9.10)]
    let spread = PinSpread.coordinates(for: pins, mapPointsPerPoint: scale)
    #expect(Set(spread.keys) == ["1", "2"])
    let one = try #require(spread["1"])
    let two = try #require(spread["2"])
    #expect(abs(screenDistance(one, two, scale: scale) - PinSpread.pinDiameter) < 0.5)
    // Pushed along the line between them: 2 stays east of 1.
    #expect(one.longitude < two.longitude)
  }

  @Test func pinsOnTheSameSpotSplitInNumberOrder() throws {
    let pins = [pin("1", 38.71, -9.14), pin("2", 38.71, -9.14)]
    let spread = PinSpread.coordinates(for: pins, mapPointsPerPoint: scale)
    let one = try #require(spread["1"])
    let two = try #require(spread["2"])
    #expect(one.longitude < two.longitude)
    #expect(abs(screenDistance(one, two, scale: scale) - PinSpread.pinDiameter) < 0.5)
  }

  @Test func chainsAreUntangled() {
    // a–b and b–c overlap, a–c does not; pushing b must not leave it on a or c.
    let step = 20.0 * scale  // map points: 20 screen points apart, under the 28-point diameter
    let origin = MKMapPoint(CLLocationCoordinate2D(latitude: 38.71, longitude: -9.14))
    let pins = (0..<3).map { index in
      PinSpread.Input(id: "\(index)", coordinate: MKMapPoint(x: origin.x + step * Double(index), y: origin.y).coordinate)
    }
    let spread = PinSpread.coordinates(for: pins, mapPointsPerPoint: scale)
    let placed = pins.map { spread[$0.id] ?? $0.coordinate }
    for (lhs, rhs) in [(0, 1), (1, 2), (0, 2)] {
      #expect(screenDistance(placed[lhs], placed[rhs], scale: scale) >= PinSpread.pinDiameter - 0.5)
    }
  }

  @Test func zoomingInUntanglesThem() {
    let pins = [pin("1", 38.71, -9.14), pin("2", 38.7103, -9.1403)]
    #expect(!PinSpread.coordinates(for: pins, mapPointsPerPoint: scale).isEmpty)
    #expect(PinSpread.coordinates(for: pins, mapPointsPerPoint: 0.5).isEmpty)
  }

  @Test func fittedScaleCoversTheCard() throws {
    let pins = [pin("a", 38.70, -9.15), pin("b", 38.72, -9.10)]
    let scale = try #require(PinSpread.fittedScale(for: pins, in: CGSize(width: 360, height: 260)))
    let a = MKMapPoint(pins[0].coordinate)
    let b = MKMapPoint(pins[1].coordinate)
    #expect(abs(b.x - a.x) / scale <= 360)
    #expect(PinSpread.fittedScale(for: [pins[0]], in: CGSize(width: 360, height: 260)) == nil)
  }
}

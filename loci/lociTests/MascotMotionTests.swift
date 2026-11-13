import Foundation
import Testing

@testable import loci

// The same cases run in loci-client (src/lib/mascot-motion.test.ts), from a
// byte-identical copy of design/mascot-motion.fixtures.json. Debug and Beta
// only, like the driver.

enum MascotFixtureValue: Decodable {
  case number(Double)
  case text(String)
  case object([String: Double])

  init(from decoder: Decoder) throws {
    let c = try decoder.singleValueContainer()
    if let n = try? c.decode(Double.self) {
      self = .number(n)
    } else if let s = try? c.decode(String.self) {
      self = .text(s)
    } else {
      self = .object(try c.decode([String: Double].self))
    }
  }

  var number: Double {
    if case .number(let n) = self { return n }
    return .nan
  }

  var text: String {
    if case .text(let s) = self { return s }
    return ""
  }
}

struct MascotFixtureCase: Decodable, CustomTestStringConvertible {
  let fn: String
  let args: [String: MascotFixtureValue]
  let expect: MascotFixtureValue

  var testDescription: String { fn }

  func arg(_ name: String) -> Double { args[name]?.number ?? .nan }
}

private struct FixtureFile: Decodable {
  let cases: [MascotFixtureCase]
}

private func loadCases() -> [MascotFixtureCase] {
  guard let url = Bundle.main.url(forResource: "mascot-motion.fixtures", withExtension: "json"),
    let data = try? Data(contentsOf: url),
    let file = try? JSONDecoder().decode(FixtureFile.self, from: data)
  else { return [] }
  return file.cases
}

private let tolerance = 1e-6

struct MascotMotionTests {
  private static let cases = loadCases()

  @Test func fixturesAndMotionAreBundled() throws {
    #expect(!Self.cases.isEmpty)
    let fns = Set(Self.cases.map(\.fn))
    #expect(
      fns == [
        "ease", "sampleTrack", "blinkSeconds", "blinkScale", "blinkWait", "lookToward",
        "approach",
      ])
    #expect(MascotMotion.bundled() != nil)
  }

  @Test(arguments: cases)
  func matchesSharedFixture(_ fixture: MascotFixtureCase) throws {
    let motion = try #require(MascotMotion.bundled())
    switch fixture.fn {
    case "lookToward":
      let look = motion.lookToward(x: fixture.arg("x"), y: fixture.arg("y"))
      guard case .object(let want) = fixture.expect else {
        Issue.record("lookToward expects an object")
        return
      }
      let got = [
        "yawDegrees": look.yawDegrees, "pitchDegrees": look.pitchDegrees,
        "eyeX": look.eyeX, "eyeY": look.eyeY,
      ]
      #expect(Set(got.keys) == Set(want.keys))
      for (key, value) in want {
        #expect(abs((got[key] ?? .nan) - value) < tolerance, "\(key)")
      }
    default:
      let got = try scalar(fixture, motion)
      #expect(abs(got - fixture.expect.number) < tolerance)
    }
  }

  private func scalar(_ fixture: MascotFixtureCase, _ motion: MascotMotion) throws -> Double {
    switch fixture.fn {
    case "ease":
      let easing = try #require(MascotEasing(rawValue: fixture.args["easing"]?.text ?? ""))
      return MascotMotion.ease(easing, fixture.arg("x"))
    case "sampleTrack":
      let state = try #require(motion.states[fixture.args["state"]?.text ?? ""])
      let track = state.tracks[Int(fixture.arg("track"))]
      return MascotMotion.sample(track, at: fixture.arg("t"))
    case "blinkSeconds":
      return motion.blinkSeconds
    case "blinkScale":
      return motion.blinkScale(fixture.arg("s"))
    case "blinkWait":
      return motion.blinkWait(fixture.arg("r"))
    case "approach":
      return MascotMotion.approach(
        fixture.arg("current"),
        fixture.arg("target"),
        dt: fixture.arg("dt"),
        tau: fixture.arg("tau")
      )
    default:
      Issue.record("unknown fixture fn \(fixture.fn)")
      return .nan
    }
  }
}

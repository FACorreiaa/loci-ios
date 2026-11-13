import Foundation

// The 3D mascot's motion driver (BRD-001): time in, values out.
//
// Pure and renderer-free, so the numbers are tested without RealityKit, and so
// the web driver (loci-client `src/lib/mascot-motion.ts`) is held to the same
// answers: both test suites iterate `mascot-motion.fixtures.json`, a
// byte-identical copy of loci-client `design/mascot-motion.fixtures.json`.
//
// Every value is an offset from the rest pose in `mascot-rig.json`. Lengths are
// in mascot heights (the model is one unit tall). Rotation order is YXZ — yaw,
// then pitch, then roll — on both platforms.

nonisolated enum MascotEasing: String, Decodable, Sendable {
  case sine
  case linear
}

nonisolated struct MascotKeyframe: Decodable, Sendable {
  let t: Double
  let v: Double
}

nonisolated struct MascotTrack: Decodable, Sendable {
  let joint: String?
  let material: String?
  let property: String
  let periodSeconds: Double
  let easing: MascotEasing
  let keyframes: [MascotKeyframe]
}

nonisolated struct MascotMotion: Decodable, Sendable {
  struct State: Decodable, Sendable {
    let kind: String
    let tracks: [MascotTrack]
  }

  struct Blink: Decodable, Sendable {
    let joints: [String]
    let property: String
    let open: Double
    let shut: Double
    let intervalSeconds: [Double]
    let closeSeconds: Double
    let holdSeconds: Double
    let openSeconds: Double
  }

  struct LookAt: Decodable, Sendable {
    let joint: String
    let eyes: [String]
    let bodyYawDegrees: Double
    let bodyPitchDegrees: Double
    let eyeOffset: Double
    let timeConstantSeconds: Double
  }

  struct Look: Equatable, Sendable {
    let yawDegrees: Double
    /// Positive looks up.
    let pitchDegrees: Double
    let eyeX: Double
    let eyeY: Double
  }

  let version: Int
  let states: [String: State]
  let blink: Blink
  let lookAt: LookAt

  /// The bundled copy of `design/mascot-motion.json`, or nil if it is missing
  /// or unreadable (the caller keeps the still).
  static func bundled(_ bundle: Bundle = .main) -> MascotMotion? {
    guard let url = bundle.url(forResource: "mascot-motion", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(MascotMotion.self, from: data)
  }

  static func ease(_ easing: MascotEasing, _ x: Double) -> Double {
    let u = clamp(x)
    switch easing {
    case .linear: return u
    case .sine: return (1 - cos(Double.pi * u)) / 2
    }
  }

  /// A looping track's value at `t` seconds. Negative time wraps too.
  static func sample(_ track: MascotTrack, at t: Double) -> Double {
    let kf = track.keyframes
    guard let last = kf.last else { return 0 }
    var phase = t / track.periodSeconds
    phase -= phase.rounded(.down)
    for i in 0..<(kf.count - 1) {
      let a = kf[i]
      let b = kf[i + 1]
      if a.t <= phase && phase <= b.t {
        let u = b.t > a.t ? (phase - a.t) / (b.t - a.t) : 0
        return a.v + (b.v - a.v) * ease(track.easing, u)
      }
    }
    return last.v
  }

  var blinkSeconds: Double {
    blink.closeSeconds + blink.holdSeconds + blink.openSeconds
  }

  /// The eyes' scaleY `s` seconds into a blink; open outside it.
  func blinkScale(_ s: Double) -> Double {
    let b = blink
    if s < 0 || s >= blinkSeconds { return b.open }
    if s < b.closeSeconds {
      return b.open + (b.shut - b.open) * Self.ease(.sine, s / b.closeSeconds)
    }
    if s < b.closeSeconds + b.holdSeconds { return b.shut }
    let u = (s - b.closeSeconds - b.holdSeconds) / b.openSeconds
    return b.shut + (b.open - b.shut) * Self.ease(.sine, u)
  }

  /// Seconds until the next blink, from a uniform random `r` in [0, 1].
  func blinkWait(_ r: Double) -> Double {
    let lo = blink.intervalSeconds.first ?? 4
    let hi = blink.intervalSeconds.last ?? lo
    return lo + (hi - lo) * Self.clamp(r)
  }

  /// Where the mascot wants to look for a pointer at x, y in [-1, 1] (y up).
  func lookToward(x: Double, y: Double) -> Look {
    let cx = Self.clamp(x, -1, 1)
    let cy = Self.clamp(y, -1, 1)
    return Look(
      yawDegrees: cx * lookAt.bodyYawDegrees,
      pitchDegrees: cy * lookAt.bodyPitchDegrees,
      eyeX: cx * lookAt.eyeOffset,
      eyeY: cy * lookAt.eyeOffset
    )
  }

  /// Exponential approach with time constant `tau`; `tau <= 0` snaps.
  static func approach(_ current: Double, _ target: Double, dt: Double, tau: Double) -> Double {
    if tau <= 0 { return target }
    return current + (target - current) * (1 - exp(-dt / tau))
  }

  static func clamp(_ x: Double, _ lo: Double = 0, _ hi: Double = 1) -> Double {
    min(hi, max(lo, x))
  }
}

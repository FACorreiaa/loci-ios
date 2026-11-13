import RealityKit
import SwiftUI
import UIKit

/// The Loci mascot in 3D (BRD-001; loci-client DESIGN.md and
/// docs/MASCOT_3D.md). It breathes, its amber rings pulse, it blinks, and it turns toward a finger
/// or pointer over it. The arithmetic is `MascotMotion`, held to the web's answers by shared
/// fixtures.
///
/// The still is rendered by RealityKit from the same model at its rest pose
/// (scripts/render-mascot-still.sh). It shows until the model's first frame, and stays under
/// Reduce Motion, in Low Power Mode, and when the model or its data cannot be read.
struct Mascot3DView: View {
  /// Where a finger or pointer is, in global coordinates. Nil: the mascot looks ahead.
  var pointer: CGPoint?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var stage = MascotStage()
  @State private var frame = CGRect.zero
  @State private var lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled

  private var draws: Bool { !reduceMotion && !lowPower }

  var body: some View {
    ZStack {
      still
        .opacity(draws && stage.isLive ? 0 : 1)
      if draws {
        MascotScene(stage: stage)
          .opacity(stage.isLive ? 1 : 0)
      }
    }
    .aspectRatio(MascotStage.aspect, contentMode: .fit)
    .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
    .onChange(of: pointer) { _, point in stage.look(at: point, from: frame) }
    .onReceive(NotificationCenter.default.publisher(for: .NSProcessInfoPowerStateDidChange)) { _ in
      lowPower = ProcessInfo.processInfo.isLowPowerModeEnabled
    }
    .animation(reduceMotion ? LociTheme.reducedFade : LociTheme.resultArrive, value: stage.isLive)
    .accessibilityElement(children: .ignore)
    .accessibilityLabel("The Loci mascot, a coral figure in white trainers with a small backpack")
    .accessibilityAddTraits(.isImage)
  }

  @ViewBuilder private var still: some View {
    if let image = UIImage(named: "mascot-3d-still") {
      Image(uiImage: image).resizable().scaledToFit()
    } else {
      Image("LociMascot").resizable().scaledToFit()
    }
  }
}

extension View {
  /// Reports where a finger or pointer is over this view, in global coordinates, for a
  /// `Mascot3DView` to look at. Taps and scrolling go on as before.
  func mascotFollows(_ pointer: Binding<CGPoint?>) -> some View {
    onContinuousHover(coordinateSpace: .global) { phase in
      switch phase {
      case .active(let point): pointer.wrappedValue = point
      case .ended: pointer.wrappedValue = nil
      }
    }
    .simultaneousGesture(
      DragGesture(minimumDistance: 0, coordinateSpace: .global)
        .onChanged { pointer.wrappedValue = $0.location }
        .onEnded { _ in pointer.wrappedValue = nil }
    )
  }
}

/// The RealityKit view: a virtual camera, no AR. Its background is clear, so the mascot stands on
/// whatever SwiftUI draws behind it.
private struct MascotScene: View {
  let stage: MascotStage
  /// Held at the rest pose: no frame updates (the still capture).
  var frozen = false

  var body: some View {
    RealityView { content in
      content.camera = .virtual
      guard let mascot = await stage.load() else { return }
      content.add(mascot)
      for entity in stage.rig {
        content.add(entity)
      }
      guard !frozen else { return }
      stage.updates = content.subscribe(to: SceneEvents.Update.self) { event in
        stage.step(event.deltaTime)
      }
    }
    .allowsHitTesting(false)
  }
}

/// The mascot at its rest pose, 240 × 320 points (720 × 960 pixels at 3x) in the middle of the
/// screen, over a flat colour. scripts/render-mascot-still.sh photographs it over black and over
/// white and recovers the transparency from the difference. Reached only through DesignPreview,
/// which is Debug only.
struct MascotStillCapture: View {
  let background: Color
  @State private var stage = MascotStage()

  var body: some View {
    ZStack {
      background.ignoresSafeArea()
      MascotScene(stage: stage, frozen: true).frame(width: 240, height: 320)
    }
    // Centred on the whole screen, not the safe area, so the script can find it.
    .ignoresSafeArea()
    .statusBarHidden()
  }
}

/// The camera framing from `mascot-rig.json` (written by loci-client tools/brand/mascot_3d.py).
private struct MascotRig: Decodable {
  struct Camera: Decodable {
    let fovDegrees: Float
    let target: [Float]
    let distance: Float
  }

  let camera: Camera

  static func bundled() -> MascotRig? {
    guard let url = Bundle.main.url(forResource: "mascot-rig", withExtension: "json"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return try? JSONDecoder().decode(MascotRig.self, from: data)
  }
}

/// The loaded mascot and its motion: joints found by name, moved each frame by `MascotMotion`.
/// The composition matches the web's (loci-client `src/lib/mascot3d/scene.ts`).
@MainActor @Observable
final class MascotStage {
  /// The still's shape (720 × 960), so the swap to the model does not move the layout.
  static let aspect: CGFloat = 3.0 / 4.0
  /// A frame that took longer (the app coming back) moves the mascot this far and no further.
  private static let longestStep = 0.1

  /// The first frame is drawn: the still can go.
  private(set) var isLive = false
  @ObservationIgnored var updates: EventSubscription?
  /// The camera and the lights, made with the mascot.
  @ObservationIgnored private(set) var rig: [Entity] = []

  private struct Joint {
    let entity: Entity
    let position: SIMD3<Float>
    let orientation: simd_quatf
    let scale: SIMD3<Float>
  }

  private struct Glow {
    let entity: Entity
    let material: PhysicallyBasedMaterial
    var scale = 1.0
  }

  private struct Look {
    var yaw = 0.0
    var pitch = 0.0
    var eyeX = 0.0
    var eyeY = 0.0
  }

  @ObservationIgnored private var motion: MascotMotion?
  @ObservationIgnored private var tracks: [MascotTrack] = []
  @ObservationIgnored private var joints: [String: Joint] = [:]
  @ObservationIgnored private var glows: [String: [Glow]] = [:]
  @ObservationIgnored private var look = Look()
  @ObservationIgnored private var target = Look()
  @ObservationIgnored private var seconds = 0.0
  @ObservationIgnored private var blinkAt = 0.0

  /// Reads the model, motion and rig from the bundle and poses the mascot at rest. Nil when any is
  /// missing: the still stays.
  func load() async -> Entity? {
    guard let motion = MascotMotion.bundled(), let framing = MascotRig.bundled(),
      let model = try? await Entity(named: "Mascot", in: .main)
    else { return nil }
    // The file wraps the rig in an entity of its own: start below it.
    let root = model.findEntity(named: "Root") ?? model
    let tracks = motion.states["standing"]?.tracks ?? []
    let names = Set(tracks.compactMap(\.joint) + motion.blink.joints + motion.lookAt.eyes)
      .union([motion.lookAt.joint])
    for name in names {
      guard let entity = root.findEntity(named: name) else { continue }
      joints[name] = Joint(
        entity: entity,
        position: entity.position,
        orientation: entity.orientation,
        scale: entity.scale
      )
    }
    for material in Set(tracks.compactMap(\.material)) {
      glows[material] = parts(drawnIn: material, under: root)
    }
    self.motion = motion
    self.tracks = tracks
    blinkAt = motion.blinkWait(.random(in: 0...1))
    rig = [
      camera(framing.camera),
      // The web's key and rim, in its 1.6 : 1.4 ratio, from the dark-appearance tokens.
      light(.lociLantern, intensity: 2000, from: [1.5, 2.5, 3]),
      light(.lociHolo, intensity: 1750, from: [-2, 1.5, -2]),
    ]
    step(0)
    return model
  }

  /// Looks toward `point`, given where the mascot is on screen. A finger is followed only over the
  /// mascot (the form stays untouched), so its edge is the whole of the turn.
  func look(at point: CGPoint?, from frame: CGRect) {
    guard let motion, let point, !frame.isEmpty else {
      target = Look()
      return
    }
    let reach = max(frame.width, frame.height) / 2
    let want = motion.lookToward(x: (point.x - frame.midX) / reach, y: (frame.midY - point.y) / reach)
    target = Look(yaw: want.yawDegrees, pitch: want.pitchDegrees, eyeX: want.eyeX, eyeY: want.eyeY)
  }

  /// One frame: the tracks, the look and the blink, each added to the rest pose.
  func step(_ elapsed: TimeInterval) {
    guard let motion else { return }
    let delta = min(elapsed, Self.longestStep)
    seconds += delta
    let tau = motion.lookAt.timeConstantSeconds
    look.yaw = MascotMotion.approach(look.yaw, target.yaw, dt: delta, tau: tau)
    look.pitch = MascotMotion.approach(look.pitch, target.pitch, dt: delta, tau: tau)
    look.eyeX = MascotMotion.approach(look.eyeX, target.eyeX, dt: delta, tau: tau)
    look.eyeY = MascotMotion.approach(look.eyeY, target.eyeY, dt: delta, tau: tau)

    if seconds >= blinkAt + motion.blinkSeconds {
      blinkAt = seconds + motion.blinkWait(.random(in: 0...1))
    }
    let lid = Float(motion.blinkScale(seconds - blinkAt))

    var lift: [String: Double] = [:]
    for track in tracks {
      let value = MascotMotion.sample(track, at: seconds)
      if let material = track.material, track.property == "emissiveScale" {
        glow(material, scale: value)
      } else if let name = track.joint, track.property == "translateY" {
        lift[name, default: 0] += value
      }
    }

    for (name, joint) in joints {
      var position = joint.position
      position.y += Float(lift[name] ?? 0)
      var orientation = joint.orientation
      var scale = joint.scale
      if name == motion.lookAt.joint {
        // Yaw, then pitch: the web's YXZ order. Positive pitch looks up, so it turns about -X.
        orientation =
          orientation * turn(look.yaw, about: [0, 1, 0]) * turn(-look.pitch, about: [1, 0, 0])
      }
      if motion.lookAt.eyes.contains(name) {
        position.x += Float(look.eyeX)
        position.y += Float(look.eyeY)
      }
      if motion.blink.joints.contains(name) {
        scale.y *= lid
      }
      joint.entity.position = position
      joint.entity.orientation = orientation
      joint.entity.scale = scale
    }
    if delta > 0 {
      isLive = true
    }
  }

  private func turn(_ degrees: Double, about axis: SIMD3<Float>) -> simd_quatf {
    simd_quatf(angle: Float(degrees * .pi / 180), axis: axis)
  }

  /// The parts drawn in `material`: the model names each mesh "<joint>_<material>".
  private func parts(drawnIn material: String, under root: Entity) -> [Glow] {
    var found: [Glow] = []
    var queue = [root]
    while let entity = queue.popLast() {
      queue.append(contentsOf: entity.children)
      guard entity.name.hasSuffix("_" + material),
        let rest = entity.components[ModelComponent.self]?.materials.first
          as? PhysicallyBasedMaterial
      else { continue }
      found.append(Glow(entity: entity, material: rest))
    }
    return found
  }

  /// Brightens or dims a material's own light around its rest. A change too small to see is not
  /// sent to the renderer.
  private func glow(_ material: String, scale: Double) {
    guard var parts = glows[material] else { return }
    for index in parts.indices where abs(parts[index].scale - scale) > 0.01 {
      parts[index].scale = scale
      var lit = parts[index].material
      lit.emissiveIntensity *= Float(scale)
      parts[index].entity.components[ModelComponent.self]?.materials = [lit]
    }
    glows[material] = parts
  }

  /// The web's camera: the mascot is one unit tall and stands on the origin.
  private func camera(_ framing: MascotRig.Camera) -> Entity {
    let entity = Entity()
    var lens = PerspectiveCameraComponent()
    lens.fieldOfViewInDegrees = framing.fovDegrees
    entity.components.set(lens)
    let target = framing.target + [0, 0.5, 0].dropFirst(framing.target.count)
    let aim = SIMD3<Float>(target[0], target[1], target[2])
    entity.look(at: aim, from: aim + [0, 0, framing.distance], relativeTo: nil)
    return entity
  }

  /// A brand light. Both lights take the dark-appearance (bright) value of their token in both
  /// appearances, as the web does.
  private func light(_ token: Color, intensity: Float, from position: SIMD3<Float>) -> Entity {
    let entity = Entity()
    let tint = UIColor(token).resolvedColor(with: UITraitCollection(userInterfaceStyle: .dark))
    entity.components.set(DirectionalLightComponent(color: tint, intensity: intensity))
    entity.look(at: [0, 0.5, 0], from: position, relativeTo: nil)
    return entity
  }
}

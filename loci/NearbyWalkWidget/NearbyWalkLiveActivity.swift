import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island for a Near me walk: steps, distance, how
/// many places are fenced, and the closest one. The extension cannot see the
/// app's theme, so the three brand colours are written here (NATIVE_DESIGN §1).
struct NearbyWalkLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: NearbyWalkAttributes.self) { context in
      LockScreenView(state: context.state, attributes: context.attributes)
        .activityBackgroundTint(Palette.paper)
        .activitySystemActionForegroundColor(Palette.forest)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(context.state.stepsText, systemImage: "figure.walk").font(.headline).foregroundStyle(Palette.ink)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.distanceText).font(.headline).foregroundStyle(Palette.ink)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if let nearest = context.state.nearestText {
            Label(nearest, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(Palette.terracotta).lineLimit(1)
          } else {
            Text("\(context.state.placesNearby) places within \(context.attributes.radiusKm) km").font(.subheadline).foregroundStyle(.secondary)
          }
        }
      } compactLeading: {
        Image(systemName: "figure.walk").foregroundStyle(Palette.terracotta)
      } compactTrailing: {
        Text(context.state.steps.formatted(.number)).font(.caption.monospacedDigit()).contentTransition(.numericText())
      } minimal: {
        Image(systemName: "figure.walk").foregroundStyle(Palette.terracotta)
      }
    }
  }
}

private struct LockScreenView: View {
  let state: NearbyWalkAttributes.ContentState
  let attributes: NearbyWalkAttributes

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        Label("Near me walk", systemImage: "figure.walk").font(.caption.weight(.medium)).foregroundStyle(Palette.forest)
        Spacer()
        Text(attributes.startedAt, style: .timer).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
      }
      HStack(alignment: .firstTextBaseline, spacing: 16) {
        VStack(alignment: .leading, spacing: 2) {
          Text(state.steps.formatted(.number)).font(.title.weight(.semibold)).foregroundStyle(Palette.ink).contentTransition(.numericText())
          Text("steps").font(.caption).foregroundStyle(.secondary)
        }
        VStack(alignment: .leading, spacing: 2) {
          Text(state.distanceText).font(.title.weight(.semibold)).foregroundStyle(Palette.ink).contentTransition(.numericText())
          Text("walked").font(.caption).foregroundStyle(.secondary)
        }
        Spacer()
        VStack(alignment: .trailing, spacing: 2) {
          Text("\(state.placesNearby)").font(.title.weight(.semibold)).foregroundStyle(Palette.ink)
          Text("places").font(.caption).foregroundStyle(.secondary)
        }
      }
      if let nearest = state.nearestText {
        Label(nearest, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(Palette.terracotta).lineLimit(1)
      }
    }
    .padding(16)
  }
}

/// NATIVE_DESIGN light tokens. The Lock Screen tints the background itself.
enum Palette {
  static let paper = Color(red: 0.961, green: 0.941, blue: 0.902)
  static let ink = Color(red: 0.102, green: 0.180, blue: 0.149)
  static let forest = Color(red: 0.129, green: 0.302, blue: 0.235)
  static let terracotta = Color(red: 0.780, green: 0.420, blue: 0.290)
}

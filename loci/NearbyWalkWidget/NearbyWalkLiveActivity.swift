import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen and Dynamic Island for a walk (Near me, or a day stop by stop): steps, distance, how
/// many places are fenced, and the closest one (or, when following a route,
/// the place being walked to). The extension cannot see the
/// app's theme, so the brand colours are written here (NATIVE_DESIGN §1).
struct NearbyWalkLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: NearbyWalkAttributes.self) { context in
      LockScreenView(state: context.state, attributes: context.attributes)
        // The tint is always obsidian, so `.secondary` must resolve against dark.
        .environment(\.colorScheme, .dark)
        .activityBackgroundTint(Palette.ground)
        .activitySystemActionForegroundColor(Palette.primary)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          Label(context.state.stepsText, systemImage: "figure.walk").font(.headline).foregroundStyle(.white)
        }
        DynamicIslandExpandedRegion(.trailing) {
          Text(context.state.distanceText).font(.headline).foregroundStyle(.white)
        }
        DynamicIslandExpandedRegion(.bottom) {
          if let destination = context.state.routeText {
            Label(destination, systemImage: "arrow.triangle.turn.up.right.diamond.fill")
              .font(.subheadline).foregroundStyle(Palette.holo).lineLimit(1)
          } else if let nearest = context.state.nearestText {
            Label(nearest, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(Palette.lantern).lineLimit(1)
          } else {
            Text(context.attributes.title ?? "\(context.state.placesNearby) places within \(context.attributes.radiusKm) km")
              .font(.subheadline).foregroundStyle(.secondary)
          }
        }
      } compactLeading: {
        Image(systemName: "figure.walk").foregroundStyle(Palette.lantern)
      } compactTrailing: {
        Text(context.state.steps.formatted(.number)).font(.caption.monospacedDigit()).contentTransition(.numericText())
      } minimal: {
        Image(systemName: "figure.walk").foregroundStyle(Palette.lantern)
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
        Label(attributes.title ?? "Near me walk", systemImage: "figure.walk").font(.caption.weight(.medium)).foregroundStyle(Palette.primary)
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
        if state.placesNearby > 0 || attributes.title == nil {
          VStack(alignment: .trailing, spacing: 2) {
            Text("\(state.placesNearby)").font(.title.weight(.semibold)).foregroundStyle(Palette.ink)
            Text("places").font(.caption).foregroundStyle(.secondary)
          }
        }
      }
      if let destination = state.routeText {
        Label(destination, systemImage: "arrow.triangle.turn.up.right.diamond.fill")
          .font(.subheadline.weight(.medium)).foregroundStyle(Palette.primary).lineLimit(1)
      } else if let nearest = state.nearestText {
        Label(nearest, systemImage: "mappin.and.ellipse").font(.subheadline).foregroundStyle(Palette.lantern).lineLimit(1)
      }
    }
    .padding(16)
  }
}

/// NATIVE_DESIGN dark tokens (LociTheme.swift, same sRGB). The Lock Screen is
/// obsidian like the app's dark-first ground; the Dynamic Island is always
/// black, so it shares the same light-on-dark colours.
enum Palette {
  /// obsidian
  static let ground = Color(red: 0.067, green: 0.086, blue: 0.114)
  /// cream
  static let ink = Color(red: 0.969, green: 0.945, blue: 0.914)
  /// signal coral, 6.8:1 on obsidian
  static let primary = Color(red: 0.957, green: 0.482, blue: 0.365)
  /// lantern: the nearest place, a discovery
  static let lantern = Color(red: 0.984, green: 0.733, blue: 0.494)
  /// holo: the route being walked
  static let holo = Color(red: 0.478, green: 0.612, blue: 0.761)
}

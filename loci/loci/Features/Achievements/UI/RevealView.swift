import LociConnectProto
import SwiftUI

/// The one-time "You've already earned N achievements" (web: RevealDialog):
/// what the backfill found from before achievements existed. Closing it marks
/// them seen on every device.
struct RevealView: View {
  let count: Int
  let achievements: [Loci_Achievement_Achievement]
  @Environment(\.dismiss) private var dismiss
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var appeared = false

  var body: some View {
    NavigationStack {
      ScrollView {
        VStack(spacing: 20) {
          Image(systemName: "rosette").font(.system(size: 44)).foregroundStyle(Color.lociCoral)
          Text("You've already earned ^[\(count) achievement](inflect: true)")
            .font(.lociDisplay(26)).foregroundStyle(Color.lociInk).multilineTextAlignment(.center)
          Text("Everything you did before achievements arrived counted. Here's what you have.")
            .font(.lociCaption(15)).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.center)
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 14)], spacing: 16) {
            ForEach(Array(achievements.enumerated()), id: \.element.id) { index, achievement in
              VStack(spacing: 6) {
                MedallionView(achievement, size: 56)
                Text(achievement.label).font(.lociCaption(12)).foregroundStyle(Color.lociInk).multilineTextAlignment(.center).lineLimit(2)
              }
              .scaleEffect(appeared || reduceMotion ? 1 : 0.6)
              .opacity(appeared || reduceMotion ? 1 : 0)
              .animation(reduceMotion ? nil : .spring(duration: 0.45).delay(Double(min(index, 12)) * 0.05), value: appeared)
              .accessibilityElement(children: .combine)
            }
          }
          Button("See them all") { dismiss() }
            .buttonStyle(.borderedProminent).tint(.lociCoralFill)
        }
        .padding(24)
      }
      .background(Color.lociPaper.ignoresSafeArea())
      .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } } }
    }
    .sensoryFeedback(.success, trigger: appeared)
    .onAppear {
      appeared = true
      Analytics.capture(.achievementsRevealed, ["count": count])
    }
  }
}

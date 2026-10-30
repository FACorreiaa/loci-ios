import LociConnectProto
import SwiftUI

/// "How was it?" then "Better or worse than Y?" until the place is placed in
/// the traveller's list for its city (web: components/ranking/HowWasIt.tsx).
/// Skip ends it early; the place stays at the bottom of its bucket.
struct HowWasItCard: View {
  let pending: PendingRating
  var service: any RankingService = ConnectRankingService()
  let onFinish: () -> Void

  private enum Step {
    case verdict
    case compare(Loci_Ranking_RankedPlace, Loci_Ranking_Comparison)
    case done(Loci_Ranking_RankedPlace)
  }

  @State private var step = Step.verdict
  @State private var busy = false
  @State private var error: String?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      HStack(alignment: .firstTextBaseline) {
        Text(title).font(.lociHeadline(16)).foregroundStyle(Color.lociInk)
        Spacer(minLength: 8)
        Button("Close", systemImage: "xmark", action: onFinish)
          .labelStyle(.iconOnly).foregroundStyle(Color.lociMutedInk)
      }
      buttons.disabled(busy)
      if let error { Text(error).font(.lociCaption(12)).foregroundStyle(Color.lociDestructive) }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .lociCard(padding: 0)
    .accessibilityElement(children: .contain)
  }

  private var title: String {
    switch step {
    case .verdict: HowWasItCopy.prompt(pending.name)
    case .compare(_, let other): HowWasItCopy.compare(other.name)
    case .done(let place): HowWasItCopy.done(place)
    }
  }

  @ViewBuilder private var buttons: some View {
    switch step {
    case .verdict:
      HStack {
        ForEach(RankingVerdict.allCases, id: \.self) { verdict in
          Button(verdict.label) { Task { await rate(verdict) } }.buttonStyle(.bordered)
        }
      }
    case .compare(_, let other):
      HStack {
        Button("Better") { Task { await compare(other, better: true) } }.buttonStyle(.bordered)
        Button("Worse") { Task { await compare(other, better: false) } }.buttonStyle(.bordered)
        Button("Skip", action: onFinish).foregroundStyle(Color.lociMutedInk)
      }
    case .done:
      Button("Done", action: onFinish).buttonStyle(.borderedProminent).tint(.lociForest)
    }
  }

  private func rate(_ verdict: RankingVerdict) async {
    await run { try await service.rate(pending, verdict: verdict) }
  }

  private func compare(_ other: Loci_Ranking_Comparison, better: Bool) async {
    await run { try await service.compare(poiID: pending.poiID, otherID: other.poiID, better: better) }
  }

  private func run(_ call: () async throws -> RankingStep) async {
    busy = true
    error = nil
    defer { busy = false }
    do {
      let result = try await call()
      if let next = result.next {
        step = .compare(result.place, next)
      } else {
        step = .done(result.place)
      }
    } catch {
      self.error = "Couldn't save that — try again."
    }
  }
}

/// The "How was it?" card for whatever is due, over the whole app.
struct RatePromptOverlay: View {
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Bindable private var prompter = RatePrompter.shared

  var body: some View {
    if let pending = prompter.current {
      HowWasItCard(pending: pending) {
        withAnimation(reduceMotion ? LociTheme.reducedFade : LociTheme.selectionSettle) { prompter.resolve(poiID: pending.poiID) }
      }
      .id(pending.poiID)
      .padding(.horizontal, 16)
      .padding(.bottom, 64)
      .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }
  }
}

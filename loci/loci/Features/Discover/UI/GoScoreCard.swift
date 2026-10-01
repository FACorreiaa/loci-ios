import SwiftUI

/// "Should I go this weekend?" for where the traveller is standing. The score
/// and verdict lead; the factors fold under a tap so the number is never the
/// only thing on screen for long.
struct GoScoreCard: View {
  let model: GoScoreModel
  var cityName = ""
  @State private var expanded = false

  private var tint: Color {
    switch model.tone {
    case .go: Color.lociForest
    case .skip: Color.red
    case .maybe: Color.lociInk
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        withAnimation(.snappy) { expanded.toggle() }
      } label: {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
          VStack(alignment: .leading, spacing: 2) {
            Text(cityName.isEmpty ? "GoScore" : "GoScore · \(cityName)").lociCoordStyle(10)
            Text(model.label).font(.lociBody(15).weight(.semibold)).foregroundStyle(tint)
            if !model.summary.isEmpty {
              Text(model.summary).font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).multilineTextAlignment(.leading)
            }
          }
          Spacer(minLength: 8)
          Text("\(model.score)").font(.lociTitle(28)).monospacedDigit().foregroundStyle(tint)
          if !model.factorRows.isEmpty {
            Image(systemName: "chevron.down").rotationEffect(.degrees(expanded ? 180 : 0)).foregroundStyle(Color.lociMutedInk)
          }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel("GoScore \(model.score), \(model.label)")
      .accessibilityHint(model.factorRows.isEmpty ? "" : (expanded ? "Hides the factors" : "Shows the factors"))

      if expanded {
        VStack(alignment: .leading, spacing: 8) {
          ForEach(model.factorRows) { row in factorView(row) }
        }
      }
      if let note = model.estimatedNote {
        Label(note, systemImage: "info.circle").font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
      }
    }
    .padding(14)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(tint.opacity(model.tone == .maybe ? 0.05 : 0.1), in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
    .overlay(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).stroke(tint.opacity(0.35)))
  }

  private func factorView(_ row: GoScoreModel.FactorRow) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(row.label).font(.lociCaption(13).weight(.medium)).foregroundStyle(Color.lociInk)
        Spacer()
        Text(row.valueText).font(.lociCaption(12)).monospacedDigit().foregroundStyle(row.isNegative ? Color.red : Color.lociMutedInk)
      }
      if let share = row.share {
        GeometryReader { geo in
          ZStack(alignment: .leading) {
            Capsule().fill(Color.lociMuted)
            Capsule().fill(tint).frame(width: geo.size.width * share)
          }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
      }
      if !row.detail.isEmpty {
        Text(row.detail).font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

/// web: TripMoney's fuel line, under "Travel between cities".
struct DriveCostRow: View {
  let model: DriveCostModel

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      HStack(alignment: .firstTextBaseline, spacing: 6) {
        Text(model.line).font(.lociBody(14).weight(.medium)).monospacedDigit()
        Text(model.detail).lociCoordStyle(10)
      }
      if !model.assumptions.isEmpty {
        Text(model.assumptions).font(.lociCaption(11)).foregroundStyle(Color.lociMutedInk)
      }
    }
    .accessibilityElement(children: .combine)
  }
}

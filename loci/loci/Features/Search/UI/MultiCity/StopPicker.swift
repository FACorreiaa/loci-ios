import SwiftUI

/// The cities of a multi-city trip as chips: pick one, or every day (nil).
struct StopPicker: View {
  let stops: [StopResult]
  @Binding var selection: Int?

  var body: some View {
    ScrollView(.horizontal, showsIndicators: false) {
      HStack(spacing: 8) {
        chip("All days", selected: selection == nil) { selection = nil }
        ForEach(stops, id: \.index) { stop in
          Image(systemName: "arrow.right").font(.caption2).foregroundStyle(.secondary)
          chip(MultiCityFormat.chip(stop), selected: selection == stop.index, stop: stop) { selection = stop.index }
        }
      }
      .padding(.vertical, 2)
    }
  }

  private func chip(_ title: String, selected: Bool, stop: StopResult? = nil, action: @escaping () -> Void) -> some View {
    Button(action: action) {
      HStack(spacing: 6) {
        Text(title).font(.subheadline.weight(.medium))
        if let stop, stop.error != nil {
          Image(systemName: "exclamationmark.triangle.fill").font(.caption).accessibilityLabel("This city failed")
        } else if let stop, stop.state.phase != .done, !stop.state.hasResult {
          ProgressView().controlSize(.mini).accessibilityLabel("Still planning")
        }
      }
      .padding(.horizontal, 12).padding(.vertical, 7)
      .background(selected ? Color.lociForest : Color.lociCard, in: Capsule())
      .foregroundStyle(selected ? Color.lociPaper : Color.primary)
      .overlay(Capsule().stroke(Color.lociBorder, lineWidth: selected ? 0 : 1))
    }
    .buttonStyle(.plain)
    .accessibilityAddTraits(selected ? .isSelected : [])
  }
}

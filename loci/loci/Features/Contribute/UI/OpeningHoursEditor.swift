import SwiftUI

/// Seven rows, one per day, each open for a span or marked closed (web:
/// OpeningHoursPicker). The canonical string the week encodes to is shown
/// live, because that string is what gets compared with another scout's.
struct OpeningHoursEditor: View {
  @Binding var hours: OpeningHours
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      ForEach(HoursDay.allCases) { day in
        row(day)
        if let problem = hours.problem(day) {
          Text(problem).font(.lociCaption(12)).foregroundStyle(Color.lociDestructive).accessibilityLabel("\(day.label): \(problem)")
        }
        if day != .sun { Divider().overlay(Color.lociBorder.opacity(0.5)) }
      }
      Text("Sent as: \(hours.encoded)")
        .font(.lociCoord(10))
        .foregroundStyle(Color.lociMutedInk)
        .textSelection(.enabled)
        .padding(.top, 6)
        .accessibilityLabel("Sent as \(hours.encoded)")
    }
    .environment(\.timeZone, .gmt)
  }

  private func row(_ day: HoursDay) -> some View {
    HStack(spacing: 6) {
      Text(day.label.prefix(3))
        .font(.lociBody(15).weight(.medium))
        .foregroundStyle(Color.lociInk)
        .frame(minWidth: 40, alignment: .leading)
        .accessibilityLabel(day.label)
      if hours[day].isClosed {
        Text("Closed").font(.lociBody(15)).foregroundStyle(Color.lociMutedInk)
      } else {
        time(day, start: true)
        Text("to").font(.lociCaption(12)).foregroundStyle(Color.lociMutedInk).accessibilityHidden(true)
        time(day, start: false)
      }
      Spacer(minLength: 4)
      Button {
        withAnimation(reduceMotion ? nil : .snappy) { hours.toggleClosed(day) }
      } label: {
        // The bordered style adds 7pt above and below: 30 + 14 reaches the 44pt tap target.
        Text(hours[day].isClosed ? "Set hours" : "Closed").frame(minHeight: LociTheme.minTapTarget - 14)
      }
      .font(.lociCaption(13).weight(.semibold))
      .buttonStyle(.bordered)
      .tint(Color.lociForest)
      .accessibilityHint(hours[day].isClosed ? "Opens \(day.label) 09:00 to 17:00" : "Marks \(day.label) closed")
    }
    .frame(minHeight: LociTheme.minTapTarget)
  }

  private func time(_ day: HoursDay, start: Bool) -> some View {
    DatePicker(
      start ? "\(day.label) opening time" : "\(day.label) closing time",
      selection: $hours[clock: day, start: start],
      displayedComponents: .hourAndMinute
    )
    .labelsHidden()
    .environment(\.locale, Locale(identifier: "en_GB"))
  }
}

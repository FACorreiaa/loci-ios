import SwiftUI

/// Several cities in one trip: add them, give each its nights, put them in
/// order, or let Loci order them. Typing "Lisbon for 3 days then Porto for 2"
/// does the same from the composer; this is for people who would rather not.
struct StopBuilderSheet: View {
  /// The most cities one trip plans — the server's cap.
  static let maxStops = 5

  let onPlan: ([StopInput], Bool) -> Void
  @Environment(\.dismiss) private var dismiss
  @State private var stops: [StopInput] = []
  @State private var draft = ""
  @State private var suggestOrder = false

  private var canAdd: Bool {
    let name = draft.trimmingCharacters(in: .whitespaces)
    return !name.isEmpty && stops.count < Self.maxStops
      && !stops.contains { $0.cityName.caseInsensitiveCompare(name) == .orderedSame }
  }

  var body: some View {
    NavigationStack {
      List {
        Section {
          HStack {
            TextField(stops.count < Self.maxStops ? "Add a city" : "Up to \(Self.maxStops) cities", text: $draft)
              .submitLabel(.done)
              .onSubmit(add)
            Button("Add", action: add).disabled(!canAdd)
          }
        }
        if !stops.isEmpty {
          Section {
            ForEach($stops, id: \.cityName) { $stop in
              Stepper(value: Binding(get: { stop.nights ?? 2 }, set: { stop.nights = $0 }), in: 1...14) {
                VStack(alignment: .leading) {
                  Text(stop.cityName).font(.lociBody())
                  Text("\(stop.nights ?? 2) night\((stop.nights ?? 2) == 1 ? "" : "s")").font(.caption).foregroundStyle(.secondary)
                }
              }
            }
            .onMove { stops.move(fromOffsets: $0, toOffset: $1) }
            .onDelete { stops.remove(atOffsets: $0) }
          } header: {
            Text("In this order")
          } footer: {
            Text("Travel between cities is an estimate — check times before you book.")
          }
        }
        Section {
          Toggle("Suggest the best order", isOn: $suggestOrder)
        }
      }
      .environment(\.editMode, .constant(stops.count > 1 ? .active : .inactive))
      .navigationTitle("Several cities")
      .navigationBarTitleDisplayMode(.inline)
      .toolbar {
        ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
        ToolbarItem(placement: .confirmationAction) {
          Button("Plan trip") {
            onPlan(stops, suggestOrder)
            dismiss()
          }
          .disabled(stops.count < 2)
        }
      }
    }
  }

  private func add() {
    guard canAdd else { return }
    stops.append(StopInput(cityName: draft.trimmingCharacters(in: .whitespaces), nights: 2))
    draft = ""
  }
}

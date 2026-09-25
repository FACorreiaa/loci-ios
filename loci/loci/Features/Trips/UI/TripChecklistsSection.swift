import LociConnectProto
import SwiftUI

/// Packing suggestions, the packing list and expenses (web:
/// components/trip/TripChecklists.tsx), synced through TripService so a tick
/// on the phone shows on the web. Suggestions are offered, never imposed:
/// nothing joins the list until the traveller says so.
struct TripChecklistsSection: View {
  @Bindable var store: TripChecklistStore

  @State private var packText = ""
  @State private var expenseLabel = ""
  @State private var expenseAmount = ""

  var body: some View {
    // The error alert lives on TripEditorView: a modifier on this Group would
    // attach one alert per section and only once the row scrolls into view.
    Group {
      if !store.openSuggestions.isEmpty { suggestionsSection }
      packingSection
      expensesSection
    }
  }

  // MARK: - Suggestions

  private var suggestionsSection: some View {
    Section {
      ForEach(store.openSuggestions, id: \.text) { suggestion in
        HStack(alignment: .top, spacing: 10) {
          if store.canEdit {
            Button("Add \(suggestion.text) to the packing list", systemImage: "plus.circle") {
              Task { await store.accept(suggestion) }
            }
            .labelStyle(.iconOnly).foregroundStyle(Color.lociForest).buttonStyle(.borderless)
          } else {
            Image(systemName: suggestion.essential ? "checkmark.seal" : "circle").foregroundStyle(Color.lociMutedInk)
          }
          VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
              Text(suggestion.text).font(.lociBody(15)).foregroundStyle(Color.lociInk)
              if suggestion.essential {
                Text("DON'T FORGET").font(.lociCoord(9)).foregroundStyle(Color.lociCoral)
                  .padding(.horizontal, 6).padding(.vertical, 2)
                  .background(Color.lociCoral.opacity(0.15), in: Capsule())
              }
            }
            if !suggestion.reason.isEmpty {
              Text(suggestion.reason).font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
            }
          }
          Spacer(minLength: 0)
          if store.canEdit {
            Button("Dismiss \(suggestion.text)", systemImage: "xmark") { Task { await store.dismiss(suggestion) } }
              .labelStyle(.iconOnly).foregroundStyle(Color.lociMutedInk).buttonStyle(.borderless)
          }
        }
      }
      if store.weatherIsEstimated {
        Label("Weather-based items use an estimated forecast.", systemImage: "info.circle")
          .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      }
    } header: {
      HStack {
        Label("Suggested for this trip", systemImage: "sparkles")
        Spacer()
        if store.canEdit {
          Button("Add all \(store.openSuggestions.count)") { Task { await store.acceptAll() } }
            .font(.lociCaption(12)).textCase(nil)
        }
      }
    }
    .listRowBackground(Color.lociCard)
  }

  // MARK: - Packing

  private var packingSection: some View {
    Section {
      if store.availability == .unavailable {
        Text("Your packing list and expenses will sync here once checklists are available on your account.")
          .font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
      } else if case .failed = store.availability {
        VStack(alignment: .leading, spacing: 8) {
          Text("Couldn't load your packing list and expenses.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
          Button("Try again") { Task { await store.retry() } }.font(.lociCaption(13).weight(.semibold)).tint(Color.lociForest)
        }
      } else {
        if store.availability == .cached {
          HStack(spacing: 8) {
            Text("Showing the copy on this phone. Edits need a connection.").font(.lociCaption()).foregroundStyle(Color.lociMutedInk)
            Spacer(minLength: 4)
            Button("Retry") { Task { await store.retry() } }.font(.lociCaption(13).weight(.semibold)).tint(Color.lociForest)
          }
        }
        ForEach(store.packing, id: \.id) { item in
          Button {
            Task { await store.toggle(item) }
          } label: {
            HStack(spacing: 10) {
              Image(systemName: item.done ? "checkmark.square.fill" : "square")
                .foregroundStyle(item.done ? Color.lociForest : Color.lociMutedInk)
              Text(item.text)
                .font(.lociBody(15))
                .strikethrough(item.done)
                .foregroundStyle(item.done ? Color.lociMutedInk : Color.lociInk)
              Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityValue(item.done ? "Packed" : "Not packed")
          .swipeActions { Button("Remove", role: .destructive) { Task { await store.delete(item) } } }
        }
        HStack {
          TextField("Add an item…", text: $packText).submitLabel(.done).onSubmit(addPack)
          Button("Add", systemImage: "plus", action: addPack)
            .labelStyle(.iconOnly).buttonStyle(.borderless)
            .disabled(packText.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .disabled(!store.canEdit)
      }
    } header: {
      HStack {
        Label("Packing", systemImage: "suitcase")
        Spacer()
        if let summary = store.packedSummary { Text(summary).font(.lociCoord(10)).textCase(nil) }
      }
    }
    .listRowBackground(Color.lociCard)
  }

  private func addPack() {
    let text = packText
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    packText = ""
    Task { await store.addPacking(text) }
  }

  // MARK: - Expenses

  @ViewBuilder private var expensesSection: some View {
    if store.availability != .unavailable, !store.isFailed {
      Section {
        ForEach(store.expenses, id: \.id) { item in
          HStack {
            Text(item.text).font(.lociBody(15)).foregroundStyle(Color.lociInk)
            Spacer()
            Text(TripChecklist.formatMoney(item.amountMinor, currency: item.currency.isEmpty ? store.currency : item.currency))
              .font(.lociCoord(12)).monospacedDigit().foregroundStyle(Color.lociInk)
          }
          .swipeActions { Button("Remove", role: .destructive) { Task { await store.delete(item) } } }
        }
        HStack {
          TextField("What for…", text: $expenseLabel)
          TextField("0.00", text: $expenseAmount)
            .keyboardType(.decimalPad).multilineTextAlignment(.trailing).frame(maxWidth: 90)
          Button("Add expense", systemImage: "plus", action: addExpense)
            .labelStyle(.iconOnly).buttonStyle(.borderless)
            .disabled(expenseLabel.trimmingCharacters(in: .whitespaces).isEmpty || expenseAmount.isEmpty)
        }
        .disabled(!store.canEdit)
      } header: {
        HStack {
          Label("Expenses", systemImage: "wallet.bifold")
          Spacer()
          Text(store.totalLabel).font(.lociCoord(11)).monospacedDigit().textCase(nil)
        }
      } footer: {
        Text("In \(store.currency).").font(.lociCaption(11))
      }
      .listRowBackground(Color.lociCard)
    }
  }

  private func addExpense() {
    let label = expenseLabel
    let amount = expenseAmount
    guard TripChecklist.amountMinor(from: amount, currency: store.currency) != nil else {
      store.error = "Enter the amount as a number, like 12.50."
      return
    }
    expenseLabel = ""
    expenseAmount = ""
    Task { await store.addExpense(label: label, amount: amount) }
  }
}

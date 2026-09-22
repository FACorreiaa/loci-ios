import LociConnectProto
import SwiftUI

/// Region and units (web: LocaleSettings). Sends UpdateUserProfile with
/// timezone, units and currency — the same three fields web sends.
struct LocaleSettingsView: View {
  /// web: lib/locale.ts CURRENCY_OPTIONS
  static let currencies: [(code: String, label: String)] = [
    ("EUR", "Euro (€)"), ("GBP", "British pound (£)"), ("USD", "US dollar ($)"), ("CHF", "Swiss franc (CHF)"),
    ("JPY", "Japanese yen (¥)"), ("CAD", "Canadian dollar (C$)"), ("AUD", "Australian dollar (A$)"), ("BRL", "Brazilian real (R$)"),
  ]

  @State private var timezone = TimeZone.current.identifier
  @State private var units = "metric"
  @State private var currency = "EUR"
  @State private var loaded: LocaleValues?
  @State private var error: String?
  @State private var isSaving = false

  private var isDirty: Bool {
    guard let loaded else { return false }
    return loaded != LocaleValues(timezone: timezone, units: units, currency: currency)
  }

  var body: some View {
    Form {
      Section {
        Picker("Time zone", selection: $timezone) {
          ForEach(TimeZone.knownTimeZoneIdentifiers, id: \.self) { Text($0.replacingOccurrences(of: "_", with: " ")).tag($0) }
        }.pickerStyle(.navigationLink)
      } footer: {
        Text("Used for trip days and the times in your itineraries.")
      }
      Section("Units") {
        Picker("Units", selection: $units) {
          Text("Metric — kilometres and metres").tag("metric")
          Text("Imperial — miles and feet").tag("imperial")
        }.pickerStyle(.inline).labelsHidden()
      }
      Section("Currency") {
        Picker("Currency", selection: $currency) { ForEach(Self.currencies, id: \.code) { Text($0.label).tag($0.code) } }
      }
    }
    .disabled(loaded == nil)
    .settingsStyle("Region and units")
    .toolbar {
      ToolbarItem(placement: .confirmationAction) { Button("Save") { Task { await save() } }.disabled(!isDirty || isSaving) }
    }
    .errorAlert($error)
    .task { await load() }
  }

  private func load() async {
    do {
      let profile = try await rpc("Could not load your settings.") {
        await SettingsClients.user.getUserProfile(request: .init(), headers: [:])
      }.profile
      if !profile.timezone.isEmpty { timezone = profile.timezone }
      if !profile.units.isEmpty { units = profile.units }
      if !profile.currency.isEmpty { currency = profile.currency }
      loaded = LocaleValues(timezone: timezone, units: units, currency: currency)
    } catch { self.error = error.userMessage }
  }

  private func save() async {
    isSaving = true
    defer { isSaving = false }
    var request = Loci_User_UpdateUserProfileRequest()
    request.params.timezone = timezone
    request.params.units = units
    request.params.currency = currency
    do {
      _ = try await rpc("Could not save.", request) { await SettingsClients.user.updateUserProfile(request: $0, headers: [:]) }
      loaded = LocaleValues(timezone: timezone, units: units, currency: currency)
    } catch { self.error = error.userMessage }
  }
}

/// The three locale fields as last saved, to tell whether the form changed.
struct LocaleValues: Equatable {
  var timezone: String
  var units: String
  var currency: String
}

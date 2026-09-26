import LociConnectProto
import SwiftUI

/// Who may open a trip, and its link (web: TripSharePanel). Replaces the old
/// one-tap "make public": four levels, and private is always one tap away.
/// Friends and link viewers get a read-only copy without notes or bookings.
struct TripShareMenu: View {
  let tripID: String
  @State private var visibility: TripVisibility
  @State private var shareCode: String
  @State private var isSaving = false
  @State private var error: String?

  init(trip: Loci_Trip_TripDraft) {
    tripID = trip.id
    _visibility = State(initialValue: TripVisibility(trip.visibility))
    _shareCode = State(initialValue: trip.shareCode)
  }

  var body: some View {
    Menu {
      Picker("Who can see this trip", selection: Binding(get: { visibility }, set: { choose($0) })) {
        ForEach(TripVisibility.allCases) { level in
          Label {
            Text(level.label)
            Text(level.detail)
          } icon: {
            Image(systemName: level.systemImage)
          }
          .tag(level)
        }
      }
      .pickerStyle(.inline)
      if visibility.hasLink, let url = SocialLinks.sharedTrip(code: shareCode), !shareCode.isEmpty {
        ShareLink(item: url) { Label("Share link", systemImage: "square.and.arrow.up") }
      }
    } label: {
      Label("Share", systemImage: visibility == .onlyMe ? "square.and.arrow.up" : visibility.systemImage)
    }
    .disabled(isSaving)
    .errorAlert($error)
  }

  private func choose(_ level: TripVisibility) {
    guard level != visibility else { return }
    let previous = visibility
    visibility = level
    isSaving = true
    Task {
      defer { isSaving = false }
      do {
        let response = try await SocialAPI.setVisibility(tripID: tripID, level)
        shareCode = response.shareCode
        if level.hasLink { Analytics.capture(.shareLinkCreated, ["content_type": "trip"]) }
      } catch {
        visibility = previous
        self.error = error.userMessage
      }
    }
  }
}

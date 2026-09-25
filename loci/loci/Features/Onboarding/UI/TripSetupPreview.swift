import SwiftUI

/// `-designPreview tripSetup`: the wizard on its last step with three interests picked, offline.
struct TripSetupPreview: View {
  var body: some View {
    let store = TripSetupStore(service: PreviewTripSetupService())
    TripSetupView(store: store) {}
      .task {
        await store.load()
        store.answers.interests = ["Food & Dining", "History", "Nature & Parks"]
        await store.next()
        await store.next()
        await store.next()
      }
  }
}

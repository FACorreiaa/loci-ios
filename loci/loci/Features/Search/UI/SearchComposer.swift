import SwiftUI

/// The one search box: Send while idle, Stop while a search streams
/// (NATIVE_DESIGN: "The Stop button replaces Send while streaming").
/// Starting goes through `SearchSessionController`; when the server names the
/// session, `onStarted` gets the link to push.
struct SearchComposer: View {
  var placeholder = "Ask Loci — “3 days in Lisbon with kids”"
  var cityName: String?
  var latitude: Double?
  var longitude: Double?
  var sessionId: String?
  let onStarted: (SessionLink) -> Void

  @State private var controller = SearchSessionController.shared
  @State private var text = ""
  @State private var awaitingStart = false
  @State private var error: String?
  @State private var needsProfile = false
  @State private var confirmReplace = false
  @State private var showProfiles = false

  private var isStreaming: Bool { controller.state.isActive }

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField(placeholder, text: $text, axis: .vertical)
        .font(.lociBody())
        .lineLimit(1...4)
        .submitLabel(.send)
        .onSubmit(send)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(Color.lociCard, in: RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: LociTheme.cornerRadius, style: .continuous).stroke(Color.lociBorder))

      if isStreaming, awaitingStart || controller.startedLink != nil {
        Button("Stop", systemImage: "stop.fill") { controller.stop() }
          .labelStyle(.iconOnly).frame(width: LociTheme.minTapTarget, height: LociTheme.minTapTarget)
          .background(Color.lociCoral, in: Circle()).foregroundStyle(Color.lociPaper)
      } else {
        Button("Send", systemImage: "arrow.up") { send() }
          .labelStyle(.iconOnly).frame(width: LociTheme.minTapTarget, height: LociTheme.minTapTarget)
          .background(Color.lociForest, in: Circle()).foregroundStyle(Color.lociPaper)
          .disabled(text.trimmingCharacters(in: .whitespaces).isEmpty)
      }
    }
    .onChange(of: controller.startedLink) { _, link in
      guard awaitingStart, let link else { return }
      awaitingStart = false
      onStarted(link)
    }
    .confirmationDialog("A search is still running. Replace it?", isPresented: $confirmReplace, titleVisibility: .visible) {
      Button("Start the new search", role: .destructive) { start() }
    }
    .alert("Create a travel profile first", isPresented: $needsProfile) {
      Button("Not now", role: .cancel) {}
      Button("Create a profile") { showProfiles = true }
    } message: {
      Text("Searches use your default travel profile. Add one in Settings › Travel profiles.")
    }
    .sheet(isPresented: $showProfiles) { NavigationStack { TravelProfilesView() } }
    .errorAlert($error)
  }

  private func send() {
    guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return }
    if isStreaming { confirmReplace = true } else { start() }
  }

  private func start() {
    let query = text
    awaitingStart = true
    Task {
      do {
        try await controller.start(query: query, cityName: cityName, latitude: latitude, longitude: longitude, sessionId: sessionId)
        text = ""
      } catch SearchSessionController.StartError.noDefaultProfile {
        awaitingStart = false
        needsProfile = true
      } catch {
        awaitingStart = false
        self.error = error.userMessage
      }
    }
  }
}

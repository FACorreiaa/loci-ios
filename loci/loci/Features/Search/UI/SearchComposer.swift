import SwiftUI

/// The one search box: Send while idle, Stop while a search streams
/// (NATIVE_DESIGN: "The Stop button replaces Send while streaming").
/// Starting goes through `SearchSessionController`; when the server names the
/// session, `onStarted` gets the link to push.
struct SearchComposer: View {
  var placeholder = "Ask Loci — “3 days in Lisbon with kids”"
  /// Text another control puts in the box (a category chip); cleared once taken.
  var seed: Binding<String>?
  var cityName: String?
  var latitude: Double?
  var longitude: Double?
  var sessionId: String?
  var useDefaultProfile = true
  /// `.muse` draws the field as the Muse chat composer (musePill fill, radius 24). Behaviour is the same.
  var style: Style = .standard
  /// Bump to put the cursor in the field (the Muse header's "New chat").
  var focusRequest = 0
  /// Told when the field gains or loses the cursor: the Muse header's "is listening".
  var onFocusChange: (Bool) -> Void = { _ in }
  /// Offered the text before it becomes a search; returning true takes it
  /// (a standing request goes to the standing-task card instead).
  var intercept: ((String) -> Bool)?
  let onStarted: (SessionLink) -> Void

  enum Style { case standard, muse }

  private let controller = SearchSessionController.shared
  @State private var text = ""
  @State private var awaitingStart = false
  @State private var error: String?
  @State private var needsProfile = false
  @State private var confirmReplace = false
  @State private var showProfiles = false
  @FocusState private var isFocused: Bool

  private var isStreaming: Bool { controller.state.isActive }
  private var fieldRadius: CGFloat { style == .muse ? LociTheme.Muse.bubbleRadius : LociTheme.cornerRadius }

  var body: some View {
    HStack(alignment: .bottom, spacing: 8) {
      TextField(placeholder, text: $text, axis: .vertical)
        .font(style == .muse ? .museBody : .lociBody())
        .lineLimit(1...4)
        .submitLabel(.send)
        .onSubmit(send)
        .focused($isFocused)
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(
          style == .muse ? Color.musePill : Color.lociCard,
          in: RoundedRectangle(cornerRadius: fieldRadius, style: .continuous)
        )
        .overlay(
          RoundedRectangle(cornerRadius: fieldRadius, style: .continuous)
            .stroke(style == .muse ? Color.clear : Color.lociBorder)
        )

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
    .onChange(of: focusRequest) { isFocused = true }
    .onChange(of: isFocused) { _, focused in onFocusChange(focused) }
    .onChange(of: seed?.wrappedValue) { _, value in
      guard let value, !value.isEmpty else { return }
      text = value
      seed?.wrappedValue = ""
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
    if let intercept, intercept(text) {
      text = ""
      return
    }
    if isStreaming { confirmReplace = true } else { start() }
  }

  private func start() {
    let query = text
    awaitingStart = true
    Task {
      do {
        try await controller.start(
          query: query,
          cityName: cityName,
          latitude: latitude,
          longitude: longitude,
          sessionId: sessionId,
          useDefaultProfile: useDefaultProfile
        )
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

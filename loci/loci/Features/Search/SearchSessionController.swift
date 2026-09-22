import BackgroundTasks
import Connect
import Foundation
import LociConnectProto
import Observation
import SwiftProtobuf
import UIKit

/// The one running search, app-wide. Leaving the screen that started it does
/// not stop it; backgrounding the app keeps reading for as long as iOS allows,
/// then detaches (the server keeps generating) and reconciles later.
///
/// Lifecycle, mirroring web's streamingService + resume-live.ts:
/// start → StreamChat → events reduced into `state` → envelope saved after each
/// event → COMPLETE/ERROR → local notification unless the user is looking at it.
/// Detached → on return, StreamChat{sessionId, resumeToken} replays what was
/// missed; if that ends without COMPLETE, GetChatSession is polled with backoff.
@MainActor @Observable final class SearchSessionController {
  static let shared = SearchSessionController()
  static let reconcileTaskID = "com.fernandocorreia.loci.search-reconcile"
  /// The server gives a generation five minutes (chat_process_stream.go worker deadline).
  static let generationDeadline: TimeInterval = 5 * 60

  enum StartError: LocalizedError {
    case noDefaultProfile

    var errorDescription: String? { "Create a travel profile first. Searches use your default profile." }
  }

  private(set) var state = SearchState()
  /// Set when the server names the session; the screen that started the search pushes its results.
  var startedLink: SessionLink?
  /// The session a results screen is showing. No notification for it while the app is active.
  var viewingSessionId: String?

  private var envelope: SearchEnvelope?
  private var streamTask: Task<Void, Never>?
  private var backgroundTask: UIBackgroundTaskIdentifier = .invalid
  private var isForeground = true

  private let store: SearchStore
  private let streams: ChatStreamClient
  private let notifier: SearchNotifier
  private let chat = Loci_Chat_ChatServiceClient(client: ConnectTransport.shared.protocolClient)
  private let profiles = Loci_Profile_ProfileServiceClient(client: ConnectTransport.shared.protocolClient)

  init(store: SearchStore = SearchStore(), streams: ChatStreamClient = ChatStreamClient(), notifier: SearchNotifier = SearchNotifier()) {
    self.store = store
    self.streams = streams
    self.notifier = notifier
    self.envelope = store.loadEnvelope()
  }

  // MARK: - Starting and stopping

  /// Start a search. Replaces any running one: one active search at a time.
  /// `sessionId` continues an existing conversation (web: follow-up messages).
  /// `useDefaultProfile` is false for Discover and Nearby, which web runs
  /// without a profile; the dashboard and chat need one.
  func start(
    query: String,
    cityName: String? = nil,
    latitude: Double? = nil,
    longitude: Double? = nil,
    profileId: String? = nil,
    sessionId: String? = nil,
    useDefaultProfile: Bool = true
  ) async throws {
    let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    var profile = profileId
    if profile == nil, useDefaultProfile {
      profile = try await defaultProfileId()
      if profile == nil { throw StartError.noDefaultProfile }
    }

    stop()
    _ = await PushNotificationManager.shared.requestAuthorizationIfNeeded()

    let envelope = SearchEnvelope(
      sessionId: sessionId,
      requestId: UUID().uuidString.lowercased(),
      profileId: profile,
      query: trimmed,
      cityName: cityName,
      latitude: latitude,
      longitude: longitude,
      startedAt: Date(),
      finished: false,
      notified: false
    )
    self.envelope = envelope
    store.save(envelope)

    var fresh = SearchState()
    fresh.query = trimmed
    fresh.cityName = cityName
    fresh.sessionId = sessionId
    fresh.status = .streaming
    state = fresh
    startedLink = nil
    open(Self.request(from: envelope, resuming: false))
  }

  /// The user tapped Stop. The server may finish anyway; nothing is notified.
  func stop() {
    streamTask?.cancel()
    streamTask = nil
    if state.isActive { state.status = state.hasResult ? .completed : .failed("Stopped.") }
    if var envelope {
      envelope.finished = true
      envelope.notified = true
      self.envelope = envelope
    }
    store.clearEnvelope()
    endBackgroundTask()
  }

  // MARK: - Reading the stream

  private func open(_ request: Loci_Chat_ChatRequest) {
    let events = streams.events(request)
    streamTask = Task { [weak self] in
      do {
        for try await event in events {
          guard let self else { return }
          await self.receive(event)
        }
        await self?.streamEnded()
      } catch is CancellationError {
        // Stopped by the user or detached for the background; both handled by the caller.
      } catch {
        await self?.streamFailed(error)
      }
    }
  }

  private func receive(_ event: Loci_Chat_StreamEvent) async {
    let effect = state.apply(event)
    if var envelope {
      envelope.sessionId = state.sessionId ?? envelope.sessionId
      envelope.lastEventId = state.lastEventId ?? envelope.lastEventId
      envelope.domain = state.domain ?? envelope.domain
      envelope.cityName = state.cityName ?? envelope.cityName
      self.envelope = envelope
      store.save(envelope)
    }
    switch effect {
    case .started(let link): startedLink = link
    case .completed, .failed: await finish()
    case nil: break
    }
  }

  /// The stream closed cleanly. Without COMPLETE the server is still going
  /// (a resume replays only what was buffered), so poll for the stored result.
  /// `streamTask` stays set while polling, so a return to the foreground does
  /// not start a second reader for the same search.
  private func streamEnded() async {
    defer { streamTask = nil }
    guard state.isActive else { return }
    state.status = .detached
    await pollUntilFinished()
  }

  private func streamFailed(_ error: Error) async {
    defer { streamTask = nil }
    // A dropped connection mid-search is not the search failing: the server keeps going.
    if case APIError.network = error, state.sessionId != nil {
      state.status = .detached
      await pollUntilFinished()
      return
    }
    state.status = .failed(error.userMessage)
    await finish()
  }

  private func finish() async {
    guard var envelope, !envelope.finished else { return }
    envelope.finished = true
    if state.status == .completed { store.saveResult(state) }
    let isViewing = isForeground && viewingSessionId != nil && viewingSessionId == state.sessionId
    if !envelope.notified, !isViewing, let link = state.link {
      envelope.notified = true
      await notifier.post(link: link, succeeded: state.status == .completed, query: state.query)
    }
    self.envelope = envelope
    store.clearEnvelope()
    endBackgroundTask()
  }

  // MARK: - Reattaching

  /// Replay what was missed, then poll if the replay does not reach COMPLETE.
  private func resume(_ envelope: SearchEnvelope) {
    guard envelope.sessionId != nil else {
      // Never got as far as a session id: nothing on the server to find.
      state.status = .failed("The search was interrupted before it started. Try again.")
      store.clearEnvelope()
      return
    }
    if state.sessionId != envelope.sessionId { state = Self.placeholder(from: envelope) }
    state.status = .detached
    // Without a resume token the server would start the search again (and spend
    // quota), so only ask the stored session.
    guard envelope.lastEventId != nil else {
      streamTask = Task { [weak self] in
        await self?.pollUntilFinished()
        self?.streamTask = nil
      }
      return
    }
    open(Self.request(from: envelope, resuming: true))
  }

  private func pollUntilFinished() async {
    guard let envelope, let sessionId = envelope.sessionId else { return }
    var delay: TimeInterval = 2
    while Date().timeIntervalSince(envelope.startedAt) < Self.generationDeadline + 30 {
      if Task.isCancelled || !state.isActive { return }
      if await checkServer(sessionId: sessionId, since: envelope.startedAt) { return }
      try? await Task.sleep(for: .seconds(delay))
      delay = min(delay * 2, 30)
    }
    state.status = .failed("This search didn't finish. Try it again.")
    await finish()
  }

  /// One GetChatSession. True when the session has a result saved after this
  /// search started (a follow-up reuses a session that already had one).
  @discardableResult private func checkServer(sessionId: String, since started: Date) async -> Bool {
    var request = Loci_Chat_GetChatSessionRequest()
    request.sessionID = sessionId
    guard
      let session = try? await rpc("", request, { await self.chat.getChatSession(request: $0, headers: [:]) }).session,
      session.hasCurrentItinerary, session.updatedAt.date >= started.addingTimeInterval(-5)
    else { return false }
    if state.destination == .itinerary || !state.hasResult {
      if state.destination == .itinerary { state.itinerary = session.currentItinerary }
      if state.cityData == nil, session.currentItinerary.hasGeneralCityData { state.cityData = session.currentItinerary.generalCityData }
    }
    state.status = .completed
    await finish()
    return true
  }

  // MARK: - App lifecycle

  func sceneDidEnterBackground() {
    isForeground = false
    guard state.isActive, backgroundTask == .invalid else { return }
    backgroundTask = UIApplication.shared.beginBackgroundTask(withName: "loci-search") { [weak self] in
      Task { @MainActor in self?.backgroundTimeExpired() }
    }
  }

  func sceneDidBecomeActive() {
    isForeground = true
    endBackgroundTask()
    guard streamTask == nil, let envelope, !envelope.finished else { return }
    resume(envelope)
  }

  /// iOS is about to suspend the app: let go of the stream, keep the envelope,
  /// and ask for a background refresh to check on the search.
  private func backgroundTimeExpired() {
    streamTask?.cancel()
    streamTask = nil
    if state.isActive { state.status = .detached }
    if let envelope { store.save(envelope) }
    Self.scheduleReconcile()
    endBackgroundTask()
  }

  private func endBackgroundTask() {
    guard backgroundTask != .invalid else { return }
    UIApplication.shared.endBackgroundTask(backgroundTask)
    backgroundTask = .invalid
  }

  // MARK: - Background refresh

  static func registerBackgroundTask() {
    BGTaskScheduler.shared.register(forTaskWithIdentifier: reconcileTaskID, using: nil) { task in
      guard let task = task as? BGAppRefreshTask else { return }
      let work = Task { @MainActor in
        let done = await SearchSessionController.shared.reconcileInBackground()
        task.setTaskCompleted(success: done)
      }
      task.expirationHandler = { work.cancel() }
    }
  }

  static func scheduleReconcile() {
    let request = BGAppRefreshTaskRequest(identifier: reconcileTaskID)
    request.earliestBeginDate = Date(timeIntervalSinceNow: 60)
    try? BGTaskScheduler.shared.submit(request)
  }

  /// Called by the background refresh: one server check, then notify or reschedule.
  func reconcileInBackground() async -> Bool {
    guard let envelope = envelope ?? store.loadEnvelope(), !envelope.finished, let sessionId = envelope.sessionId else { return true }
    self.envelope = envelope
    if state.sessionId != sessionId { state = Self.placeholder(from: envelope) }
    state.status = .detached
    if await checkServer(sessionId: sessionId, since: envelope.startedAt) { return true }
    if Date().timeIntervalSince(envelope.startedAt) > Self.generationDeadline + 60 {
      state.status = .failed("This search didn't finish. Try it again.")
      await finish()
      return true
    }
    Self.scheduleReconcile()
    return false
  }

  // MARK: - Opening a session

  /// The state to show for a session link: the live search, this phone's saved
  /// copy, or the server's (itineraries only; web does the same).
  func state(for link: SessionLink) async -> SearchState? {
    if state.sessionId == link.sessionId { return state }
    if let saved = store.loadResult(for: link) { return saved }
    var request = Loci_Chat_GetChatSessionRequest()
    request.sessionID = link.sessionId
    guard let session = try? await rpc("", request, { await self.chat.getChatSession(request: $0, headers: [:]) }).session,
      session.hasCurrentItinerary
    else { return nil }
    let restored = SearchState.restored(link: link, result: session.currentItinerary)
    return restored.hasResult ? restored : nil
  }

  // MARK: - Helpers

  private func defaultProfileId() async throws -> String? {
    let response = try await rpc("Could not load your travel profiles.") {
      await self.profiles.getUserPreferenceProfiles(request: .init(), headers: [:])
    }
    return (response.profiles.first(where: \.isDefault) ?? response.profiles.first)?.id
  }

  private static func placeholder(from envelope: SearchEnvelope) -> SearchState {
    var state = SearchState()
    state.sessionId = envelope.sessionId
    state.query = envelope.query
    state.cityName = envelope.cityName
    state.domain = envelope.domain
    state.destination = SearchDestination(domain: envelope.domain ?? "")
    state.lastEventId = envelope.lastEventId
    return state
  }

  /// The same ChatRequest fields web sends (chatStream.ts), plus the resume pair on a reattach.
  static func request(from envelope: SearchEnvelope, resuming: Bool) -> Loci_Chat_ChatRequest {
    var request = Loci_Chat_ChatRequest()
    request.message = envelope.query
    request.requestID = envelope.requestId
    if let sessionId = envelope.sessionId { request.sessionID = sessionId }
    if let cityName = envelope.cityName, !cityName.isEmpty { request.cityName = cityName }
    if let profileId = envelope.profileId { request.profileID = profileId }
    if let latitude = envelope.latitude, let longitude = envelope.longitude {
      request.userLocation.latitude = latitude
      request.userLocation.longitude = longitude
    }
    if resuming, let token = envelope.lastEventId { request.resumeToken = token }
    return request
  }
}

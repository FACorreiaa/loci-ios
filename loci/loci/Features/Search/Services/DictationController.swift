import AVFoundation
import Connect
import Foundation
import LociConnectProto
import Observation

/// Speech-to-text on the server (loci.speech.SpeechService). What happens with
/// the transcript afterwards is the composer's job: spoken or typed, it is the
/// same request.
nonisolated enum SpeechAPI {
  static let speech = Loci_Speech_SpeechServiceClient(client: ConnectTransport.shared.protocolClient)
}

/// Why a dictation produced no text, with the words the user sees.
nonisolated enum DictationError: Error, Equatable {
  case permissionDenied
  case micFailed
  /// The server has no transcription configured: the mic hides for this screen.
  case unavailable
  case rejected
  case busy
  case failed
  case nothingHeard

  /// Map the Transcribe RPC's Connect code.
  static func from(code: Code) -> DictationError {
    switch code {
    // Only "not configured" hides the mic. `Unavailable` is also a transient
    // transcription failure, so it stays retryable.
    case .failedPrecondition: .unavailable
    case .invalidArgument: .rejected
    case .resourceExhausted, .unavailable: .busy
    default: .failed
    }
  }

  /// The transcript to use, or `nothingHeard` when the server heard no speech
  /// (an empty transcript is an answer, not a server error).
  static func transcript(_ text: String) throws(DictationError) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw .nothingHeard }
    return trimmed
  }

  var message: String {
    switch self {
    case .permissionDenied: "Loci can't use the microphone. Turn it on in Settings › Loci › Microphone."
    case .micFailed: "The microphone didn't start. Try again."
    case .unavailable: "Dictation isn't available. Type your request instead."
    case .rejected: "Loci couldn't read that recording. Try again."
    case .busy: "Dictation is busy. Try again in a minute."
    case .failed: "Dictation didn't work. Try again."
    case .nothingHeard: "I couldn't hear anything in that."
    }
  }
}

/// Add a transcript to whatever is already typed: trimmed, one space between.
nonisolated func appendTranscript(_ existing: String, _ new: String) -> String {
  let addition = new.trimmingCharacters(in: .whitespacesAndNewlines)
  let base = existing.trimmingCharacters(in: .whitespacesAndNewlines)
  if addition.isEmpty { return base }
  if base.isEmpty { return addition }
  return base + " " + addition
}

/// Decides when somebody has stopped talking
/// (web: loci-client/src/lib/audio/silence.ts).
///
/// Only after they have started: a pause before the first word is someone
/// thinking of what to ask, and stopping then would send nothing. In a loud place
/// this may never fire, which is why the tap and the recording cap stay.
nonisolated struct SilenceDetector: Sendable {
  /// Average power above this counts as speech. Quiet enough for a normal voice
  /// at arm's length; AVAudioRecorder reports 0 dB for the loudest it can hear.
  static let speechLevel: Float = -38
  /// How long a pause means they have finished.
  static let silenceAfter: TimeInterval = 1.2

  private var heardAt: TimeInterval?

  /// Takes a loudness and the time it was measured; true means stop.
  mutating func feed(power: Float, at now: TimeInterval) -> Bool {
    if power >= Self.speechLevel {
      heardAt = now
      return false
    }
    guard let heardAt else { return false }
    return now - heardAt >= Self.silenceAfter
  }
}

/// Records a trip request and turns it into text. One tap starts, the next
/// stops; a recording also stops by itself after `maxDuration`.
///
/// `toggle()` called while idle suspends for the whole recording and upload and
/// returns the transcript; called while recording it only ends the recording.
@MainActor @Observable
final class DictationController {
  enum State: Equatable { case idle, recording, transcribing }

  static let maxDuration: Duration = .seconds(45)
  /// The server's allowlist names AAC in an MP4 container `audio/mp4`, not `audio/m4a`.
  static let mimeType = "audio/mp4"

  typealias Transcribe = @Sendable (Data) async -> ResponseMessage<Loci_Speech_TranscribeResponse>

  private(set) var state: State = .idle
  var error: String?
  /// True once the server says it cannot transcribe; the composer hides the mic.
  private(set) var isUnavailable = false

  @ObservationIgnored private let transcribeCall: Transcribe
  @ObservationIgnored private var recorder: AVAudioRecorder?
  @ObservationIgnored private var stopSignal: CheckedContinuation<Bool, Never>?
  @ObservationIgnored private var autoStop: Task<Void, Never>?
  @ObservationIgnored private var silenceWatch: Task<Void, Never>?
  /// The assistant ends a recording on a pause; the search composer doesn't.
  @ObservationIgnored private let stopsOnSilence: Bool

  init(
    stopsOnSilence: Bool = false,
    transcribe: @escaping Transcribe = { audio in
      var request = Loci_Speech_TranscribeRequest()
      request.audio = audio
      request.mimeType = DictationController.mimeType
      return await SpeechAPI.speech.transcribe(request: request)
    }
  ) {
    self.stopsOnSilence = stopsOnSilence
    transcribeCall = transcribe
  }

  func toggle() async -> String? {
    switch state {
    case .recording:
      finishRecording(keep: true)
      return nil
    case .transcribing:
      return nil
    case .idle:
      return await recordAndTranscribe()
    }
  }

  /// Drop a recording in progress without uploading it (the view went away).
  func cancel() {
    if state == .recording { finishRecording(keep: false) }
  }

  /// Upload a recording and return its transcript.
  func transcribe(_ audio: Data) async throws(DictationError) -> String {
    let call = transcribeCall
    let response = await withAuthRetry { await call(audio) }
    guard let message = response.message else {
      throw DictationError.from(code: response.error?.code ?? response.code)
    }
    return try DictationError.transcript(message.text)
  }

  // MARK: - Recording

  private func recordAndTranscribe() async -> String? {
    error = nil
    guard await hasPermission() else {
      error = DictationError.permissionDenied.message
      return nil
    }
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("dictation-\(UUID().uuidString)")
      .appendingPathExtension("m4a")
    defer { try? FileManager.default.removeItem(at: url) }

    do {
      try startRecorder(at: url)
    } catch {
      deactivateSession()
      self.error = DictationError.micFailed.message
      return nil
    }

    state = .recording
    autoStop = Task { [weak self] in
      try? await Task.sleep(for: Self.maxDuration)
      guard !Task.isCancelled else { return }
      self?.finishRecording(keep: true)
    }
    if stopsOnSilence { watchForSilence() }
    let keep = await withCheckedContinuation { stopSignal = $0 }

    guard keep else {
      state = .idle
      return nil
    }
    state = .transcribing
    defer { state = .idle }

    guard let audio = try? Data(contentsOf: url), !audio.isEmpty else {
      error = DictationError.nothingHeard.message
      return nil
    }
    do {
      return try await transcribe(audio)
    } catch {
      if error == .unavailable { isUnavailable = true }
      self.error = error.message
      return nil
    }
  }

  private func hasPermission() async -> Bool {
    switch AVAudioApplication.shared.recordPermission {
    case .granted: true
    case .denied: false
    default: await AVAudioApplication.requestRecordPermission()
    }
  }

  private func startRecorder(at url: URL) throws {
    let session = AVAudioSession.sharedInstance()
    try session.setCategory(.record, mode: .default)
    try session.setActive(true)
    let settings: [String: Any] = [
      AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
      AVSampleRateKey: 16_000,
      AVNumberOfChannelsKey: 1,
      AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue,
    ]
    let recorder = try AVAudioRecorder(url: url, settings: settings)
    recorder.isMeteringEnabled = stopsOnSilence
    guard recorder.record() else { throw DictationError.micFailed }
    self.recorder = recorder
  }

  private func watchForSilence() {
    silenceWatch = Task { [weak self] in
      var detector = SilenceDetector()
      let started = ContinuousClock.now
      while !Task.isCancelled {
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled, let self, let recorder = self.recorder else { return }
        recorder.updateMeters()
        let elapsed = started.duration(to: .now) / .seconds(1)
        if detector.feed(power: recorder.averagePower(forChannel: 0), at: elapsed) {
          self.finishRecording(keep: true)
          return
        }
      }
    }
  }

  private func finishRecording(keep: Bool) {
    autoStop?.cancel()
    autoStop = nil
    silenceWatch?.cancel()
    silenceWatch = nil
    recorder?.stop()
    recorder = nil
    deactivateSession()
    stopSignal?.resume(returning: keep)
    stopSignal = nil
  }

  private func deactivateSession() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

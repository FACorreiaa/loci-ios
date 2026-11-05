import AVFoundation
import UIKit

/// What the controller needs from speech, so a test can listen in.
@MainActor
protocol AskLociSpeaking: AnyObject {
  func say(_ text: String)
  func stop()
}

/// Reads an answer aloud, one sentence at a time, on the device.
///
/// The session is held only while there is something to say, and ducks whatever
/// else is playing. VoiceOver users get announcements instead: two voices over
/// each other help nobody.
@MainActor
final class AskLociSpeaker: NSObject, AskLociSpeaking {
  private let synthesizer = AVSpeechSynthesizer()
  private var queued = 0

  override init() {
    super.init()
    synthesizer.delegate = self
  }

  func say(_ text: String) {
    if UIAccessibility.isVoiceOverRunning {
      UIAccessibility.post(notification: .announcement, argument: text)
      return
    }
    if queued == 0 { activateSession() }
    queued += 1
    synthesizer.speak(AVSpeechUtterance(string: text))
  }

  func stop() {
    guard queued > 0 else { return }
    queued = 0
    synthesizer.stopSpeaking(at: .immediate)
    deactivateSession()
  }

  func finishedOne() {
    guard queued > 0 else { return }
    queued -= 1
    if queued == 0 { deactivateSession() }
  }

  private func activateSession() {
    let session = AVAudioSession.sharedInstance()
    try? session.setCategory(.playback, mode: .spokenAudio, options: .duckOthers)
    try? session.setActive(true)
  }

  private func deactivateSession() {
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }
}

extension AskLociSpeaker: AVSpeechSynthesizerDelegate {
  nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
    Task { @MainActor in finishedOne() }
  }
}
